class_name Avatar
extends Node3D
## Аватар героя.
##
## Ключевое правило проекта: у героя НЕТ ТЕЛА как изображения. Есть телесная
## оболочка, которая работает вырезом в кадре (body_hole.gdshader), и есть
## ровно две вещи, которые существуют резко — РУКИ и МАСКА.
##
## Поэтому здесь три независимых материала:
##   * body_hole  — дыра вместо тела (прозрачный пасс, читает кадр),
##   * hands_reveal — руки: поры, грязь, пот, микрорельеф, тремор,
##   * mask_visor — маска: преломление уже размытого фона, конденсат, грязь.
##
## Аватар сам синхронизирует свои материалы с виталитетами из GameState, поэтому
## любой бит игры автоматически получает правильную картинку.

signal pose_changed(name: StringName)

const SURFACE_VALVE := 0.0

@export var body_enabled := true
## Смещение головы от корней аватара.
var head_anchor: Node3D
var head_node: Node3D
var left_arm: ArmRig
var right_arm: ArmRig

var body_material: ShaderMaterial
var hands_material: ShaderMaterial
var nail_material: ShaderMaterial
var mask_material: ShaderMaterial
var visor_material: ShaderMaterial

var _body_mesh: MeshInstance3D
var _flashlight: Node3D
var _current_pose := &"idle"
var _extra_blur := 0.0
var _gesture_visor_fog := 0.0


func _ready() -> void:
	_build_materials()
	_build_body()
	_build_head()
	_build_arms()
	_build_flashlight()
	set_pose(&"idle")


func _process(delta: float) -> void:
	_sync_vitals(delta)


# --- Сборка -------------------------------------------------------------------

func _build_materials() -> void:
	body_material = ShaderLibrary.material(&"body_hole", {
		"blur_radius": 26.0,
		"chromatic": 0.34,
		"absorption": 0.45,
		"edge_softness": 0.6,
	})
	hands_material = ShaderLibrary.material(&"hands_reveal", {
		"skin_tone": Color(0.86, 0.72, 0.64),
		"skin_deep": Color(0.60, 0.29, 0.25),
		"dirt_amount": 0.6,
		"wetness": 0.3,
		"pore_amount": 0.8,
	})
	nail_material = ShaderLibrary.material(&"hands_reveal", {
		"skin_tone": Color(0.90, 0.83, 0.79),
		"skin_deep": Color(0.72, 0.55, 0.52),
		"dirt_amount": 0.18,
		"wetness": 0.55,
		"pore_amount": 0.25,
		"rim_strength": 0.35,
		"detail_scale": 90.0,
	})
	mask_material = ShaderLibrary.material(&"mask_visor", {
		"refraction": 0.25,
		"thickness": 0.6,
		"condensation": 0.15,
		"outer_grime": 0.4,
		"droplets": 0.12,
		"tunnel": 0.2,
	})
	# Визор — отдельный экземпляр с сильным преломлением: сквозь него видно
	# размытое тело за спиной, и это единственное место, где герой видит себя.
	visor_material = ShaderLibrary.material(&"mask_visor", {
		"refraction": 1.35,
		"thickness": 1.35,
		"chromatic": 0.95,
		"condensation": 0.5,
		"outer_grime": 0.6,
		"droplets": 0.35,
		"scratches": 0.35,
		"tunnel": 0.3,
	}, 1)


func _build_body() -> void:
	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "HollowBody"
	_body_mesh.mesh = AvatarBuilder.build_body_hull()
	_body_mesh.material_override = body_material
	_body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Порядок отрисовки: тело рисуется после всей непрозрачной геометрии.
	_body_mesh.custom_aabb = AABB(Vector3(-0.6, -0.2, -0.6), Vector3(1.2, 2.2, 1.2))
	add_child(_body_mesh)
	_body_mesh.visible = body_enabled


func _build_head() -> void:
	head_node = Node3D.new()
	head_node.name = "Head"
	head_node.position = Vector3(0, AvatarBuilder.HEAD_HEIGHT, 0.0)
	add_child(head_node)

	head_anchor = Node3D.new()
	head_anchor.name = "HeadAnchor"
	head_anchor.position = Vector3(0, AvatarBuilder.HEAD_HEIGHT + 0.02, 0.0)
	add_child(head_anchor)

	var mask := MeshInstance3D.new()
	mask.name = "MaskShell"
	mask.mesh = AvatarBuilder.build_mask()
	mask.material_override = mask_material
	head_node.add_child(mask)

	var visor := MeshInstance3D.new()
	visor.name = "Visor"
	visor.mesh = AvatarBuilder.build_visor()
	visor.material_override = visor_material
	head_node.add_child(visor)

	var valve := MeshInstance3D.new()
	valve.name = "Valve"
	valve.mesh = AvatarBuilder.build_valve()
	valve.material_override = mask_material
	head_node.add_child(valve)

	var straps := MeshInstance3D.new()
	straps.name = "Straps"
	straps.mesh = AvatarBuilder.build_straps()
	straps.material_override = hands_material
	head_node.add_child(straps)

	var filter := MeshInstance3D.new()
	filter.name = "Filter"
	filter.mesh = AvatarBuilder.build_filter()
	filter.material_override = mask_material
	head_node.add_child(filter)


func _build_arms() -> void:
	left_arm = ArmRig.new()
	left_arm.name = "LeftArm"
	left_arm.position = Vector3(-AvatarBuilder.SHOULDER_WIDTH, AvatarBuilder.SHOULDER_HEIGHT, 0.0)
	add_child(left_arm)
	left_arm.build(-1.0, hands_material, nail_material)

	right_arm = ArmRig.new()
	right_arm.name = "RightArm"
	right_arm.position = Vector3(AvatarBuilder.SHOULDER_WIDTH, AvatarBuilder.SHOULDER_HEIGHT, 0.0)
	add_child(right_arm)
	right_arm.build(1.0, hands_material, nail_material)


func _build_flashlight() -> void:
	_flashlight = Node3D.new()
	_flashlight.name = "Flashlight"
	var mesh := MeshInstance3D.new()
	mesh.mesh = AvatarBuilder.build_flashlight()
	# Фонарь — металл и стекло: тот же шейдер рук с другими параметрами.
	var mat := ShaderLibrary.material(&"hands_reveal", {
		"skin_tone": Color(0.55, 0.57, 0.60),
		"skin_deep": Color(0.28, 0.29, 0.31),
		"dirt_amount": 0.45,
		"wetness": 0.15,
		"pore_amount": 0.15,
		"detail_scale": 120.0,
		"rim_strength": 1.5,
		"rim_color": Color(0.75, 0.85, 1.0),
	})
	mesh.material_override = mat
	_flashlight.add_child(mesh)

	var light := SpotLight3D.new()
	light.name = "Beam"
	light.light_color = Color(0.85, 0.90, 1.0)
	light.light_energy = 3.2
	light.spot_range = 18.0
	light.spot_angle = 33.0
	light.spot_angle_attenuation = 1.1
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-90, 0, 0)
	light.position = Vector3(0, 0, -0.10)
	_flashlight.add_child(light)

	# Крепим к кисти правой руки.
	var wrist: Node3D = right_arm.get_node("Shoulder/Elbow/Wrist")
	wrist.add_child(_flashlight)
	_flashlight.position = Vector3(0, -0.02, -0.05)
	_flashlight.rotation_degrees = Vector3(-8, 0, 0)


# --- Управление состоянием ----------------------------------------------------

func set_pose(pose_name: StringName, both_arms := true) -> void:
	if _current_pose == pose_name and both_arms:
		return
	_current_pose = pose_name
	if both_arms:
		left_arm.set_pose(pose_name)
		right_arm.set_pose(pose_name)
	pose_changed.emit(pose_name)


## Правая рука держит фонарь, левая живёт своей жизнью: так руки не двигаются
## «одним куском», и кадр сразу становится живым.
func set_pose_asymmetric(left_pose: StringName, right_pose: StringName) -> void:
	_current_pose = left_pose
	left_arm.set_pose(left_pose)
	right_arm.set_pose(right_pose)


func set_finger_curl(value: float) -> void:
	left_arm.set_curl(value)
	right_arm.set_curl(value)


## Жест: последовательность поз. Используется сценарными моментами.
func gesture(steps: Array) -> void:
	right_arm.play_sequence(steps)


func is_gesturing() -> bool:
	return right_arm.is_gesturing() or left_arm.is_gesturing()


## Резкий доп-блюр: используется в моменты обморока и «выпадения из реальности».
func set_extra_blur(value: float) -> void:
	_extra_blur = clampf(value, 0.0, 60.0)


func set_flashlight(on: bool) -> void:
	if _flashlight == null:
		return
	var beam := _flashlight.get_node_or_null("Beam") as SpotLight3D
	if beam != null:
		beam.visible = on


func mask_world_position() -> Vector3:
	return head_node.global_position + head_node.global_transform.basis * Vector3(0, 0, 0.05)


# --- Синхронизация с виталитетами ---------------------------------------------

func _sync_vitals(delta: float) -> void:
	var dread := GameState.dread
	var pressure := GameState.pressure_level()
	var pupil := GameState.pupil_size()
	var beat := GameState.heartbeat_envelope()

	# Дыра: при падении давления и росте ужаса диск рассеяния расширяется —
	# герой буквально расплывается тем сильнее, чем хуже ему становится.
	var blur := lerpf(16.0, 48.0, clampf(dread * 0.75 + pressure * 0.55, 0.0, 1.0))
	blur += _extra_blur
	ShaderLibrary.set_uniform(body_material, &"blur_radius", blur)
	ShaderLibrary.set_uniform(body_material, &"pressure", pressure)
	ShaderLibrary.set_uniform(body_material, &"pulse", beat)
	ShaderLibrary.set_uniform(body_material, &"living", 0.08 if Quality.comfort_value("reduce_shake") else 0.3)
	# Покрытие: при потере сознания тело почти исчезает из кадра.
	ShaderLibrary.set_uniform(body_material, &"coverage",
		clampf(0.35 + GameState.consciousness * 0.65, 0.0, 1.0))
	ShaderLibrary.set_uniform(body_material, &"absorption", lerpf(0.3, 0.6, dread))

	# Руки: холод, пот, тремор, грязь.
	ShaderLibrary.set_uniform(hands_material, &"cold", GameState.cold())
	ShaderLibrary.set_uniform(hands_material, &"tremor", GameState.tremor())
	ShaderLibrary.set_uniform(hands_material, &"wetness", clampf(0.2 + dread * 0.5, 0.0, 1.0))
	ShaderLibrary.set_uniform(hands_material, &"dirt_amount", clampf(0.35 + dread * 0.5, 0.0, 1.0))

	# Маска: конденсат растёт на выдохе, зрачок влияет на прозрачность стекла.
	var breath := maxf(0.0, GameState.breath_signed())
	_gesture_visor_fog = lerpf(_gesture_visor_fog, breath, minf(delta * 3.0, 1.0))
	ShaderLibrary.set_uniform(visor_material, &"breath_fog", _gesture_visor_fog * 0.8)
	ShaderLibrary.set_uniform(visor_material, &"condensation", clampf(0.35 + _gesture_visor_fog * 0.5, 0.0, 1.0))
	ShaderLibrary.set_uniform(visor_material, &"outer_grime", clampf(0.45 + dread * 0.4, 0.0, 1.0))
	ShaderLibrary.set_uniform(mask_material, &"condensation", clampf(0.1 + _gesture_visor_fog * 0.3, 0.0, 1.0))
	ShaderLibrary.set_uniform(mask_material, &"tunnel", lerpf(0.15, 0.45, pupil))
