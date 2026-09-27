class_name AvatarBuilder
extends RefCounted
## Фабрики геометрии героя и его реквизита.
##
## Тело строится как телесная оболочка — по ней шейдер режет дыру.
## Ни одна часть тела не имеет текстуры-картинки: только форма и шейдер.
## Руки и маска — наоборот, максимально плотная геометрия: именно они должны
## читаться резко на фоне размытой пустоты вместо тела.

const HEIGHT := 1.78
const SHOULDER_HEIGHT := 1.44
const SHOULDER_WIDTH := 0.20
const HEAD_HEIGHT := 1.62


## Телесная оболочка: то, что становится дырой. Силуэт должен читаться
## человеком даже когда внутри силуэта нет ничего, кроме размытого фона.
static func build_body_hull() -> ArrayMesh:
	var b := MeshBuilder.new()
	# Грудная клетка и живот.
	b.ellipsoid(Vector3(0, 1.24, 0), Vector3(0.205, 0.235, 0.135), 18, 28)
	# Таз.
	b.ellipsoid(Vector3(0, 0.99, 0), Vector3(0.175, 0.145, 0.125), 14, 24)
	# Плечевой пояс — чуть шире, чтобы силуэт был живым, а не цилиндром.
	b.ellipsoid(Vector3(-0.145, 1.40, 0), Vector3(0.095, 0.085, 0.095), 12, 18)
	b.ellipsoid(Vector3(0.145, 1.40, 0), Vector3(0.095, 0.085, 0.095), 12, 18)
	# Шея и голова (лицо будет под маской, но череп должен быть на месте).
	b.cylinder(Vector3(0, 1.40, 0.005), Vector3(0, 1.545, 0.005), 0.058, 0.052, 14, false)
	b.ellipsoid(Vector3(0, HEAD_HEIGHT, 0.004), Vector3(0.096, 0.116, 0.104), 16, 24)
	# Бёдра, голени, стопы.
	for side in [-1.0, 1.0]:
		b.capsule(Vector3(0.092 * side, 0.965, 0.0), Vector3(0.098 * side, 0.535, 0.012), 0.078, 14, 4)
		b.capsule(Vector3(0.098 * side, 0.515, 0.008), Vector3(0.093 * side, 0.115, 0.014), 0.056, 12, 4)
		b.capsule(Vector3(0.093 * side, 0.055, -0.03), Vector3(0.093 * side, 0.045, 0.115), 0.045, 10, 3)
	# Ключицы — мелкая деталь силуэта, но она читается.
	b.capsule(Vector3(-0.02, 1.435, 0.03), Vector3(-0.155, 1.43, 0.005), 0.017, 8, 2)
	b.capsule(Vector3(0.02, 1.435, 0.03), Vector3(0.155, 1.43, 0.005), 0.017, 8, 2)
	return b.commit("body_hull")


## Оболочка руки без кисти: плечо + предплечье. Кисть собирается ригом
## по фалангам, чтобы ей можно было управлять.
static func build_upper_arm(side: float, length_upper := 0.29, length_fore := 0.26) -> ArrayMesh:
	var b := MeshBuilder.new()
	# Плечо: от сустава вниз, с утолщением дельтовидной мышцы.
	b.capsule(Vector3(0, 0, 0), Vector3(0, -length_upper, 0.0), 0.052, 14, 4)
	b.ellipsoid(Vector3(0, 0.01, 0), Vector3(0.062, 0.055, 0.058), 12, 18)
	b.capsule(Vector3(0, -length_upper, 0), Vector3(0, -length_upper - length_fore, 0.0), 0.044, 12, 4)
	# Локоть.
	b.ellipsoid(Vector3(0, -length_upper - 0.005, -0.004), Vector3(0.045, 0.038, 0.045), 10, 16)
	var mesh := b.commit("upper_arm_%s" % ("l" if side < 0.0 else "r"))
	return mesh


## Кисть: ладонь + тенар + костяшки. Пальцы — риг.
static func build_palm(side: float) -> ArrayMesh:
	var b := MeshBuilder.new()
	# Ладонь: сплющенный эллипсоид.
	b.ellipsoid(Vector3(0, 0, -0.045), Vector3(0.048, 0.021, 0.058), 14, 22)
	# Тенар (мышца большого пальца).
	b.ellipsoid(Vector3(-0.034 * side, -0.006, -0.028), Vector3(0.026, 0.018, 0.034), 10, 16)
	# Гипотенар.
	b.ellipsoid(Vector3(0.038 * side, 0.0, -0.032), Vector3(0.02, 0.015, 0.03), 10, 14)
	# Костяшки.
	for i in range(0, 4):
		var x := (-0.030 + 0.020 * float(i)) * side
		b.ellipsoid(Vector3(x, 0.008, -0.098), Vector3(0.011, 0.009, 0.011), 8, 12)
	return b.commit("palm_%s" % ("l" if side < 0.0 else "r"))


## Фаланга пальца: тело + суставные шары, чтобы сгиб читался геометрией.
static func build_phalanx(length: float, radius: float, knuckle: bool) -> ArrayMesh:
	var b := MeshBuilder.new()
	var r := radius if knuckle else radius * 0.9
	b.capsule(Vector3.ZERO, Vector3(0, 0, -length), r, 12, 3)
	if knuckle:
		b.ellipsoid(Vector3(0, 0, -length), Vector3.ONE * r * 1.05, 10, 14)
	return b.commit("phalanx")


## Ноготь: отдельный материал (глянцевый, светлее кожи).
static func build_nail(length: float, width: float, offset_z: float) -> ArrayMesh:
	var b := MeshBuilder.new()
	b.ellipsoid(Vector3(0, 0.006, -offset_z), Vector3(width, 0.0035, length), 8, 12)
	return b.commit("nail")


## Маска: контур лица, выдавленный в толщину, плюс обод, клапаны и ремни.
## Это единственное «лицо» героя — и единственная резкая форма на голове.
static func build_mask(mask_scale := 1.06) -> ArrayMesh:
	var b := MeshBuilder.new()
	var profile := MeshBuilder.mask_profile(0.104 * mask_scale, 0.142 * mask_scale)
	# Оболочка маски.
	b.extrude(profile, 0.062, Vector3(0, 0, 0.0))
	# Обод по периметру.
	var count := profile.size()
	for i in range(0, count):
		var a := profile[i]
		var c := profile[(i + 1) % count]
		b.capsule(
			Vector3(a.x, a.y, 0.031),
			Vector3(c.x, c.y, 0.031),
			0.0075, 6, 2
		)
	return b.commit("mask_shell")


## Визор: слегка выгнутое стекло, за которым живёт отдельный шейдер.
static func build_visor() -> ArrayMesh:
	var b := MeshBuilder.new()
	var segments := 16
	var half_width := 0.086
	var half_height := 0.042
	var bulge := 0.020
	for i in range(0, segments):
		var u0 := -1.0 + 2.0 * float(i) / float(segments)
		var u1 := -1.0 + 2.0 * float(i + 1) / float(segments)
		var x0 := u0 * half_width
		var x1 := u1 * half_width
		var z0 := 0.030 + bulge * (1.0 - u0 * u0) * 0.9
		var z1 := 0.030 + bulge * (1.0 - u1 * u1) * 0.9
		# Верхняя и нижняя кромки визора скошены — как у настоящих очков-консервов.
		var y_top := half_height * (0.86 + 0.14 * (1.0 - absf(u0)))
		var y_bottom := -half_height * (0.72 + 0.10 * (1.0 - absf(u1)))
		b.quad(
			Vector3(x0, y_bottom, z0), Vector3(x1, y_bottom, z1),
			Vector3(x1, y_top, z1), Vector3(x0, y_top, z0),
			Vector2(1.0, 1.0), Vector3(0, 0, 1)
		)
	return b.commit("visor")


## Обратный клапан маски (дыхание слышно, пар идёт вниз, а не в визор).
static func build_valve() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.cylinder(Vector3(0, -0.052, 0.052), Vector3(0, -0.062, 0.086), 0.016, 0.019, 14, true)
	b.torus(Vector3(0, -0.060, 0.081), Vector3(0, -0.2, 1), 0.018, 0.004, 14, 8)
	return b.commit("mask_valve")


## Ремень маски: две лямки, уходящие за голову.
static func build_straps() -> ArrayMesh:
	var b := MeshBuilder.new()
	for side in [-1.0, 1.0]:
		b.capsule(
			Vector3(0.088 * side, 0.028, 0.008),
			Vector3(0.104 * side, 0.010, -0.075),
			0.012, 8, 2
		)
		b.capsule(
			Vector3(0.104 * side, 0.010, -0.075),
			Vector3(0.030 * side, -0.010, -0.118),
			0.011, 8, 2
		)
	# Затылочный узел.
	b.ellipsoid(Vector3(0, -0.010, -0.120), Vector3(0.026, 0.018, 0.012), 8, 12)
	return b.commit("mask_straps")


## Фильтр-патрон на щеке — тяжёлая деталь, которая сразу говорит: смена длинная.
static func build_filter() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.cylinder(Vector3(-0.088, -0.030, 0.020), Vector3(-0.128, -0.052, 0.006), 0.030, 0.034, 16, true)
	b.torus(Vector3(-0.120, -0.047, 0.010), Vector3(-0.7, -0.42, -0.28), 0.033, 0.005, 16, 8)
	for i in range(0, 6):
		var angle := float(i) / 6.0 * TAU
		b.capsule(
			Vector3(-0.094, -0.033, 0.019),
			Vector3(-0.098 + cos(angle) * 0.012, -0.036 + sin(angle) * 0.012, 0.016),
			0.0035, 6, 1
		)
	return b.commit("mask_filter")


## Фонарь: алюминиевый корпус, кольцо, стекло. Носится в правой руке.
static func build_flashlight() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.cylinder(Vector3(0, 0, 0.14), Vector3(0, 0, -0.05), 0.021, 0.024, 18, true)
	b.cylinder(Vector3(0, 0, -0.05), Vector3(0, 0, -0.085), 0.024, 0.034, 18, true)
	b.torus(Vector3(0, 0, -0.086), Vector3(0, 0, 1), 0.031, 0.005, 18, 8)
	b.cylinder(Vector3(0, 0, -0.082), Vector3(0, 0, -0.088), 0.030, 0.030, 16, true)
	# Накатка на корпусе.
	for i in range(0, 10):
		var z := 0.12 - float(i) * 0.016
		b.torus(Vector3(0, 0, z), Vector3(0, 0, 1), 0.0222, 0.0016, 14, 6)
	return b.commit("flashlight")


## Манжета тонометра на предплечье — интерфейс героя с собственным телом.
static func build_cuff(radius := 0.05) -> ArrayMesh:
	var b := MeshBuilder.new()
	b.cylinder(Vector3(0, 0, 0.0), Vector3(0, 0, 0.13), radius, radius * 0.96, 18, false)
	b.torus(Vector3(0, 0, 0.012), Vector3(0, 0, 1), radius + 0.004, 0.006, 18, 8)
	b.torus(Vector3(0, 0, 0.122), Vector3(0, 0, 1), radius - 0.001, 0.005, 18, 8)
	# Трубка, уходящая к манометру.
	b.capsule(Vector3(radius * 0.9, 0.0, 0.06), Vector3(radius + 0.11, -0.06, 0.02), 0.0055, 8, 2)
	return b.commit("cuff")


## Пустой силуэт для отладки камеры: показывает точку, куда смотрит голова.
static func build_debug_anchor() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.ellipsoid(Vector3.ZERO, Vector3.ONE * 0.03, 8, 12)
	b.cylinder(Vector3(0, 0, -0.05), Vector3(0, 0, -0.5), 0.004, 0.001, 8, false)
	return b.commit("debug_anchor")
