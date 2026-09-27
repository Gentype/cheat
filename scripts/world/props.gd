class_name Props
extends RefCounted
## Процедурный реквизит блока. Каждая функция собирает готовую ноду с
## геометрией и коллизией. Ни одной внешней модели: каталки, койки, штативы,
## мониторы и двери строятся кодом из примитивов MeshBuilder.
##
## Материалы берутся из MaterialFactory, поэтому вся мебель блока делит
## несколько шейдерных экземпляров, а не плодит свои.

const WALL_HEIGHT := 2.75
const WALL_THICKNESS := 0.14


# --- Помощники -----------------------------------------------------------------

static func _add_mesh(parent: Node3D, mesh: ArrayMesh, material: Material, mesh_name := "Mesh") -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	return instance


static func _add_box_collision(body: StaticBody3D, size: Vector3, offset := Vector3.ZERO) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = offset
	body.add_child(shape)


static func _static(name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = 1
	body.collision_mask = 0
	return body


# --- Архитектура ---------------------------------------------------------------

## Пол. surface — метаданные шага (tile / metal / cloth), по ним звучит шаг.
static func create_floor(size: Vector2, position := Vector3.ZERO, surface := "tile",
		material: Material = null) -> StaticBody3D:
	var body := _static("Floor")
	body.position = position
	var builder := MeshBuilder.new()
	# Нормаль вверх: пол виден сверху — порядок точек даёт +Y.
	builder.rect(Vector3(-size.x * 0.5, 0.0, size.y * 0.5),
		Vector3(size.x, 0.0, 0.0), Vector3(0.0, 0.0, -size.y))
	_add_mesh(body, builder.commit("floor"), material if material != null else MaterialFactory.tile_floor())
	_add_box_collision(body, Vector3(size.x, 0.2, size.y), Vector3(0, -0.1, 0))
	body.set_meta(&"surface", surface)
	return body


static func create_ceiling(size: Vector2, position := Vector3.ZERO, height := WALL_HEIGHT,
		material: Material = null) -> StaticBody3D:
	var body := _static("Ceiling")
	body.position = position + Vector3(0, height, 0)
	var builder := MeshBuilder.new()
	builder.rect(Vector3(-size.x * 0.5, 0.0, -size.y * 0.5),
		Vector3(size.x, 0.0, 0.0), Vector3(0.0, 0.0, size.y))
	_add_mesh(body, builder.commit("ceiling"), material if material != null else MaterialFactory.concrete())
	_add_box_collision(body, Vector3(size.x, 0.2, size.y), Vector3(0, 0.1, 0))
	return body


## Стена от точки A до точки B (по XZ), с плинтусом и кафельной полосой снизу.
static func create_wall(from: Vector3, to: Vector3, height := WALL_HEIGHT,
		thickness := WALL_THICKNESS, tiled_up_to := 2.05) -> StaticBody3D:
	var body := _static("Wall")
	var delta := to - from
	var length := delta.length()
	if length < 0.01:
		return body
	var direction := Vector3(delta.x, 0.0, delta.z).normalized()
	var right := Vector3(direction.z, 0.0, -direction.x) * (thickness * 0.5)
	var builder := MeshBuilder.new()
	builder.rect(from - right, direction * length, Vector3(0.0, tiled_up_to, 0.0))
	_add_mesh(body, builder.commit("wall_tile"), MaterialFactory.tile_wall(), "WallTile")

	var upper := MeshBuilder.new()
	upper.rect(from - right + Vector3(0, tiled_up_to, 0), direction * length,
		Vector3(0.0, height - tiled_up_to, 0.0))
	_add_mesh(body, upper.commit("wall_paint"), MaterialFactory.painted_wall(), "WallPaint")

	# Обратная сторона стены (в блоках это разные помещения).
	var back := MeshBuilder.new()
	back.rect(to + right, -direction * length, Vector3(0.0, height, 0.0))
	_add_mesh(body, back.commit("wall_back"), MaterialFactory.painted_wall(), "WallBack")

	# Торцы.
	var cap := MeshBuilder.new()
	cap.rect(from + right, right * 2.0, Vector3(0.0, height, 0.0))
	_add_mesh(body, cap.commit("wall_cap_a"), MaterialFactory.painted_wall(), "WallCapA")

	# Нода остаётся в начале координат: геометрия уже в мировых координатах,
	# а коллизия получает точный трансформ вдоль стены.
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(thickness, height, length)
	shape.shape = box
	shape.position = (from + to) * 0.5 + Vector3(0, height * 0.5, 0)
	shape.rotation.y = atan2(direction.x, direction.z)
	body.add_child(shape)
	return body


## Перегородка-дверной проём: две «щеки» и перекладина.
static func create_doorway(center: Vector3, direction: Vector3, width := 1.1,
		height := 2.1, wall_height := WALL_HEIGHT) -> Node3D:
	var root := Node3D.new()
	root.name = "Doorway"
	var side := Vector3(direction.z, 0.0, -direction.x).normalized()
	var half := width * 0.5
	var jamb := 0.09
	root.add_child(create_wall(center - side * half - direction * jamb,
		center - side * half + direction * jamb, height))
	root.add_child(create_wall(center + side * half - direction * jamb,
		center + side * half + direction * jamb, height))
	# Перекладина над проёмом.
	var lintel := MeshBuilder.new()
	var from := center + side * half
	var to := center - side * half
	lintel.rect(from + Vector3(0, height, 0), (to - from), Vector3(0, wall_height - height, 0))
	_add_mesh(root, lintel.commit("lintel"), MaterialFactory.painted_wall(), "Lintel")
	return root


# --- Двери, окна, занавеси ------------------------------------------------------

## Дверь: полотно, ручка, смотровое окно, доводчик. Угол открытия задаётся
## в радианах — уровень ставит их по сценарию.
static func create_door(position: Vector3, yaw: float, open_angle := 0.0,
		with_window := true) -> Node3D:
	var root := Node3D.new()
	root.name = "Door"
	root.position = position
	root.rotation.y = yaw

	var width := 0.95
	var height := 2.1
	var thickness := 0.05

	var leaf := Node3D.new()
	leaf.name = "Leaf"
	leaf.rotation.y = open_angle
	root.add_child(leaf)

	var panel := MeshBuilder.new()
	panel.box(Vector3(width * 0.5, height * 0.5, 0.0), Vector3(width, height, thickness),
		Vector2(2.0, 2.0))
	_add_mesh(leaf, panel.commit("door_leaf"), MaterialFactory.painted_metal(), "LeafMesh")

	# Ручка-скоба.
	var handle := MeshBuilder.new()
	handle.capsule(Vector3(0.06, 1.02, 0.05), Vector3(0.06, 1.02, 0.20), 0.014, 10, 3)
	handle.capsule(Vector3(0.06, 1.02, 0.20), Vector3(0.13, 1.02, 0.20), 0.014, 10, 3)
	_add_mesh(leaf, handle.commit("door_handle"), MaterialFactory.metal(), "Handle")

	if with_window:
		var frame := MeshBuilder.new()
		frame.box(Vector3(width * 0.5, 1.62, 0.0), Vector3(0.48, 0.42, 0.062))
		_add_mesh(leaf, frame.commit("door_window_frame"), MaterialFactory.painted_metal(), "WindowFrame")

		var glass := MeshBuilder.new()
		glass.box(Vector3(width * 0.5, 1.62, 0.0), Vector3(0.40, 0.34, 0.02))
		_add_mesh(leaf, glass.commit("door_window"), MaterialFactory.glass(), "WindowGlass")

	# Доводчик — тяжёлый цилиндр сверху, объясняет, почему дверь закрывается сама.
	var closer := MeshBuilder.new()
	closer.cylinder(Vector3(0.12, 2.02, 0.06), Vector3(0.72, 2.02, 0.06), 0.026, 0.026, 12)
	_add_mesh(leaf, closer.commit("door_closer"), MaterialFactory.metal(), "Closer")

	var body := _static("DoorBody")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, 0.08)
	shape.shape = box
	shape.position = Vector3(width * 0.5, height * 0.5, 0.0)
	body.add_child(shape)
	leaf.add_child(body)
	return root


## Занавесь вокруг койки: рельс по потолку и полотно ткани.
static func create_curtain(center: Vector3, yaw: float, width := 2.2) -> Node3D:
	var root := Node3D.new()
	root.name = "Curtain"
	root.position = center
	root.rotation.y = yaw

	var rail := MeshBuilder.new()
	rail.cylinder(Vector3(-width * 0.5, 2.35, 0.0), Vector3(width * 0.5, 2.35, 0.0), 0.018, 0.018, 12)
	_add_mesh(root, rail.commit("curtain_rail"), MaterialFactory.metal(), "Rail")

	# Полотно: слегка волнистая поверхность из полос ткани.
	var cloth := MeshBuilder.new()
	var folds := 12
	for i in range(0, folds):
		var u0 := -0.5 + float(i) / float(folds)
		var u1 := -0.5 + float(i + 1) / float(folds)
		var wave0 := sin(float(i) * 1.7) * 0.06
		var wave1 := sin(float(i + 1) * 1.7) * 0.06
		var p0 := Vector3(u0 * width, 2.34, wave0)
		var p1 := Vector3(u1 * width, 2.34, wave1)
		var p2 := Vector3(u1 * width, 0.25, wave1 + 0.02)
		var p3 := Vector3(u0 * width, 0.25, wave0 + 0.02)
		var normal := (p1 - p0).cross(p3 - p0).normalized()
		cloth.quad(p0, p1, p2, p3, Vector2(1.0, 2.4), normal)
	_add_mesh(root, cloth.commit("curtain_cloth"), MaterialFactory.curtain(), "Cloth")
	return root


# --- Койки и каталки -----------------------------------------------------------

## Функциональная койка: рама, матрас, боковые поручни, колёса, спинка.
static func create_bed(position: Vector3, yaw := 0.0, occupied := false) -> Node3D:
	var root := Node3D.new()
	root.name = "Bed"
	root.position = position
	root.rotation.y = yaw

	var frame := MeshBuilder.new()
	# Рама-основание.
	frame.cylinder(Vector3(-0.45, 0.42, -0.95), Vector3(0.45, 0.42, -0.95), 0.03, 0.03, 12)
	frame.cylinder(Vector3(-0.45, 0.42, 0.95), Vector3(0.45, 0.42, 0.95), 0.03, 0.03, 12)
	frame.cylinder(Vector3(-0.45, 0.42, -0.95), Vector3(-0.45, 0.42, 0.95), 0.03, 0.03, 12)
	frame.cylinder(Vector3(0.45, 0.42, -0.95), Vector3(0.45, 0.42, 0.95), 0.03, 0.03, 12)
	# Ножки и колёса.
	for sx in [-0.42, 0.42]:
		for sz in [-0.85, 0.85]:
			frame.capsule(Vector3(sx, 0.40, sz), Vector3(sx, 0.12, sz), 0.022, 8, 2)
			frame.torus(Vector3(sx, 0.06, sz), Vector3(0, 0, 1), 0.045, 0.014, 12, 8)
	# Спинка поднимается — койка в отделении всегда «полусидя».
	var headboard := MeshBuilder.new()
	headboard.box(Vector3(0, 1.02, -0.98), Vector3(0.92, 0.5, 0.05), Vector2(2.0, 1.0))
	_add_mesh(root, frame.commit("bed_frame"), MaterialFactory.metal(), "Frame")
	_add_mesh(root, headboard.commit("bed_head"), MaterialFactory.painted_metal(), "Headboard")

	# Матрас и простыня: два слоя, простыня чуть провисает по краям.
	var mattress := MeshBuilder.new()
	mattress.box(Vector3(0, 0.55, 0), Vector3(0.86, 0.16, 1.85), Vector2(3.0, 3.0))
	_add_mesh(root, mattress.commit("bed_mattress"), MaterialFactory.fabric(Color(0.62, 0.66, 0.68)), "Mattress")

	var sheet := MeshBuilder.new()
	sheet.box(Vector3(0, 0.645, 0.02), Vector3(0.88, 0.04, 1.9), Vector2(4.0, 4.0))
	_add_mesh(root, sheet.commit("bed_sheet"), MaterialFactory.fabric(Color(0.84, 0.85, 0.82)), "Sheet")

	# Поручни: подняты со стороны, где нет стены.
	var rail := MeshBuilder.new()
	rail.cylinder(Vector3(0.46, 0.86, -0.5), Vector3(0.46, 0.86, 0.6), 0.018, 0.018, 10)
	rail.cylinder(Vector3(0.46, 0.62, -0.5), Vector3(0.46, 0.62, 0.6), 0.016, 0.016, 10)
	for sz in [-0.5, 0.05, 0.6]:
		rail.capsule(Vector3(0.46, 0.62, sz), Vector3(0.46, 0.86, sz), 0.014, 8, 2)
	_add_mesh(root, rail.commit("bed_rail"), MaterialFactory.metal(), "Rail")

	if occupied:
		# Под простынёй кто-то есть: объём и складки, но не человек.
		var shape := MeshBuilder.new()
		shape.ellipsoid(Vector3(0, 0.72, -0.35), Vector3(0.34, 0.14, 0.62), 12, 18)
		shape.ellipsoid(Vector3(0, 0.82, -0.72), Vector3(0.19, 0.15, 0.2), 10, 16)
		shape.capsule(Vector3(0, 0.74, 0.1), Vector3(0, 0.72, 0.72), 0.16, 12, 4)
		_add_mesh(root, shape.commit("bed_occupant"), MaterialFactory.fabric(Color(0.80, 0.81, 0.79)), "Occupant")

	var body := _static("BedBody")
	_add_box_collision(body, Vector3(0.95, 0.75, 2.0), Vector3(0, 0.42, 0))
	root.add_child(body)
	root.set_meta(&"blocking", true)
	return root


## Каталка — рабочая лошадь блока. Металл, матрас, колёса, поручень.
static func create_gurney(position: Vector3, yaw := 0.0, with_sheet := true) -> Node3D:
	var root := Node3D.new()
	root.name = "Gurney"
	root.position = position
	root.rotation.y = yaw

	var frame := MeshBuilder.new()
	frame.box(Vector3(0, 0.72, 0), Vector3(0.72, 0.05, 1.92), Vector2(2.0, 4.0))
	for sx in [-0.31, 0.31]:
		for sz in [-0.82, 0.82]:
			frame.capsule(Vector3(sx, 0.70, sz), Vector3(sx, 0.16, sz), 0.02, 8, 2)
			frame.torus(Vector3(sx, 0.08, sz), Vector3(0, 0, 1), 0.05, 0.016, 12, 8)
	# Поручень-толкатель.
	frame.cylinder(Vector3(-0.34, 0.96, -0.94), Vector3(0.34, 0.96, -0.94), 0.018, 0.018, 12)
	frame.capsule(Vector3(-0.34, 0.72, -0.94), Vector3(-0.34, 0.96, -0.94), 0.016, 8, 2)
	frame.capsule(Vector3(0.34, 0.72, -0.94), Vector3(0.34, 0.96, -0.94), 0.016, 8, 2)
	# Подставка для тазика и крючки для капельницы.
	frame.torus(Vector3(0, 0.45, 0.55), Vector3(0, 1, 0), 0.13, 0.008, 14, 8)
	frame.capsule(Vector3(0.30, 0.75, -0.9), Vector3(0.30, 1.55, -0.9), 0.014, 8, 2)
	frame.capsule(Vector3(0.30, 1.55, -0.9), Vector3(0.30, 1.62, -0.85), 0.012, 6, 2)
	_add_mesh(root, frame.commit("gurney_frame"), MaterialFactory.metal(), "Frame")

	var pad := MeshBuilder.new()
	pad.box(Vector3(0, 0.78, 0), Vector3(0.68, 0.1, 1.88), Vector2(3.0, 6.0))
	_add_mesh(root, pad.commit("gurney_pad"), MaterialFactory.plastic(), "Pad")

	if with_sheet:
		var sheet := MeshBuilder.new()
		sheet.box(Vector3(0, 0.845, 0.05), Vector3(0.70, 0.035, 1.7), Vector2(3.0, 6.0))
		_add_mesh(root, sheet.commit("gurney_sheet"), MaterialFactory.fabric(Color(0.82, 0.83, 0.80)), "Sheet")

	var body := _static("GurneyBody")
	_add_box_collision(body, Vector3(0.78, 0.85, 2.0), Vector3(0, 0.42, 0))
	root.add_child(body)
	return root


## Штатив капельницы с пакетом и трубкой, уходящей к койке.
static func create_iv_stand(position: Vector3, tube_to := Vector3.ZERO) -> Node3D:
	var root := Node3D.new()
	root.name = "IVStand"
	root.position = position

	var builder := MeshBuilder.new()
	builder.cylinder(Vector3(0, 0.0, 0), Vector3(0, 1.78, 0), 0.016, 0.014, 12, true)
	# Пять лучей основания.
	for i in range(0, 5):
		var angle := float(i) / 5.0 * TAU
		builder.capsule(Vector3(0, 0.04, 0),
			Vector3(cos(angle) * 0.24, 0.02, sin(angle) * 0.24), 0.01, 8, 2)
		builder.torus(Vector3(cos(angle) * 0.24, 0.02, sin(angle) * 0.24), Vector3(0, 0, 1), 0.022, 0.01, 10, 8)
	# Крюк.
	builder.torus(Vector3(0, 1.79, 0.03), Vector3(0, 0.4, 1), 0.026, 0.005, 12, 8)
	_add_mesh(root, builder.commit("iv_stand"), MaterialFactory.metal(), "Stand")

	# Пакет с раствором и трубка.
	var bag := MeshBuilder.new()
	bag.box(Vector3(0, 1.58, 0.02), Vector3(0.12, 0.32, 0.05), Vector2(1.0, 2.0))
	_add_mesh(root, bag.commit("iv_bag"), MaterialFactory.plastic(), "Bag")

	if tube_to != Vector3.ZERO:
		var tube := MeshBuilder.new()
		var points := PackedVector3Array([
			Vector3(0, 1.42, 0.02),
			Vector3(0, 1.20, 0.04),
			tube_to + Vector3(0, 0.9, 0),
			tube_to,
		])
		tube.tube_along(points, 0.006, 6)
		_add_mesh(root, tube.commit("iv_tube"), MaterialFactory.plastic(), "Tube")

	return root


# --- Приборы -------------------------------------------------------------------

## Монитор на стойке: корпус, экран с кардиограммой, панель кнопок, кабель.
static func create_monitor(position: Vector3, yaw := 0.0, bpm := 68.0,
		flatline := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Monitor"
	root.position = position
	root.rotation.y = yaw

	var cart := MeshBuilder.new()
	cart.box(Vector3(0, 0.02, 0), Vector3(0.5, 0.04, 0.42), Vector2(2.0, 2.0))
	for sx in [-0.2, 0.2]:
		for sz in [-0.15, 0.15]:
			cart.torus(Vector3(sx, 0.0, sz), Vector3(0, 0, 1), 0.035, 0.012, 10, 8)
	cart.capsule(Vector3(0, 0.04, 0), Vector3(0, 1.12, 0), 0.03, 12, 3)
	_add_mesh(root, cart.commit("monitor_cart"), MaterialFactory.metal(), "Cart")

	var case := MeshBuilder.new()
	case.box(Vector3(0, 1.32, 0.0), Vector3(0.44, 0.34, 0.22), Vector2(2.0, 2.0))
	case.box(Vector3(0, 1.12, 0.02), Vector3(0.42, 0.06, 0.2), Vector2(2.0, 1.0))
	_add_mesh(root, case.commit("monitor_case"), MaterialFactory.plastic(), "Case")

	# Экран — плоскость чуть впереди корпуса, со своим шейдером кардиограммы.
	var screen := MeshBuilder.new()
	screen.rect(Vector3(-0.18, 1.20, 0.113), Vector3(0.36, 0, 0), Vector3(0, 0.24, 0))
	_add_mesh(root, screen.commit("monitor_screen"), MaterialFactory.crt(bpm, Color(0.35, 1.0, 0.62), flatline), "Screen")

	# Кнопки: несколько мелких корпусов с подсветкой.
	var buttons := MeshBuilder.new()
	buttons.box(Vector3(0.0, 1.13, 0.115), Vector3(0.30, 0.03, 0.01))
	_add_mesh(root, buttons.commit("monitor_buttons"), MaterialFactory.emissive(Color(0.55, 0.75, 0.6), 0.8), "Buttons")

	# Кабель питания, уходящий за стойку.
	var cable := MeshBuilder.new()
	cable.tube_along(PackedVector3Array([
		Vector3(0, 1.14, -0.1), Vector3(0.1, 0.6, -0.2), Vector3(0.2, 0.06, -0.3),
	]), 0.008, 6)
	_add_mesh(root, cable.commit("monitor_cable"), MaterialFactory.rubber(), "Cable")

	var body := _static("MonitorBody")
	_add_box_collision(body, Vector3(0.5, 1.5, 0.45), Vector3(0, 0.75, 0))
	root.add_child(body)
	root.set_meta(&"blocking", true)
	return root


## Потолочный светильник палаты. Возвращает ноду со светом — уровень может гасить.
static func create_lamp(position: Vector3, yaw := 0.0, energy := 1.6,
		color := Color(0.86, 0.92, 1.0)) -> Node3D:
	var root := Node3D.new()
	root.name = "Lamp"
	root.position = position
	root.rotation.y = yaw

	var builder := MeshBuilder.new()
	builder.box(Vector3(0, 2.70, 0), Vector3(1.18, 0.08, 0.30), Vector2(3.0, 1.0))
	_add_mesh(root, builder.commit("lamp_case"), MaterialFactory.painted_metal(), "Case")

	var panel := MeshBuilder.new()
	panel.rect(Vector3(-0.56, 2.655, -0.13), Vector3(1.12, 0, 0), Vector3(0, 0, 0.26))
	_add_mesh(root, panel.commit("lamp_panel"), MaterialFactory.emissive(color, energy * 1.4), "Panel")

	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = Vector3(0, 2.55, 0)
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 7.5
	light.shadow_enabled = true
	light.light_specular = 1.0
	light.light_volumetric_fog_energy = 1.4
	root.add_child(light)
	return root


## Настенные часы с остановившейся секундной стрелкой — деталь, которую
## замечают не сразу, а потом уже не могут развидеть.
static func create_clock(position: Vector3, yaw := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Clock"
	root.position = position
	root.rotation.y = yaw

	var case := MeshBuilder.new()
	case.cylinder(Vector3(0, 0, 0.02), Vector3(0, 0, 0.06), 0.14, 0.14, 20, true)
	_add_mesh(root, case.commit("clock_case"), MaterialFactory.plastic(), "Case")

	var face := MeshBuilder.new()
	face.disc(Vector3(0, 0, 0.061), 0.125, 24, Vector3(0, 0, 1))
	_add_mesh(root, face.commit("clock_face"), MaterialFactory.emissive(Color(0.85, 0.85, 0.78), 0.25), "Face")

	var hands := MeshBuilder.new()
	hands.box(Vector3(0, 0.045, 0.068), Vector3(0.012, 0.09, 0.004))
	hands.box(Vector3(0.035, 0.0, 0.068), Vector3(0.07, 0.012, 0.004))
	_add_mesh(root, hands.commit("clock_hands"), MaterialFactory.plastic(), "Hands")
	return root


## Умывальник с зеркалом и краном: единственная вода в блоке.
static func create_sink(position: Vector3, yaw := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Sink"
	root.position = position
	root.rotation.y = yaw

	var body := MeshBuilder.new()
	body.box(Vector3(0, 0.42, 0.16), Vector3(0.60, 0.16, 0.42), Vector2(2.0, 2.0))
	body.box(Vector3(0, 0.60, 0.30), Vector3(0.62, 0.10, 0.14), Vector2(2.0, 1.0))
	# Чаша.
	body.box(Vector3(0, 0.50, 0.16), Vector3(0.44, 0.10, 0.30), Vector2(2.0, 1.0))
	_add_mesh(root, body.commit("sink_body"), MaterialFactory.plastic(), "Body")

	var basin := MeshBuilder.new()
	basin.cylinder(Vector3(0, 0.52, 0.16), Vector3(0, 0.46, 0.16), 0.15, 0.12, 20, false)
	_add_mesh(root, basin.commit("sink_basin"), MaterialFactory.metal(), "Basin")

	var faucet := MeshBuilder.new()
	faucet.cylinder(Vector3(0, 0.56, 0.34), Vector3(0, 0.78, 0.34), 0.018, 0.016, 12, true)
	faucet.capsule(Vector3(0, 0.78, 0.34), Vector3(0, 0.76, 0.20), 0.016, 10, 3)
	faucet.capsule(Vector3(0.06, 0.74, 0.34), Vector3(0.06, 0.70, 0.30), 0.012, 8, 2)
	_add_mesh(root, faucet.commit("sink_faucet"), MaterialFactory.metal(), "Faucet")

	# Зеркало: стекло с грязью. Здесь герой впервые видит, что тела нет.
	var mirror := MeshBuilder.new()
	mirror.rect(Vector3(-0.30, 0.80, 0.06), Vector3(0.60, 0, 0), Vector3(0, 0.62, 0))
	_add_mesh(root, mirror.commit("sink_mirror"), MaterialFactory.glass(), "Mirror")

	var body_node := _static("SinkBody")
	_add_box_collision(body_node, Vector3(0.64, 0.9, 0.5), Vector3(0, 0.45, 0.2))
	root.add_child(body_node)
	return root


## Шкаф с распахнутыми дверцами: внутри — растворы, лотки, бинты.
static func create_cabinet(position: Vector3, yaw := 0.0, open_left := 0.6,
		open_right := 0.1) -> Node3D:
	var root := Node3D.new()
	root.name = "Cabinet"
	root.position = position
	root.rotation.y = yaw
	var width := 1.1
	var height := 1.85
	var depth := 0.42

	var carcass := MeshBuilder.new()
	# Задняя стенка, боковины, полки.
	carcass.box(Vector3(0, height * 0.5, -depth * 0.5), Vector3(width, height, 0.03))
	carcass.box(Vector3(-width * 0.5, height * 0.5, 0), Vector3(0.03, height, depth))
	carcass.box(Vector3(width * 0.5, height * 0.5, 0), Vector3(0.03, height, depth))
	for i in range(0, 4):
		var y := 0.12 + float(i) * 0.52
		carcass.box(Vector3(0, y, 0), Vector3(width - 0.06, 0.025, depth - 0.04))
	_add_mesh(root, carcass.commit("cabinet_body"), MaterialFactory.painted_metal(), "Carcass")

	for side in [-1.0, 1.0]:
		var angle := open_left if side < 0.0 else open_right
		var leaf := Node3D.new()
		leaf.name = "Door_%s" % ("left" if side < 0.0 else "right")
		leaf.position = Vector3(side * width * 0.5, 0, depth * 0.5)
		leaf.rotation.y = angle * side
		root.add_child(leaf)
		var door_mesh := MeshBuilder.new()
		door_mesh.box(Vector3(-side * width * 0.25, height * 0.5, 0.0), Vector3(width * 0.5, height, 0.02), Vector2(2.0, 3.0))
		_add_mesh(leaf, door_mesh.commit("cabinet_door"), MaterialFactory.painted_metal(), "Door")

	# Содержимое: лотки, бутыли, бинты.
	var contents := MeshBuilder.new()
	for i in range(0, 5):
		var x := -0.32 + float(i) * 0.16
		contents.cylinder(Vector3(x, 0.66, 0.02), Vector3(x, 0.80, 0.02), 0.024, 0.024, 10, true)
	for i in range(0, 3):
		var x2 := -0.30 + float(i) * 0.28
		contents.box(Vector3(x2, 1.22, 0.0), Vector3(0.22, 0.06, 0.28), Vector2(1.0, 1.0))
	contents.box(Vector3(0.1, 1.74, 0.0), Vector3(0.3, 0.1, 0.3), Vector2(1.0, 1.0))
	_add_mesh(root, contents.commit("cabinet_contents"), MaterialFactory.plastic(), "Contents")

	var body := _static("CabinetBody")
	_add_box_collision(body, Vector3(width + 0.05, height, depth + 0.05), Vector3(0, height * 0.5, 0))
	root.add_child(body)
	return root


static func create_chair(position: Vector3, yaw := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Chair"
	root.position = position
	root.rotation.y = yaw
	var builder := MeshBuilder.new()
	builder.box(Vector3(0, 0.45, 0), Vector3(0.44, 0.05, 0.44), Vector2(2.0, 2.0))
	builder.box(Vector3(0, 0.75, -0.19), Vector3(0.42, 0.52, 0.04), Vector2(2.0, 2.0))
	for sx in [-0.19, 0.19]:
		for sz in [-0.19, 0.19]:
			builder.capsule(Vector3(sx, 0.42, sz), Vector3(sx, 0.02, sz), 0.014, 8, 2)
	_add_mesh(root, builder.commit("chair"), MaterialFactory.plastic(), "Chair")
	var body := _static("ChairBody")
	_add_box_collision(body, Vector3(0.46, 0.5, 0.46), Vector3(0, 0.25, 0))
	root.add_child(body)
	return root


## Инвалидная коляска: тот самый предмет, который «переезжает», пока герой
## отвлёкся на склейку кадра.
static func create_wheelchair(position: Vector3, yaw := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Wheelchair"
	root.position = position
	root.rotation.y = yaw

	var builder := MeshBuilder.new()
	builder.box(Vector3(0, 0.50, 0), Vector3(0.46, 0.06, 0.44), Vector2(2.0, 2.0))
	builder.box(Vector3(0, 0.86, -0.22), Vector3(0.44, 0.5, 0.04), Vector2(2.0, 2.0))
	for side in [-1.0, 1.0]:
		# Большое колесо с ободом и спицами.
		builder.torus(Vector3(0.30 * side, 0.30, -0.08), Vector3(1, 0, 0), 0.28, 0.022, 22, 10)
		builder.torus(Vector3(0.30 * side, 0.30, -0.08), Vector3(1, 0, 0), 0.24, 0.008, 20, 8)
		for i in range(0, 12):
			var angle := float(i) / 12.0 * TAU
			builder.capsule(
				Vector3(0.30 * side, 0.30, -0.08),
				Vector3(0.30 * side, 0.30 + cos(angle) * 0.27, -0.08 + sin(angle) * 0.27),
				0.004, 4, 1)
		# Малое колесо.
		builder.torus(Vector3(0.22 * side, 0.09, 0.24), Vector3(1, 0, 0), 0.09, 0.016, 14, 8)
		# Подлокотник.
		builder.capsule(Vector3(0.24 * side, 0.70, -0.18), Vector3(0.24 * side, 0.70, 0.14), 0.018, 8, 2)
		builder.capsule(Vector3(0.24 * side, 0.50, -0.18), Vector3(0.24 * side, 0.70, -0.18), 0.014, 6, 2)
	_add_mesh(root, builder.commit("wheelchair"), MaterialFactory.metal(), "Wheelchair")

	var seat := MeshBuilder.new()
	seat.box(Vector3(0, 0.545, 0.0), Vector3(0.42, 0.04, 0.4), Vector2(1.0, 1.0))
	_add_mesh(root, seat.commit("wheelchair_seat"), MaterialFactory.fabric(Color(0.36, 0.40, 0.42)), "Seat")

	var body := _static("WheelchairBody")
	_add_box_collision(body, Vector3(0.7, 0.9, 0.7), Vector3(0, 0.45, 0))
	root.add_child(body)
	return root


## Трубы и кабели под потолком — обязательная деталь больничного кадра.
static func create_pipe_run(points: PackedVector3Array, radius := 0.035,
		material: Material = null) -> Node3D:
	var root := Node3D.new()
	root.name = "Pipes"
	var builder := MeshBuilder.new()
	builder.tube_along(points, radius, 10)
	for i in range(0, points.size() - 1):
		var mid := (points[i] + points[i + 1]) * 0.5
		if points[i].distance_to(points[i + 1]) > 1.2:
			builder.capsule(mid - Vector3(0, 0.08, 0), mid, 0.012, 6, 2)
	_add_mesh(root, builder.commit("pipes"), material if material != null else MaterialFactory.metal())
	return root


## Каталка «под завязку»: тело под простынёй — но это не тело, а складки ткани.
static func create_covered_gurney(position: Vector3, yaw := 0.0) -> Node3D:
	var root := create_gurney(position, yaw, false)
	var shape := MeshBuilder.new()
	# Силуэт под простынёй: длинный объём, приподнятость в районе груди,
	# провал на месте лица. Человек читается, человека нет.
	shape.ellipsoid(Vector3(0, 0.93, 0.15), Vector3(0.30, 0.12, 0.85), 14, 20)
	shape.ellipsoid(Vector3(0, 1.00, -0.42), Vector3(0.24, 0.13, 0.28), 12, 18)
	shape.ellipsoid(Vector3(0, 0.92, -0.72), Vector3(0.16, 0.10, 0.16), 10, 14)
	shape.capsule(Vector3(-0.22, 0.90, 0.5), Vector3(0.22, 0.90, 0.62), 0.09, 10, 3)
	var mesh := _add_mesh(root, shape.commit("covered"), MaterialFactory.fabric(Color(0.86, 0.87, 0.84)), "Cover")
	mesh.set_meta(&"is_cover", true)
	root.set_meta(&"covered", true)
	return root
