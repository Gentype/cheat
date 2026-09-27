extends SceneTree
## Выгрузка процедурной геометрии в OBJ — для правки формы в Blender.
##
## Запуск:
##   godot --headless --path . --script tools/export_props.gd
##   godot --headless --path . --script tools/export_props.gd -- --out=res://export/props
##
## Зачем это нужно: форму рук, маски, каталки и манжеты удобно доводить руками.
## Из Blender возвращается **только геометрия**: материалы остаются процедурными,
## поэтому выгруженные меши — это болванки для правки, а не игровые ассеты.
##
## Что выгружается:
##   * части аватара (оболочка-дыра, рука, кисть, фаланга, ноготь, маска, визор,
##     клапан, ремни, фильтр, фонарь, манжета);
##   * сборки реквизита блока (койка, каталка, штатив, монитор, лампа, часы,
##     раковина, шкаф, стул, кресло-коляска, труба, занавес, дверь).

const DEFAULT_OUT := "res://export/props"

var _out_dir := DEFAULT_OUT
var _written := 0
var _skipped := 0


func _initialize() -> void:
	_out_dir = _read_out_arg()
	var exit_code := _export_everything()
	if exit_code == 0:
		print("Экспорт завершён: %d файлов в %s" % [_written, _out_dir])
		if _skipped > 0:
			print("Пропущено пустых мешей: %d" % _skipped)
	else:
		push_error("Экспорт не удался: не записан ни один файл")
	quit(exit_code)


func _read_out_arg() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			return argument.trim_prefix("--out=")
	return DEFAULT_OUT


func _export_everything() -> int:
	var absolute := ProjectSettings.globalize_path(_out_dir)
	var error := DirAccess.make_dir_recursive_absolute(absolute)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("Не удалось создать каталог %s (код %d)" % [absolute, error])
		return 1

	_export_avatar_parts(absolute)
	_export_props(absolute)

	return 0 if _written > 0 else 1


# --- Части аватара ------------------------------------------------------------

func _export_avatar_parts(absolute: String) -> void:
	var parts := {
		"body_hull": AvatarBuilder.build_body_hull(),
		"arm_upper_left": AvatarBuilder.build_upper_arm(-1.0),
		"arm_upper_right": AvatarBuilder.build_upper_arm(1.0),
		"palm_left": AvatarBuilder.build_palm(-1.0),
		"palm_right": AvatarBuilder.build_palm(1.0),
		"phalanx_proximal": AvatarBuilder.build_phalanx(0.032, 0.0115, true),
		"phalanx_middle": AvatarBuilder.build_phalanx(0.026, 0.0105, false),
		"phalanx_distal": AvatarBuilder.build_phalanx(0.020, 0.0096, false),
		"nail": AvatarBuilder.build_nail(0.017, 0.012, -0.004),
		"mask": AvatarBuilder.build_mask(1.06),
		"visor": AvatarBuilder.build_visor(),
		"valve": AvatarBuilder.build_valve(),
		"straps": AvatarBuilder.build_straps(),
		"filter": AvatarBuilder.build_filter(),
		"flashlight": AvatarBuilder.build_flashlight(),
		"cuff": AvatarBuilder.build_cuff(),
	}
	for part_name in parts.keys():
		_write_mesh(absolute, "avatar_%s" % part_name, parts[part_name])


# --- Реквизит блока -----------------------------------------------------------

func _export_props(absolute: String) -> void:
	var tube := PackedVector3Array([
		Vector3(-0.4, 2.55, -1.0), Vector3(-0.4, 2.55, 0.6), Vector3(-0.1, 2.35, 1.2),
	])
	var assemblies := {
		"bed_empty": Props.create_bed(Vector3.ZERO, 0.0, false),
		"bed_occupied": Props.create_bed(Vector3.ZERO, 0.0, true),
		"gurney": Props.create_gurney(Vector3.ZERO),
		"covered_gurney": Props.create_covered_gurney(Vector3.ZERO),
		"iv_stand": Props.create_iv_stand(Vector3.ZERO, Vector3(0.2, 0.9, 0.1)),
		"monitor": Props.create_monitor(Vector3.ZERO, 0.0, 68.0, 0.0),
		"lamp": Props.create_lamp(Vector3.ZERO),
		"clock": Props.create_clock(Vector3.ZERO),
		"sink": Props.create_sink(Vector3.ZERO),
		"cabinet": Props.create_cabinet(Vector3.ZERO),
		"chair": Props.create_chair(Vector3.ZERO),
		"wheelchair": Props.create_wheelchair(Vector3.ZERO),
		"pipes": Props.create_pipe_run(tube),
		"curtain": Props.create_curtain(Vector3.ZERO, 0.0, 2.2),
		"door_open": Props.create_door(Vector3.ZERO, 0.0, 1.2, true),
		"door_closed": Props.create_door(Vector3.ZERO, 0.0, 0.0, false),
	}
	for assembly_name in assemblies.keys():
		_write_tree(absolute, assembly_name, assemblies[assembly_name])


func _write_tree(absolute: String, assembly_name: String, root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node := stack.pop_back() as Node
		if node is MeshInstance3D:
			var mesh := (node as MeshInstance3D).mesh
			_write_mesh(absolute, "%s__%s" % [assembly_name, _clean_name(node.name)], mesh)
		for child in node.get_children():
			stack.append(child)
	root.free()


func _clean_name(node_name: String) -> String:
	return node_name.to_lower().replace(" ", "_").replace("@", "")


# --- Запись -------------------------------------------------------------------

func _write_mesh(absolute: String, file_name: String, mesh: Mesh) -> void:
	if mesh == null or mesh.get_surface_count() == 0:
		_skipped += 1
		return
	var path := "%s/%s.obj" % [absolute, file_name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Не удалось открыть на запись %s" % path)
		return
	file.store_line("# Mydriasis — процедурная геометрия, выгрузка для правки формы.")
	file.store_line("# Материалы остаются процедурными: этот файл — болванка.")
	var triangles := 0
	for surface in range(0, mesh.get_surface_count()):
		triangles += _write_surface(file, mesh, surface)
	file.close()
	_written += 1
	print("  %s — треугольников: %d" % [file_name, triangles])


func _write_surface(file: FileAccess, mesh: Mesh, surface: int) -> int:
	var arrays := mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.is_empty():
		return 0
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	file.store_line("o surface_%d" % surface)
	for vertex in vertices:
		file.store_line("v %.5f %.5f %.5f" % [vertex.x, vertex.y, vertex.z])
	if uvs.size() == vertices.size():
		for uv in uvs:
			# Blender читает V снизу вверх — переворачиваем, чтобы текстуры не вставали кверху ногами.
			file.store_line("vt %.5f %.5f" % [uv.x, 1.0 - uv.y])
	if normals.size() == vertices.size():
		for normal in normals:
			file.store_line("vn %.5f %.5f %.5f" % [normal.x, normal.y, normal.z])

	var has_uv := uvs.size() == vertices.size()
	var has_normal := normals.size() == vertices.size()
	var triangle_count := 0
	if indices.is_empty():
		var i := 0
		while i + 2 < vertices.size():
			_write_face(file, i, i + 1, i + 2, has_uv, has_normal)
			triangle_count += 1
			i += 3
	else:
		var i := 0
		while i + 2 < indices.size():
			_write_face(file, indices[i], indices[i + 1], indices[i + 2], has_uv, has_normal)
			triangle_count += 1
			i += 3
	return triangle_count


func _write_face(file: FileAccess, a: int, b: int, c: int, has_uv: bool, has_normal: bool) -> void:
	var ai := a + 1
	var bi := b + 1
	var ci := c + 1
	if has_uv and has_normal:
		file.store_line("f %d/%d/%d %d/%d/%d %d/%d/%d" % [ai, ai, ai, bi, bi, bi, ci, ci, ci])
	elif has_normal:
		file.store_line("f %d//%d %d//%d %d//%d" % [ai, ai, bi, bi, ci, ci])
	else:
		file.store_line("f %d %d %d" % [ai, bi, ci])
