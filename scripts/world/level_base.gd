class_name LevelBase
extends Node3D
## База уровня. Собирает каркас бита: окружение, героя, режиссёра камеры,
## экранные эффекты, HUD и звуковой слой. Уровень-наследник описывает только
## геометрию, расстановку и события.
##
## Уровни пишутся кодом осознанно: блокинг должен читаться в diff'ах, а не
## прятаться в бинарных .tscn. Сцены-обёртки (scenes/game/*.tscn) — просто
## Node3D со скриптом.

@export var level_id: StringName = &""
@export var level_name := ""
## Файл ракурсов режиссёра. Ключ к «ахуенной камере» — данные, а не код.
@export var camera_frames_path := "res://resources/camera_frames/ward_night.json"
@export var opening_frame: StringName = &""
@export var ambient_loop: StringName = &"ward_amb"
@export var mood := 0

var director: CameraDirector
var player: PlayerController
var effects: ScreenEffects
var hud: HUD
var environment_rig: EnvironmentRig
var _pause_menu: Node = null
var _ready_done := false

## Слои: эффекты кадра — 80/81, HUD выше них, пауза и шторка — ещё выше.
const HUD_LAYER := 100


func _ready() -> void:
	add_to_group(&"level")
	_build_environment()
	_build_level()
	_build_player()
	_build_effects()
	_build_director()
	_build_hud()
	_start_ambience()
	GameState.current_level = level_id
	GameState.game_paused = false
	_ready_done = true
	await get_tree().process_frame
	_on_level_ready()


## Переопределяется уровнем: геометрия, реквизит, триггеры, события.
func _build_level() -> void:
	pass


## Переопределяется уровнем: что происходит, когда каркас уже собран.
func _on_level_ready() -> void:
	pass


# --- Каркас -------------------------------------------------------------------

func _build_environment() -> void:
	environment_rig = EnvironmentRig.new()
	environment_rig.name = "Environment"
	environment_rig.mood = mood as EnvironmentRig.Mood
	add_child(environment_rig)


func _build_player() -> void:
	player = PlayerController.new()
	player.name = "Player"
	add_child(player)
	player.global_position = spawn_position()
	player.rotation.y = spawn_yaw()
	player.interactable_changed.connect(_on_interactable_changed)
	player.pause_requested.connect(_toggle_pause)
	player.noise_emitted.connect(_on_noise_emitted)


func _build_effects() -> void:
	effects = ScreenEffects.new()
	effects.name = "ScreenEffects"
	add_child(effects)


func _build_director() -> void:
	director = CameraDirector.new()
	director.name = "CameraDirector"
	add_child(director)
	director.set_anchor(player.avatar.head_anchor)
	director.frame_changed.connect(_on_frame_changed)
	var loaded := director.load_frames_from_json(camera_frames_path)
	if not loaded:
		push_warning("LevelBase: ракурсы не загружены из " + camera_frames_path)
	if loaded and opening_frame != &"":
		director.cut_to(opening_frame, 0.0, &"opening")


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUDLayer"
	layer.layer = HUD_LAYER
	add_child(layer)
	hud = HUD.new()
	hud.name = "HUD"
	layer.add_child(hud)


func _start_ambience() -> void:
	if ambient_loop != &"":
		AudioDirector.start_loop(ambient_loop, AudioDirector.BUS_BED, -16.0)
	AudioDirector.start_loop(&"drone_low", AudioDirector.BUS_BED, -30.0)


# --- Хуки уровня ---------------------------------------------------------------

func spawn_position() -> Vector3:
	return Vector3.ZERO


func spawn_yaw() -> float:
	return 0.0


func _on_interactable_changed(interactable: Interactable) -> void:
	if hud == null:
		return
	if interactable == null:
		hud.set_prompt("")
	else:
		hud.set_prompt("[E] " + interactable.prompt)


func _on_noise_emitted(amount: float, _position: Vector3) -> void:
	GameState.apply_stress(amount * 0.02, &"effort")


func _on_frame_changed(_frame: CameraFrame, _reason: StringName) -> void:
	pass


# --- Инструменты для наследников ---------------------------------------------

func say(text: String, seconds := 3.5) -> void:
	if hud != null:
		hud.say(text, seconds)


func objective(text: String) -> void:
	if hud != null:
		hud.set_objective(text)


func cut(id: StringName, hold := 0.0) -> void:
	if director != null:
		director.cut_to(id, hold)


func change_mood(value: int) -> void:
	if environment_rig != null:
		environment_rig.set_mood(value as EnvironmentRig.Mood)


## Триггер камеры: зона, которая навязывает ракурс.
func add_camera_trigger(position: Vector3, frame_id: StringName, hold := 3.0,
		size := Vector3(1.8, 2.5, 1.8), tags: Array[StringName] = []) -> CameraTrigger:
	var trigger := CameraTrigger.new()
	trigger.position = position
	trigger.frame_id = frame_id
	trigger.hold = hold
	trigger.interest_tags = tags
	# Зона задаётся уровнем: под каждый кадр своя ширина коридора срабатывания.
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	trigger.add_child(shape)
	add_child(trigger)
	trigger.triggered.connect(_on_camera_trigger)
	return trigger


func _on_camera_trigger(trigger: CameraTrigger, _body: Node3D) -> void:
	cut(trigger.frame_id, trigger.hold)


## Зона события: что-то происходит, когда герой входит.
func add_event_zone(position: Vector3, event_name: StringName,
		size := Vector3(2.0, 2.5, 2.0), once := true) -> Area3D:
	var zone := Area3D.new()
	zone.name = "Zone_" + String(event_name)
	zone.position = position
	zone.collision_layer = 0
	zone.collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	zone.add_child(shape)
	zone.set_meta(&"event", event_name)
	zone.set_meta(&"once", once)
	zone.set_meta(&"fired", false)
	add_child(zone)
	zone.body_entered.connect(_on_event_zone_entered.bind(zone))
	return zone


func _on_event_zone_entered(body: Node3D, zone: Area3D) -> void:
	if not body.is_in_group(&"player"):
		return
	if bool(zone.get_meta(&"once", true)) and bool(zone.get_meta(&"fired", false)):
		return
	zone.set_meta(&"fired", true)
	_on_event(StringName(zone.get_meta(&"event", &"")), zone)


## Переопределяется уровнем: реакция на вход героя в зону события.
func _on_event(_event_name: StringName, _zone: Area3D) -> void:
	pass


# --- Пауза --------------------------------------------------------------------

func _toggle_pause() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		# Меню само снимает паузу и освобождается.
		(_pause_menu as CanvasLayer).call(&"close")
		_pause_menu = null
		return
	var scene := load("res://scenes/ui/pause_menu.tscn")
	if scene == null:
		return
	_pause_menu = (scene as PackedScene).instantiate()
	add_child(_pause_menu)


func _unhandled_input(event: InputEvent) -> void:
	if not _ready_done:
		return
	if event.is_action_pressed(&"debug_camera"):
		_toggle_debug_view()
	elif event.is_action_pressed(&"camera_next"):
		_cycle_frame()
	elif event.is_action_pressed(&"quality_cycle"):
		Quality.set_tier(((int(Quality.tier) + 1) % 4) as Quality.Tier)


func _toggle_debug_view() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or director == null:
		return
	var debug := cam == director.camera
	if debug:
		var free := Camera3D.new()
		free.name = "DebugFreeCamera"
		add_child(free)
		free.current = true
		free.global_position = director.camera.global_position + Vector3(0, 0.4, 1.4)
		free.fov = 55.0
		say("ОТЛАДОЧНАЯ КАМЕРА · F1 — вернуться к режиссёру", 3.0)
	else:
		var free_cam := get_node_or_null("DebugFreeCamera")
		if free_cam != null:
			free_cam.queue_free()
		director.camera.current = true
		say("РЕЖИССЁР", 1.6)


func _cycle_frame() -> void:
	if director == null:
		return
	var ids := director.frame_ids()
	if ids.is_empty():
		return
	var current := director.current_frame
	var index := ids.find(current.id) if current != null else -1
	index = (index + 1) % ids.size()
	director.cut_to(ids[index], 0.0, &"debug")
	say("РАКУРС: " + String(ids[index]).to_upper(), 1.6)
