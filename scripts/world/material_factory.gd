class_name MaterialFactory
extends RefCounted
## Фабрика материалов уровня. Материалы кэшируются: один материал на весь блок,
## иначе каждая стена тянула бы свой экземпляр шейдера и ломала батчинг.
##
## В проекте нет ни одной картинки-текстуры. Всё, что видно, — процедурная
## поверхность: кафель, краска, металл, стекло, ткань, пластик.

static var _cache: Dictionary = {}


static func _get(key: StringName, id: StringName, params: Dictionary, priority := 0) -> ShaderMaterial:
	if _cache.has(key):
		var cached = _cache[key]
		if cached != null:
			return cached
	var mat := ShaderLibrary.material(id, params, priority)
	_cache[key] = mat
	return mat


static func reset() -> void:
	_cache.clear()


## Мокрый кафель палат: холодный, скользкий, с грязью в швах.
static func tile_floor() -> ShaderMaterial:
	return _get(&"tile_floor", &"wet_tile", {
		"uv_scale": Vector2(3.4, 3.4),
		"grout_width": 0.028,
		"grout_dirt": 0.78,
		"wetness": 0.7,
		"puddle": 0.5,
		"stain": 0.55,
		"tile_color": Color(0.70, 0.73, 0.72),
		"tile_color_alt": Color(0.54, 0.58, 0.58),
		"glaze": 0.9,
	})


## Кафель на стене: тот же шейдер, другой масштаб и меньше воды.
static func tile_wall() -> ShaderMaterial:
	return _get(&"tile_wall", &"wet_tile", {
		"uv_scale": Vector2(3.2, 3.2),
		"grout_width": 0.03,
		"grout_dirt": 0.6,
		"wetness": 0.35,
		"puddle": 0.1,
		"flow": 0.5,
		"stain": 0.7,
		"tile_color": Color(0.66, 0.70, 0.70),
		"tile_color_alt": Color(0.50, 0.55, 0.56),
		"glaze": 0.75,
	})


## Крашеная стена над кафелем — «масляная краска» больничного коридора.
static func painted_wall() -> ShaderMaterial:
	return _get(&"painted_wall", &"wet_tile", {
		"uv_scale": Vector2(0.8, 0.8),
		"tile_size": Vector2(1.4, 1.4),
		"grout_width": 0.008,
		"grout_dirt": 0.25,
		"wetness": 0.16,
		"puddle": 0.0,
		"glaze": 0.55,
		"stain": 0.75,
		"stain_color": Color(0.30, 0.28, 0.24),
		"tile_color": Color(0.52, 0.55, 0.50),
		"tile_color_alt": Color(0.47, 0.50, 0.47),
	})


static func concrete() -> ShaderMaterial:
	return _get(&"concrete", &"wet_tile", {
		"uv_scale": Vector2(0.6, 0.6),
		"tile_size": Vector2(2.0, 2.0),
		"grout_width": 0.004,
		"grout_dirt": 0.2,
		"wetness": 0.05,
		"glaze": 0.05,
		"stain": 0.6,
		"tile_color": Color(0.38, 0.39, 0.38),
		"tile_color_alt": Color(0.32, 0.33, 0.33),
	})


## Шлифованный металл: рамы каталок, поручни, штативы.
static func metal() -> ShaderMaterial:
	return _get(&"metal", &"hands_reveal", {
		"skin_tone": Color(0.58, 0.60, 0.63),
		"skin_deep": Color(0.30, 0.31, 0.33),
		"dirt_amount": 0.42,
		"pore_amount": 0.18,
		"wetness": 0.12,
		"detail_scale": 110.0,
		"rim_strength": 1.25,
		"rim_color": Color(0.72, 0.82, 1.0),
	})


## Крашеный металл корпусов: мониторы, тумбы, двери.
static func painted_metal() -> ShaderMaterial:
	return _get(&"painted_metal", &"hands_reveal", {
		"skin_tone": Color(0.44, 0.47, 0.47),
		"skin_deep": Color(0.26, 0.28, 0.28),
		"dirt_amount": 0.5,
		"pore_amount": 0.3,
		"wetness": 0.18,
		"detail_scale": 60.0,
		"rim_strength": 0.6,
	})


## Медицинский пластик: корпуса, лотки, вёдра, ручки.
static func plastic() -> ShaderMaterial:
	return _get(&"plastic", &"hands_reveal", {
		"skin_tone": Color(0.76, 0.78, 0.74),
		"skin_deep": Color(0.62, 0.65, 0.62),
		"dirt_amount": 0.35,
		"pore_amount": 0.05,
		"wetness": 0.3,
		"detail_scale": 200.0,
		"rim_strength": 0.5,
		"rim_color": Color(0.8, 0.9, 1.0),
	})


## Резина: колёса каталок, уплотнители дверей, коврики.
static func rubber() -> ShaderMaterial:
	return _get(&"rubber", &"hands_reveal", {
		"skin_tone": Color(0.16, 0.16, 0.17),
		"skin_deep": Color(0.08, 0.08, 0.09),
		"dirt_amount": 0.5,
		"pore_amount": 0.55,
		"wetness": 0.1,
		"detail_scale": 150.0,
		"rim_strength": 0.35,
	})


## Медицинская ткань: простыни, халаты, занавеси, марля, ремни.
static func fabric(tint := Color(0.78, 0.79, 0.76)) -> ShaderMaterial:
	var key := StringName("fabric_%s" % tint.to_html(false))
	return _get(key, &"fabric_gauze", {
		"uv_scale": Vector2(6.0, 6.0),
		"thread_density": 210.0,
		"base_color": tint,
		"shadow_color": tint.darkened(0.35),
		"stain_amount": 0.35,
		"soak": 0.3,
	})


## Полупрозрачная занавесь вокруг койки.
static func curtain() -> ShaderMaterial:
	return _get(&"curtain", &"fabric_gauze", {
		"uv_scale": Vector2(4.0, 4.0),
		"thread_density": 140.0,
		"base_color": Color(0.66, 0.72, 0.70),
		"shadow_color": Color(0.34, 0.40, 0.40),
		"transparency": 0.55,
		"stain_amount": 0.4,
		"soak": 0.2,
		"fuzz": 0.8,
	}, 1)


static func glass() -> ShaderMaterial:
	return _get(&"glass", &"glass_dirt", {
		"refraction": 0.55,
		"grime": 0.65,
		"fingerprints": 0.6,
		"runs": 0.5,
		"frost": 0.15,
	}, 1)


static func frosted_glass() -> ShaderMaterial:
	return _get(&"frosted_glass", &"glass_dirt", {
		"refraction": 0.8,
		"grime": 0.4,
		"fingerprints": 0.35,
		"runs": 0.35,
		"frost": 0.9,
		"tint": Color(0.7, 0.76, 0.78),
		"tint_density": 0.4,
	}, 1)


## Экран монитора: параметры кардиограммы задаются на месте вызова.
static func crt(bpm := 68.0, trace := Color(0.35, 1.0, 0.62), flatline := 0.0) -> ShaderMaterial:
	var key := StringName("crt_%d_%d" % [int(bpm), int(flatline * 100.0)])
	return _get(key, &"monitor_crt", {
		"bpm": bpm,
		"trace_color": trace,
		"flatline": flatline,
		"glow": 1.5,
	})


## Светящаяся наклейка/табличка. Цвет — единственный источник смысла.
static func sign_plate(color := Color(0.85, 0.80, 0.35)) -> StandardMaterial3D:
	var key := StringName("sign_%s" % color.to_html(false))
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.35
	mat.roughness = 0.7
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = mat
	return mat


static func emissive(color: Color, energy := 3.0) -> StandardMaterial3D:
	var key := StringName("emit_%s_%d" % [color.to_html(false), int(energy * 10.0)])
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cache[key] = mat
	return mat
