class_name MeshBuilder
extends RefCounted
## Процедурная геометрия. Весь «настоящий» реквизит игры — руки, маска, тело,
## стены, мониторы, каталки — собирается из этих примитивов кодом и может быть
## выгружен в .obj (tools/export_props.gd) для тех, кто хочет править форму в
## Blender. Ноль внешних моделей: ассетов-картинок в проекте нет вообще.
##
## ВАЖНО О ПОРЯДКЕ ОБХОДА ВЕРШИН: Godot считает лицевыми треугольники, идущие
## по часовой стрелке со стороны наблюдателя. Это значит, что у корректно
## ориентированного треугольника векторное произведение (b-a)×(c-a) направлено
## ВНУТРЬ поверхности. В `_tri` это проверяется автоматически по внешней
## нормали, поэтому примитивы можно писать «в лоб».

## Аварийный переключатель: если на конкретной сборке движка окажется, что
## грани вывернуты (например, при смене соглашения), ставим true и вся
## сгенерированная геометрия переворачивается разом.
var flip_winding := false

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _colors := PackedColorArray()
var _use_colors := false


func vertex_count() -> int:
	return _vertices.size()


func triangle_count() -> int:
	return _vertices.size() / 3


# --- Ядро ---------------------------------------------------------------------

func _emit(p: Vector3, n: Vector3, uv: Vector2, c: Color) -> void:
	_vertices.append(p)
	_normals.append(n)
	_uvs.append(uv)
	if _use_colors:
		_colors.append(c)


## Треугольник с автоматической ориентацией под соглашение Godot.
func _tri(p0: Vector3, p1: Vector3, p2: Vector3,
		n0: Vector3, n1: Vector3, n2: Vector3,
		uv0: Vector2, uv1: Vector2, uv2: Vector2,
		outward: Vector3, c := Color.WHITE) -> void:
	var rhs := (p1 - p0).cross(p2 - p0)
	var keep := rhs.dot(outward) < 0.0
	if flip_winding:
		keep = not keep
	if keep:
		_emit(p0, n0, uv0, c)
		_emit(p1, n1, uv1, c)
		_emit(p2, n2, uv2, c)
	else:
		_emit(p0, n0, uv0, c)
		_emit(p2, n2, uv2, c)
		_emit(p1, n1, uv1, c)


func use_vertex_colors() -> void:
	_use_colors = true


# --- Примитивы ----------------------------------------------------------------

## Четырёхугольник против часовой стрелки, если смотреть с внешней стороны.
func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		uv_scale := Vector2.ONE, normal := Vector3.ZERO, color := Color.WHITE) -> void:
	var n := normal
	if n.is_zero_approx():
		n = (p1 - p0).cross(p3 - p0).normalized()
	if n.is_zero_approx():
		n = Vector3.UP
	var uv0 := Vector2(0.0, 1.0) * uv_scale
	var uv1 := Vector2(1.0, 1.0) * uv_scale
	var uv2 := Vector2(1.0, 0.0) * uv_scale
	var uv3 := Vector2(0.0, 0.0) * uv_scale
	_tri(p0, p1, p2, n, n, n, uv0, uv1, uv2, n, color)
	_tri(p0, p2, p3, n, n, n, uv0, uv2, uv3, n, color)


## Прямоугольник в мировых метрах: удобно для стен, полов и потолков,
## потому что UV сразу в метрах и процедурные шейдеры тайлятся правильно.
func rect(origin: Vector3, right: Vector3, up: Vector3, color := Color.WHITE) -> void:
	var p0 := origin
	var p1 := origin + right
	var p2 := origin + right + up
	var p3 := origin + up
	var n := right.cross(up).normalized()
	var su := right.length()
	var sv := up.length()
	_tri(p0, p1, p2, n, n, n, Vector2(0, sv), Vector2(su, sv), Vector2(su, 0), n, color)
	_tri(p0, p2, p3, n, n, n, Vector2(0, sv), Vector2(su, 0), Vector2(0, 0), n, color)


func box(center: Vector3, size: Vector3, uv_scale := Vector2.ONE, color := Color.WHITE) -> void:
	var h := size * 0.5
	var corners := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, h.y, -h.z), center + Vector3(-h.x, h.y, -h.z),
		center + Vector3(-h.x, -h.y, h.z), center + Vector3(h.x, -h.y, h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
	]
	# Перед (+Z), зад (-Z), право (+X), лево (-X), верх (+Y), низ (-Y).
	_face(corners[4], corners[5], corners[6], corners[7], Vector3(0, 0, 1), uv_scale, color)
	_face(corners[1], corners[0], corners[3], corners[2], Vector3(0, 0, -1), uv_scale, color)
	_face(corners[5], corners[1], corners[2], corners[6], Vector3(1, 0, 0), uv_scale, color)
	_face(corners[0], corners[4], corners[7], corners[3], Vector3(-1, 0, 0), uv_scale, color)
	_face(corners[3], corners[7], corners[6], corners[2], Vector3(0, 1, 0), uv_scale, color)
	_face(corners[0], corners[1], corners[5], corners[4], Vector3(0, -1, 0), uv_scale, color)


func _face(a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		n: Vector3, uv_scale: Vector2, color := Color.WHITE) -> void:
	var w := (b - a).length()
	var h := (c - b).length()
	var su := w * uv_scale.x
	var sv := h * uv_scale.y
	_tri(a, b, c, n, n, n, Vector2(0, sv), Vector2(su, sv), Vector2(su, 0), n, color)
	_tri(a, c, d, n, n, n, Vector2(0, sv), Vector2(su, 0), Vector2(0, 0), n, color)


## Сфера/эллипсоид: основа торса (тело), головы под маску, шары ламп.
func ellipsoid(center: Vector3, radius: Vector3, rings := 16, segments := 24,
		color := Color.WHITE) -> void:
	for r in range(0, rings):
		var v0 := float(r) / float(rings)
		var v1 := float(r + 1) / float(rings)
		var phi0 := v0 * PI
		var phi1 := v1 * PI
		for s in range(0, segments):
			var u0 := float(s) / float(segments)
			var u1 := float(s + 1) / float(segments)
			var th0 := u0 * TAU
			var th1 := u1 * TAU
			var p00 := _sphere_point(center, radius, phi0, th0)
			var p10 := _sphere_point(center, radius, phi1, th0)
			var p11 := _sphere_point(center, radius, phi1, th1)
			var p01 := _sphere_point(center, radius, phi0, th1)
			var n00 := _sphere_normal(center, radius, p00)
			var n10 := _sphere_normal(center, radius, p10)
			var n11 := _sphere_normal(center, radius, p11)
			var n01 := _sphere_normal(center, radius, p01)
			var q00 := Vector2(u0, v0)
			var q10 := Vector2(u0, v1)
			var q11 := Vector2(u1, v1)
			var q01 := Vector2(u1, v0)
			_tri(p00, p10, p11, n00, n10, n11, q00, q10, q11, n00, color)
			_tri(p00, p11, p01, n00, n11, n01, q00, q11, q01, n00, color)


func _sphere_point(center: Vector3, radius: Vector3, phi: float, theta: float) -> Vector3:
	return center + Vector3(
		sin(phi) * cos(theta) * radius.x,
		cos(phi) * radius.y,
		sin(phi) * sin(theta) * radius.z
	)


func _sphere_normal(center: Vector3, radius: Vector3, p: Vector3) -> Vector3:
	return Vector3(
		(p.x - center.x) / maxf(radius.x, 0.0001),
		(p.y - center.y) / maxf(radius.y, 0.0001),
		(p.z - center.z) / maxf(radius.z, 0.0001)
	).normalized()


## Цилиндр/усечённый конус между двумя точками. Основа труб, штативов, поручней.
func cylinder(p0: Vector3, p1: Vector3, r0: float, r1: float, segments := 16,
		caps := true, color := Color.WHITE) -> void:
	var axis := (p1 - p0)
	var length := axis.length()
	if length < 0.0001:
		return
	var dir := axis / length
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var tangent := dir.cross(up).normalized()
	var bitangent := dir.cross(tangent).normalized()
	for s in range(0, segments):
		var u0 := float(s) / float(segments)
		var u1 := float(s + 1) / float(segments)
		var a0 := u0 * TAU
		var a1 := u1 * TAU
		var n0 := (tangent * cos(a0) + bitangent * sin(a0)).normalized()
		var n1 := (tangent * cos(a1) + bitangent * sin(a1)).normalized()
		var b0 := p0 + n0 * r0
		var b1 := p0 + n1 * r0
		var t0 := p1 + n0 * r1
		var t1 := p1 + n1 * r1
		var sn0 := n0 if is_zero_approx(r1 - r0) else (n0 + dir * ((r0 - r1) / length)).normalized()
		var sn1 := n1 if is_zero_approx(r1 - r0) else (n1 + dir * ((r0 - r1) / length)).normalized()
		var uv0 := Vector2(u0 * 4.0, 0.0)
		var uv1 := Vector2(u1 * 4.0, 0.0)
		var uv2 := Vector2(u1 * 4.0, length)
		var uv3 := Vector2(u0 * 4.0, length)
		_tri(b0, t0, t1, sn0, sn0, sn1, uv0, uv2, uv3, n0, color)
		_tri(b0, t1, b1, sn0, sn1, sn1, uv0, uv3, uv1, n0, color)
		if caps:
			# Крышки: веером от центра, чтобы нормали были честными.
			_tri(p0, b1, b0, -dir, -dir, -dir,
				Vector2(0.5, 0.5), Vector2(u1, 0.0), Vector2(u0, 0.0), -dir, color)
			_tri(p1, t0, t1, dir, dir, dir,
				Vector2(0.5, 0.5), Vector2(u0, 0.0), Vector2(u1, 0.0), dir, color)


## Капсула — пальцы, конечности, шланги. Полусферы + цилиндр.
func capsule(p0: Vector3, p1: Vector3, radius: float, segments := 14, rings := 6,
		color := Color.WHITE) -> void:
	var axis := p1 - p0
	var length := axis.length()
	if length < 0.0001:
		ellipsoid(p0, Vector3.ONE * radius, rings * 2, segments, color)
		return
	var dir := axis / length
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var tangent := dir.cross(up).normalized()
	var bitangent := dir.cross(tangent).normalized()

	# Тело
	cylinder(p0, p1, radius, radius, segments, false, color)

	# Две полусферы, у которых исключены экваториальные дубли.
	for side in [0, 1]:
		var base := p0 if side == 0 else p1
		var sign_dir := -dir if side == 0 else dir
		for r in range(0, rings):
			var v0 := (float(r) / float(rings)) * (PI * 0.5)
			var v1 := (float(r + 1) / float(rings)) * (PI * 0.5)
			for s in range(0, segments):
				var u0 := float(s) / float(segments)
				var u1 := float(s + 1) / float(segments)
				var a0 := u0 * TAU
				var a1 := u1 * TAU
				var d00 := _cap_point(base, tangent, bitangent, sign_dir, radius, v0, a0)
				var d10 := _cap_point(base, tangent, bitangent, sign_dir, radius, v1, a0)
				var d11 := _cap_point(base, tangent, bitangent, sign_dir, radius, v1, a1)
				var d01 := _cap_point(base, tangent, bitangent, sign_dir, radius, v0, a1)
				var m00 := (d00 - base).normalized()
				var m10 := (d10 - base).normalized()
				var m11 := (d11 - base).normalized()
				var m01 := (d01 - base).normalized()
				var uv0 := Vector2(u0, v0)
				var uv1 := Vector2(u0, v1)
				var uv2 := Vector2(u1, v1)
				var uv3 := Vector2(u1, v0)
				_tri(d00, d10, d11, m00, m10, m11, uv0, uv1, uv2, m00, color)
				_tri(d00, d11, d01, m00, m11, m01, uv0, uv2, uv3, m00, color)


func _cap_point(base: Vector3, tangent: Vector3, bitangent: Vector3, dir: Vector3,
		radius: float, phi: float, theta: float) -> Vector3:
	var radial := (tangent * cos(theta) + bitangent * sin(theta)) * cos(phi) * radius
	var along := dir * sin(phi) * radius
	return base + radial + along


## Тор — обод маски, поручни, манжета тонометра.
func torus(center: Vector3, axis: Vector3, major: float, minor: float,
		segments := 20, tube_segments := 10, color := Color.WHITE) -> void:
	var dir := axis.normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var tangent := dir.cross(up).normalized()
	var bitangent := dir.cross(tangent).normalized()
	for s in range(0, segments):
		var u0 := float(s) / float(segments)
		var u1 := float(s + 1) / float(segments)
		var a0 := u0 * TAU
		var a1 := u1 * TAU
		var c0 := center + (tangent * cos(a0) + bitangent * sin(a0)) * major
		var c1 := center + (tangent * cos(a1) + bitangent * sin(a1)) * major
		var out0 := (tangent * cos(a0) + bitangent * sin(a0)).normalized()
		var out1 := (tangent * cos(a1) + bitangent * sin(a1)).normalized()
		for t in range(0, tube_segments):
			var b0 := (float(t) / float(tube_segments)) * TAU
			var b1 := (float(t + 1) / float(tube_segments)) * TAU
			var n00 := (out0 * cos(b0) + dir * sin(b0)).normalized()
			var n01 := (out0 * cos(b1) + dir * sin(b1)).normalized()
			var n10 := (out1 * cos(b0) + dir * sin(b0)).normalized()
			var n11 := (out1 * cos(b1) + dir * sin(b1)).normalized()
			var p00 := c0 + n00 * minor
			var p01 := c0 + n01 * minor
			var p10 := c1 + n10 * minor
			var p11 := c1 + n11 * minor
			var uv00 := Vector2(u0 * 8.0, float(t) / float(tube_segments))
			var uv01 := Vector2(u0 * 8.0, float(t + 1) / float(tube_segments))
			var uv10 := Vector2(u1 * 8.0, float(t) / float(tube_segments))
			var uv11 := Vector2(u1 * 8.0, float(t + 1) / float(tube_segments))
			_tri(p00, p10, p11, n00, n10, n11, uv00, uv10, uv11, n00, color)
			_tri(p00, p11, p01, n00, n11, n01, uv00, uv11, uv01, n00, color)


## Трубка по ломаной — катетеры, кабели, кислородные линии.
func tube_along(points: PackedVector3Array, radius: float, segments := 8,
		color := Color.WHITE) -> void:
	if points.size() < 2:
		return
	for i in range(0, points.size() - 1):
		capsule(points[i], points[i + 1], radius, segments, 3, color)


## Выдавливание замкнутого профиля (в плоскости XY) вдоль Z.
## Так собирается маска: профиль лица + толщина. UV: обход периметра × глубина.
func extrude(profile: PackedVector2Array, depth: float, offset := Vector3.ZERO,
		color := Color.WHITE) -> void:
	var count := profile.size()
	if count < 3:
		return
	var perimeter := 0.0
	var lengths := PackedFloat32Array()
	for i in range(0, count):
		var a := profile[i]
		var b := profile[(i + 1) % count]
		var l := a.distance_to(b)
		lengths.append(l)
		perimeter += l
	if perimeter <= 0.0001:
		return

	var front_z := depth * 0.5
	var back_z := -depth * 0.5
	var walked := 0.0
	for i in range(0, count):
		var a := profile[i]
		var b := profile[(i + 1) % count]
		var edge := b - a
		var normal2 := Vector2(edge.y, -edge.x).normalized()
		var u0 := walked / perimeter
		var u1 := (walked + lengths[i]) / perimeter
		walked += lengths[i]

		var a3f := Vector3(a.x, a.y, front_z) + offset
		var b3f := Vector3(b.x, b.y, front_z) + offset
		var a3b := Vector3(a.x, a.y, back_z) + offset
		var b3b := Vector3(b.x, b.y, back_z) + offset
		var n := Vector3(normal2.x, normal2.y, 0.0).normalized()

		var uv0 := Vector2(u0, 0.0)
		var uv1 := Vector2(u1, 0.0)
		var uv2 := Vector2(u1, 1.0)
		var uv3 := Vector2(u0, 1.0)
		# Боковая стенка
		_tri(a3b, b3b, b3f, n, n, n, uv0, uv1, uv2, n, color)
		_tri(a3b, b3f, a3f, n, n, n, uv0, uv2, uv3, n, color)

	# Передняя и задняя крышки — веером от центра масс профиля.
	var centroid := Vector2.ZERO
	for p in profile:
		centroid += p
	centroid /= float(count)
	var uv_center := Vector2(0.5, 0.5)
	var center_front := Vector3(centroid.x, centroid.y, front_z) + offset
	var center_back := Vector3(centroid.x, centroid.y, back_z) + offset
	for i in range(0, count):
		var a := profile[i]
		var b := profile[(i + 1) % count]
		var af := Vector3(a.x, a.y, front_z) + offset
		var bf := Vector3(b.x, b.y, front_z) + offset
		var ab := Vector3(a.x, a.y, back_z) + offset
		var bb := Vector3(b.x, b.y, back_z) + offset
		var u0 := Vector2((a.x - centroid.x), (a.y - centroid.y)) * 0.5
		var u1 := Vector2((b.x - centroid.x), (b.y - centroid.y)) * 0.5
		_tri(center_front, af, bf, Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD,
			uv_center, u0, u1, Vector3.FORWARD, color)
		_tri(center_back, bb, ab, Vector3.BACK, Vector3.BACK, Vector3.BACK,
			uv_center, u1, u0, Vector3.BACK, color)


## Плоский диск — лужа, пятно крови, световое пятно на полу.
func disc(center: Vector3, radius: float, segments := 24, up := Vector3.UP,
		color := Color.WHITE) -> void:
	for s in range(0, segments):
		var a0 := (float(s) / float(segments)) * TAU
		var a1 := (float(s + 1) / float(segments)) * TAU
		var dir0 := Vector3(cos(a0), 0.0, sin(a0))
		var dir1 := Vector3(cos(a1), 0.0, sin(a1))
		_tri(center, center + dir0 * radius, center + dir1 * radius,
			up, up, up, Vector2(0.5, 0.5), Vector2(0.5, 0.5) + Vector2(dir0.x, dir0.z) * 0.5,
			Vector2(0.5, 0.5) + Vector2(dir1.x, dir1.z) * 0.5, up, color)


## Профиль для маски: симметричный контур лица в плоскости XY.
## Возвращает точки против часовой стрелки — extrude сам разберётся с ориентацией.
static func mask_profile(width := 0.105, height := 0.145, cheek := 0.78) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := 28
	for i in range(0, steps):
		var t := float(i) / float(steps) * TAU
		# Форма: сверху лоб уже, снизу подбородок вытянут, бока — скулы.
		var x := sin(t) * width * (1.0 - 0.18 * absf(cos(t)))
		var y := cos(t) * height
		if y < 0.0:
			y *= 1.12
		else:
			x *= cheek
		points.append(Vector2(x, y))
	return points


# --- Сборка -------------------------------------------------------------------

func commit(surface_name := "procedural") -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	if _use_colors:
		arrays[Mesh.ARRAY_COLOR] = _colors
	var mesh := ArrayMesh.new()
	mesh.resource_name = surface_name
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Триангулированный меш → текст .obj (для выгрузки в Blender).
func to_obj(obj_name := "mydriasis_part") -> String:
	var text := "# Mydriasis Studio — процедурная геометрия\n"
	text += "# Сгенерировано MeshBuilder, порядок обхода: по часовой снаружи.\n"
	text += "o %s\n" % obj_name
	for v in _vertices:
		text += "v %.5f %.5f %.5f\n" % [v.x, v.y, v.z]
	for n in _normals:
		text += "vn %.5f %.5f %.5f\n" % [n.x, n.y, n.z]
	for uv in _uvs:
		text += "vt %.5f %.5f\n" % [uv.x, uv.y]
	var triangles := _vertices.size() / 3
	for i in range(0, triangles):
		var a := i * 3 + 1
		text += "f %d/%d/%d %d/%d/%d %d/%d/%d\n" % [a, a, a, a + 1, a + 1, a + 1, a + 2, a + 2, a + 2]
	return text


## Габаритный размер — для расстановки и проверок в тестах.
func bounds() -> AABB:
	if _vertices.is_empty():
		return AABB()
	var box := AABB(_vertices[0], Vector3.ZERO)
	for v in _vertices:
		box = box.expand(v)
	return box
