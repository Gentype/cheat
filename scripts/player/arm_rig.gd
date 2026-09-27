class_name ArmRig
extends Node3D
## Риг руки: плечо → локоть → кисть → пять пальцев по три фаланги.
##
## Зачем скелет, а не одна меш-деталь: рука — единственная живая плоть в кадре,
## и именно её движение продаёт присутствие человека. Позы заданы цифрами,
## переходы интерполируются, поверх всегда идёт тремор от виталитетов.
##
## Соглашение по осям: конечность растёт вдоль -Y, пальцы — вдоль -Z,
## тыл ладони смотрит в +Y. Сгиб — положительный поворот вокруг X.

## Целевые позы. Числа подобраны так, чтобы силуэт читался даже в темноте.
const POSES := {
	&"idle": {
		"shoulder_x": -0.10, "shoulder_y": 0.06, "shoulder_z": 0.04,
		"elbow": 0.22, "wrist_x": 0.0, "wrist_y": 0.0, "curl": 0.30, "spread": 0.25,
	},
	&"raised": {
		"shoulder_x": -1.05, "shoulder_y": -0.10, "shoulder_z": -0.05,
		"elbow": 1.30, "wrist_x": -0.28, "wrist_y": 0.05, "curl": 0.82, "spread": 0.35,
	},
	&"brace": {
		"shoulder_x": -1.22, "shoulder_y": -0.22, "shoulder_z": -0.10,
		"elbow": 1.05, "wrist_x": -0.35, "wrist_y": 0.0, "curl": 0.45, "spread": 0.55,
	},
	&"grip": {
		"shoulder_x": -0.66, "shoulder_y": -0.05, "shoulder_z": 0.0,
		"elbow": 1.52, "wrist_x": -0.10, "wrist_y": 0.0, "curl": 0.98, "spread": 0.05,
	},
	&"check_pulse": {
		"shoulder_x": -0.92, "shoulder_y": -0.34, "shoulder_z": -0.18,
		"elbow": 1.72, "wrist_x": -0.42, "wrist_y": -0.25, "curl": 0.72, "spread": -0.35,
	},
	&"cover": {
		"shoulder_x": -1.38, "shoulder_y": -0.30, "shoulder_z": -0.22,
		"elbow": 2.05, "wrist_x": 0.30, "wrist_y": 0.20, "curl": 0.62, "spread": 0.15,
	},
	&"clutch": {
		"shoulder_x": -1.02, "shoulder_y": -0.18, "shoulder_z": -0.10,
		"elbow": 1.95, "wrist_x": 0.10, "wrist_y": 0.0, "curl": 1.0, "spread": 0.0,
	},
	&"limp": {
		"shoulder_x": 0.06, "shoulder_y": 0.14, "shoulder_z": 0.02,
		"elbow": 0.06, "wrist_x": 0.10, "wrist_y": 0.0, "curl": 0.08, "spread": 0.20,
	},
}

const FINGER_NAMES := ["thumb", "index", "middle", "ring", "little"]
## Длины фаланг: [большой, указательный, средний, безымянный, мизинец].
const FINGER_LENGTHS := [
	[0.036, 0.030, 0.024],
	[0.042, 0.028, 0.020],
	[0.046, 0.031, 0.021],
	[0.042, 0.029, 0.020],
	[0.034, 0.023, 0.018],
]
const FINGER_RADIUS := [0.0115, 0.0105, 0.0103, 0.0096, 0.0084]
## Положение основания пальца в системе кисти.
const FINGER_ROOT := [
	Vector3(-0.036, -0.004, -0.030),
	Vector3(-0.028, -0.002, -0.088),
	Vector3(-0.007, 0.0, -0.094),
	Vector3(0.014, -0.001, -0.090),
	Vector3(0.033, -0.005, -0.079),
]
## Ограничение сгиба по фалангам, радианы. Большой палец сгибается иначе.
const FINGER_LIMITS := [
	[0.7, 0.9, 0.7],
	[1.55, 1.7, 1.1],
	[1.55, 1.75, 1.15],
	[1.5, 1.7, 1.1],
	[1.45, 1.65, 1.05],
]

## -1 — левая, +1 — правая.
var side := 1.0
var upper_length := 0.29
var fore_length := 0.26

var _shoulder := Node3D.new()
var _elbow := Node3D.new()
var _wrist := Node3D.new()
var _finger_joints: Array = []
var _finger_roots: Array = []
var _material: ShaderMaterial
var _nail_material: ShaderMaterial
var _target := {}
var _current := {}
var _curl := 0.3
var _curl_target := 0.3
var _spread := 0.25
var _spread_target := 0.25
var _sequence: Array = []
var _sequence_timer := 0.0
var _time := 0.0
var _sway_amount := 1.0
var _tremor_scale := 1.0


func _ready() -> void:
	_time = randf() * 10.0


## Сборка руки. Материалы передаются снаружи, чтобы все части кисти и
## предплечья делили один шейдер и синхронно меняли виталитеты.
func build(arm_side: float, skin_material: ShaderMaterial, nail_material: ShaderMaterial) -> void:
	side = signf(arm_side)
	if is_zero_approx(side):
		side = 1.0
	_material = skin_material
	_nail_material = nail_material

	_shoulder.name = "Shoulder"
	add_child(_shoulder)

	var arm_mesh := MeshInstance3D.new()
	arm_mesh.name = "ArmMesh"
	arm_mesh.mesh = AvatarBuilder.build_upper_arm(side, upper_length, fore_length)
	arm_mesh.material_override = _material
	arm_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_shoulder.add_child(arm_mesh)

	_elbow.name = "Elbow"
	_elbow.position = Vector3(0, -upper_length, 0)
	_shoulder.add_child(_elbow)

	_wrist.name = "Wrist"
	_wrist.position = Vector3(0, -fore_length, 0)
	_elbow.add_child(_wrist)

	var palm := MeshInstance3D.new()
	palm.name = "Palm"
	palm.mesh = AvatarBuilder.build_palm(side)
	palm.material_override = _material
	_wrist.add_child(palm)

	for i in range(0, FINGER_NAMES.size()):
		_build_finger(i)

	_target = POSES[&"idle"]
	_current = _target.duplicate()
	_apply_current(0.0)


func _build_finger(index: int) -> void:
	var lengths: Array = FINGER_LENGTHS[index]
	var radius: float = FINGER_RADIUS[index]
	var root := Node3D.new()
	root.name = "Finger_" + FINGER_NAMES[index]
	var base: Vector3 = FINGER_ROOT[index]
	root.position = Vector3(base.x * side, base.y, base.z)
	_wrist.add_child(root)
	_finger_roots.append(root)

	var joints: Array = []
	var parent := root
	for i in range(0, lengths.size()):
		var joint := Node3D.new()
		joint.name = "Phalanx%d" % (i + 1)
		var length: float = lengths[i]
		var mesh := MeshInstance3D.new()
		mesh.mesh = AvatarBuilder.build_phalanx(length, radius * (1.0 - float(i) * 0.08), i == 0)
		mesh.material_override = _material
		joint.add_child(mesh)
		if i == lengths.size() - 1:
			var nail := MeshInstance3D.new()
			nail.mesh = AvatarBuilder.build_nail(length * 0.55, radius * 0.75, length * 0.62)
			nail.material_override = _nail_material
			nail.position = Vector3(0, -radius * 0.55, 0)
			joint.add_child(nail)
		parent.add_child(joint)
		joints.append(joint)
		var next := Node3D.new()
		next.name = "Next%d" % (i + 1)
		next.position = Vector3(0, 0, -length)
		joint.add_child(next)
		parent = next
	_finger_joints.append(joints)


## Плавно перейти в позу.
func set_pose(pose_name: StringName, blend := 1.0) -> void:
	if not POSES.has(pose_name):
		push_warning("ArmRig: нет позы " + String(pose_name))
		return
	var pose: Dictionary = POSES[pose_name]
	_target = pose.duplicate()
	if blend < 1.0:
		for key in _current.keys():
			_target[key] = lerpf(float(_current[key]), float(_target.get(key, _current[key])), blend)


func set_curl(value: float) -> void:
	_curl_target = clampf(value, 0.0, 1.0)


func set_spread(value: float) -> void:
	_spread_target = clampf(value, -1.0, 1.0)


## Последовательность поз: ["grip", 0.4, "raised", 0.8] — жест на N секунд.
func play_sequence(steps: Array) -> void:
	_sequence.clear()
	var i := 0
	while i + 1 < steps.size():
		_sequence.append({"pose": steps[i], "time": float(steps[i + 1])})
		i += 2
	_sequence_timer = 0.0
	if not _sequence.is_empty():
		set_pose(_sequence[0]["pose"])


func is_gesturing() -> bool:
	return not _sequence.is_empty()


func _process(delta: float) -> void:
	_time += delta
	_advance_sequence(delta)

	# Тремор: чем выше пульс и ниже сатурация, тем сильнее дрожат руки.
	var tremor := GameState.tremor() * _tremor_scale
	var rate := 8.0 + tremor * 22.0
	var shake := Vector3(
		sin(_time * rate * 0.9) * 0.5 + sin(_time * rate * 2.3) * 0.25,
		cos(_time * rate * 1.1) * 0.5,
		sin(_time * rate * 1.7) * 0.35
	) * tremor * 0.006

	# Дыхание: кисть приподнимается вместе с грудной клеткой.
	var breath := GameState.breath_signed() * 0.012 * _sway_amount
	_current["breath"] = breath

	var speed := 6.5 + tremor * 5.0
	for key in _target.keys():
		_current[key] = lerpf(float(_current.get(key, _target[key])), float(_target[key]), minf(delta * speed, 1.0))
	_curl = lerpf(_curl, _curl_target, minf(delta * 6.0, 1.0))
	_spread = lerpf(_spread, _spread_target, minf(delta * 5.0, 1.0))
	_apply_current(delta, shake)


func _advance_sequence(delta: float) -> void:
	if _sequence.is_empty():
		return
	_sequence_timer += delta
	var entry: Dictionary = _sequence[0]
	if _sequence_timer >= float(entry["time"]):
		_sequence_timer = 0.0
		_sequence.pop_front()
		if not _sequence.is_empty():
			set_pose(_sequence[0]["pose"])


func _apply_current(_delta: float, shake := Vector3.ZERO) -> void:
	var shoulder_x := float(_current.get("shoulder_x", 0.0)) + shake.y
	var shoulder_y := float(_current.get("shoulder_y", 0.0)) * side + shake.x * 0.5
	var shoulder_z := float(_current.get("shoulder_z", 0.0)) * side
	var elbow := float(_current.get("elbow", 0.0))
	var wrist_x := float(_current.get("wrist_x", 0.0))
	var wrist_y := float(_current.get("wrist_y", 0.0)) * side
	var breath := float(_current.get("breath", 0.0))

	_shoulder.rotation = Vector3(shoulder_x, shoulder_y, shoulder_z)
	_shoulder.position = Vector3(0, breath * 0.5, 0)
	_elbow.rotation = Vector3(elbow, 0.0, 0.0)
	_wrist.rotation = Vector3(wrist_x + shake.z, wrist_y, shoulder_z * 0.3)

	# Пронация: ладонь поворачивается внутрь тем сильнее, чем сложнее поза.
	var spread := _spread
	for i in range(0, _finger_joints.size()):
		var joints: Array = _finger_joints[i]
		var limits: Array = FINGER_LIMITS[i]
		var root: Node3D = _finger_roots[i]
		# Разведение пальцев — только у указательного-мизинца.
		if i > 0:
			root.rotation = Vector3(0.0, (spread * (float(i) - 2.0) * 0.16) * side, 0.0)
		else:
			root.rotation = Vector3(0.0, -spread * 0.35 * side, 0.0)
		for j in range(0, joints.size()):
			var joint: Node3D = joints[j]
			# Сгиб идёт отрицательным поворотом: палец уходит к ладони.
			joint.rotation = Vector3(-_curl * float(limits[j]), 0.0, 0.0)
