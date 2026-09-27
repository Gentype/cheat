class_name ShaderLibrary
extends RefCounted
## Реестр шейдеров проекта.
##
## Зачем отдельный реестр, а не .tres-материалы:
##  1. Материалы должны создаваться кодом, чтобы уровни-блокинги собирались из
##     данных, а не из вручную расставленных нод.
##  2. Смена уровня качества должна мгновенно перекраивать параметры уже
##     существующих материалов (число выборок блюра и т.д.).
##  3. Неизвестный юниформ не должен валить игру — set_uniform молча пропускает
##     то, чего нет в шейдере (страховка при правках шейдеров на ходу).

const SHADER_DIR := "res://shaders/"

## Все шейдеры проекта. Правки здесь — единственная точка входа.
const CATALOG := {
	&"body_hole": "body_hole.gdshader",
	&"hands_reveal": "hands_reveal.gdshader",
	&"mask_visor": "mask_visor.gdshader",
	&"wet_tile": "wet_tile.gdshader",
	&"glass_dirt": "glass_dirt.gdshader",
	&"fabric_gauze": "fabric_gauze.gdshader",
	&"monitor_crt": "monitor_crt.gdshader",
	&"post_grade": "post_grade.gdshader",
	&"veil": "veil.gdshader",
}

## Кэш загруженных Shader.
static var _shaders: Dictionary = {}
## Материалы, созданные библиотекой: нужны для переоценки при смене качества.
static var _live: Array = []
## Кэш имён юниформов: shader_id -> Array[StringName].
static var _uniform_names: Dictionary = {}


static func shader(id: StringName) -> Shader:
	if _shaders.has(id):
		return _shaders[id]
	if not CATALOG.has(id):
		push_error("ShaderLibrary: неизвестный шейдер " + String(id))
		return null
	var path: String = SHADER_DIR + String(CATALOG[id])
	var resource := load(path)
	if resource is Shader:
		_shaders[id] = resource
		return resource
	push_error("ShaderLibrary: не удалось загрузить " + path)
	return null


## Создаёт материал. params — словарь начальных значений юниформов.
static func material(id: StringName, params: Dictionary = {}, priority := 0) -> ShaderMaterial:
	var sh := shader(id)
	if sh == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_meta(&"shader_id", id)
	if priority != 0:
		mat.render_priority = priority
	for key in params.keys():
		set_uniform(mat, key, params[key])
	_apply_quality_defaults(mat, id)
	_live.append(weakref(mat))
	return mat


## Устанавливает юниформ, только если он существует в шейдере.
static func set_uniform(mat: ShaderMaterial, name: Variant, value: Variant) -> void:
	if mat == null:
		return
	var id: StringName = mat.get_meta(&"shader_id", &"")
	var native_name := StringName(name)
	if _uniform_names.has(id):
		if not (_uniform_names[id] as Array).has(native_name):
			return
	else:
		var names: Array = []
		if mat.shader != null:
			for entry in mat.shader.get_shader_uniform_list(true):
				names.append(StringName(entry.get("name", "")))
		_uniform_names[id] = names
		if not names.has(native_name):
			return
	mat.set_shader_parameter(String(native_name), value)


## Переоценка всех живых материалов: вызывает Quality при смене уровня.
static func refresh_all() -> void:
	var alive: Array = []
	for entry in _live:
		var mat: ShaderMaterial = entry.get_ref() if entry is WeakRef else null
		if mat == null:
			continue
		alive.append(weakref(mat))
		_apply_quality_defaults(mat, mat.get_meta(&"shader_id", &""))
	_live = alive


## Настройки, которые диктует уровень качества и режим комфорта.
static func _apply_quality_defaults(mat: ShaderMaterial, id: StringName) -> void:
	match id:
		&"body_hole":
			set_uniform(mat, &"blur_samples", Quality.blur_samples())
			set_uniform(mat, &"living", 0.10 if Quality.comfort_value("reduce_shake") else 0.25)
		&"hands_reveal":
			set_uniform(mat, &"detail_scale", lerpf(24.0, 42.0, Quality.density()))
		&"mask_visor":
			set_uniform(mat, &"scratches", 0.12 if Quality.density() < 0.6 else 0.30)
		&"post_grade":
			set_uniform(mat, &"grain", 0.0 if Quality.comfort_value("reduce_grain") else 0.35)
			if Quality.comfort_value("no_pupil_distortion"):
				set_uniform(mat, &"pupil_irregularity", 0.0)
			if Quality.comfort_value("no_flash"):
				set_uniform(mat, &"flash", 0.0)
		&"wet_tile":
			if Quality.density() < 0.6:
				set_uniform(mat, &"grout_dirt", 0.5)
		_:
			pass


## Полноэкранный слой: CanvasLayer + ColorRect, читающий уже собранный кадр.
## post_grade и veil живут именно так — поверх 3D, под HUD.
static func fullscreen_layer(host: Node, id: StringName, layer: int, params: Dictionary = {}) -> ShaderMaterial:
	var canvas := CanvasLayer.new()
	canvas.name = "FX_" + String(id)
	canvas.layer = layer
	host.add_child(canvas)
	var rect := ColorRect.new()
	rect.name = "Quad"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color(1, 1, 1, 1)
	var mat := material(id, params)
	rect.material = mat
	canvas.add_child(rect)
	return mat
