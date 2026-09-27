class_name PlayerController
extends CharacterBody3D
## Герой.
##
## Управление сознательно «тяжёлое»: это человек в реанимационном отделении,
## а не шутерный протагонист. При этом камера по-прежнему не вращается мышью —
## мышью поворачивается ГОЛОВА в ограниченном конусе, а ракурс выбирает
## режиссёр. Поэтому взаимодействие идёт лучом из головы, а не из центра кадра.

signal interactable_changed(interactable: Interactable)
signal noise_emitted(amount: float, position: Vector3)
signal stepped(surface: StringName, position: Vector3)
signal pause_requested()

const WALK_SPEED := 1.45
const SLOW_SPEED := 0.72
const RUSH_SPEED := 2.85
const ACCELERATION := 7.0
const DECELERATION := 9.5
const HEAD_YAW_LIMIT := 1.25
const HEAD_PITCH_MIN := -0.85
const HEAD_PITCH_MAX := 0.75
const STEP_DISTANCE := 0.72
const NOISE_WALK := 0.18
const NOISE_RUSH := 0.85

@export var mouse_sensitivity := 0.0022
@export var invert_y := false
@export var can_move := true

var avatar: Avatar
var head: Node3D
var look_ray: RayCast3D

var move_speed_scale := 1.0
var head_yaw := 0.0
var head_pitch := 0.0
var is_holding_breath := false
var current_noise := 0.0

var _input_basis_forward := Vector3.FORWARD
var _input_basis_right := Vector3.RIGHT
var _step_accumulator := 0.0
var _focus_interactable: Interactable
var _sprint_energy := 1.0
var _gravity := 9.8


func _ready() -> void:
	add_to_group(&"player")
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.7
	shape.shape = capsule
	shape.position = Vector3(0, 0.85, 0)
	add_child(shape)
	collision_layer = 1
	collision_mask = 1

	avatar = Avatar.new()
	avatar.name = "Avatar"
	add_child(avatar)
	head = avatar.head_node

	look_ray = RayCast3D.new()
	look_ray.name = "LookRay"
	look_ray.target_position = Vector3(0, 0, -2.4)
	# 1 — мир (стены и мебель), 4 — интерактивные зоны: сквозь стены не достать.
	look_ray.collision_mask = 1 | 4
	look_ray.collide_with_areas = true
	look_ray.enabled = true
	avatar.head_node.add_child(look_ray)

	mouse_sensitivity = float(SaveSystem.get_setting("input/sensitivity", mouse_sensitivity))
	invert_y = bool(SaveSystem.get_setting("input/invert_y", false))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not GameState.game_paused and can_move:
		var motion := event as InputEventMouseMotion
		# Голова, а не камера: конус ограничен, дальше герой просто не смотрит.
		head_yaw = clampf(head_yaw - motion.relative.x * mouse_sensitivity, -HEAD_YAW_LIMIT, HEAD_YAW_LIMIT)
		var pitch_delta := motion.relative.y * mouse_sensitivity * (-1.0 if invert_y else 1.0)
		head_pitch = clampf(head_pitch - pitch_delta, HEAD_PITCH_MIN, HEAD_PITCH_MAX)
	elif event.is_action_pressed(&"interact") and _focus_interactable != null:
		_focus_interactable.interact(self)
	elif event.is_action_pressed(&"pause"):
		pause_requested.emit()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	_update_head(delta)
	_update_movement(delta)
	_update_breath()
	_update_focus()
	_update_steps(delta)
	move_and_slide()


func teleport(position_in_world: Vector3, yaw := 0.0) -> void:
	global_position = position_in_world
	rotation.y = yaw
	velocity = Vector3.ZERO


# --- Движение -----------------------------------------------------------------

func _update_movement(delta: float) -> void:
	var input := Vector2.ZERO
	if can_move and not GameState.game_paused:
		input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")

	# Базис ввода не переключается мгновенно после склейки кадра: герой
	# продолжает идти «как шёл», и только потом направление уточняется.
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var forward := -camera.global_transform.basis.z
		forward.y = 0.0
		if forward.length() > 0.01:
			forward = forward.normalized()
			_input_basis_forward = _input_basis_forward.lerp(forward, minf(delta * 2.6, 1.0)).normalized()
			_input_basis_right = Vector3(_input_basis_forward.z, 0.0, -_input_basis_forward.x)

	var desired := (_input_basis_forward * input.y + _input_basis_right * input.x)
	if desired.length() > 0.01:
		desired = desired.normalized()

	# Задержка дыхания резко снижает шум и скорость — это осознанный выбор.
	var speed := WALK_SPEED
	if _sprint_energy < 0.15:
		speed = SLOW_SPEED
	if input.length() > 0.85 and _sprint_energy > 0.2:
		speed = RUSH_SPEED
	if is_holding_breath:
		speed *= 0.55
	speed *= move_speed_scale
	if GameState.consciousness < 0.6:
		speed *= lerpf(0.45, 1.0, GameState.consciousness)

	var target := desired * speed
	if desired.length() > 0.01:
		velocity.x = move_toward(velocity.x, target.x, ACCELERATION * delta * 4.0)
		velocity.z = move_toward(velocity.z, target.z, ACCELERATION * delta * 4.0)
	else:
		velocity.x = move_toward(velocity.x, 0.0, DECELERATION * delta)
		velocity.z = move_toward(velocity.z, 0.0, DECELERATION * delta)

	# Направление шага — расход сил: бежать по этому этажу почти нельзя.
	var consumed := velocity.length() / RUSH_SPEED
	if consumed > 0.6:
		_sprint_energy = maxf(0.0, _sprint_energy - delta * 0.16)
	else:
		_sprint_energy = minf(1.0, _sprint_energy + delta * 0.05)

	# Тело доворачивается туда, куда герой идёт.
	if desired.length() > 0.05:
		var target_yaw := atan2(-desired.x, -desired.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(delta * 3.4, 1.0))

	current_noise = lerpf(current_noise, 0.0, minf(delta * 1.6, 1.0))
	if desired.length() > 0.05:
		var level := NOISE_WALK if speed <= WALK_SPEED + 0.01 else NOISE_RUSH
		if is_holding_breath:
			level *= 0.35
		current_noise = maxf(current_noise, level)
		if level > 0.5:
			noise_emitted.emit(level * delta, global_position)


func _update_head(_delta: float) -> void:
	if head == null:
		return
	# Голова «плавает»: мышью её не удержать идеально ровно.
	var sway_x := sin(Time.get_ticks_msec() * 0.0007) * 0.006
	var sway_y := cos(Time.get_ticks_msec() * 0.00053) * 0.004
	head.rotation = Vector3(head_pitch + sway_y, head_yaw + sway_x, 0.0)
	# Дрожь от виталитетов передаётся голове, а через неё — композиции кадра.
	var tremor := GameState.tremor() * 0.01
	if tremor > 0.0001:
		var t := Time.get_ticks_msec() * 0.001
		head.rotation.x += sin(t * 17.0) * tremor
		head.rotation.y += cos(t * 23.0) * tremor


func _update_breath() -> void:
	var wanted := Input.is_action_pressed(&"hold_breath") and can_move
	is_holding_breath = wanted
	GameState.holding_breath = wanted


func _update_steps(delta: float) -> void:
	var horizontal := Vector2(velocity.x, velocity.z).length()
	if horizontal > 0.15:
		_step_accumulator += horizontal * delta
		if _step_accumulator >= STEP_DISTANCE:
			_step_accumulator = 0.0
			_do_step(horizontal)


func _do_step(horizontal_speed: float) -> void:
	var surface: StringName = &"tile"
	var from_point := global_position + Vector3(0, 0.6, 0)
	var to_point := global_position - Vector3(0, 1.2, 0)
	var space := PhysicsRayQueryParameters3D.create(from_point, to_point)
	space.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(space)
	if not hit.is_empty():
		var collider = hit.get("collider")
		if collider != null and collider.has_meta(&"surface"):
			surface = StringName(str(collider.get_meta(&"surface")))
	var volume := lerpf(-14.0, -3.0, clampf(horizontal_speed / RUSH_SPEED, 0.0, 1.0))
	if is_holding_breath:
		volume -= 6.0
	AudioDirector.footstep(surface, global_position, volume)
	stepped.emit(surface, global_position)


func _update_focus() -> void:
	if look_ray == null:
		return
	var found: Interactable = null
	if look_ray.is_colliding():
		var collider := look_ray.get_collider()
		if collider is Interactable and (collider as Interactable).enabled:
			found = collider
		elif collider is Node and (collider as Node).get_parent() is Interactable:
			var parent := (collider as Node).get_parent() as Interactable
			if parent != null and parent.enabled:
				found = parent
	if found != _focus_interactable:
		if _focus_interactable != null and is_instance_valid(_focus_interactable):
			_focus_interactable.set_focus(false)
		_focus_interactable = found
		if found != null:
			found.set_focus(true)
		interactable_changed.emit(found)


func focus_interactable() -> Interactable:
	return _focus_interactable


func set_speed_scale(value: float) -> void:
	move_speed_scale = clampf(value, 0.1, 3.0)
