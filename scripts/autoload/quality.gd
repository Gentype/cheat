extends Node
## Quality — профилировщик графики и автоматический сторож производительности.
##
## Уровни: НИЗКОЕ / СРЕДНЕЕ / ВЫСОКОЕ / ВЫСШЕЕ. По умолчанию стоит «ВЫСШЕЕ»:
## проект рассчитан на то, что камеры, шейдеры и материалы работают на полную.
## Если кадры проседают — сторож плавно опускает масштаб рендера, не трогая
## художественные настройки (никогда не выключает эффекты, отвечающие за смысл).

signal changed(tier: int)

enum Tier { LOW, MEDIUM, HIGH, ULTRA }

const TIER_NAMES := {
	Tier.LOW: "НИЗКОЕ",
	Tier.MEDIUM: "СРЕДНЕЕ",
	Tier.HIGH: "ВЫСОКОЕ",
	Tier.ULTRA: "ВЫСШЕЕ",
}

## Профили: всё, что отличает уровни. blur_samples — число выборок в диске
## рассеяния тела, detail — общая плотность процедурных деталей в шейдерах.
const PROFILES := {
	Tier.LOW: {
		"blur_samples": 8,
		"render_scale": 0.75,
		"msaa": Viewport.MSAA_DISABLED,
		"screen_space_aa": false,
		"taa": false,
		"ssao": false,
		"ssil": false,
		"sdfgi": false,
		"glow": true,
		"volumetric_fog": false,
		"shadow_quality": RenderingServer.SHADOW_QUALITY_HARD,
		"shadow_softness": false,
		"directional_shadows": true,
		"procedural_density": 0.5,
	},
	Tier.MEDIUM: {
		"blur_samples": 16,
		"render_scale": 0.9,
		"msaa": Viewport.MSAA_2X,
		"screen_space_aa": false,
		"taa": false,
		"ssao": true,
		"ssil": false,
		"sdfgi": false,
		"glow": true,
		"volumetric_fog": false,
		"shadow_quality": RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		"shadow_softness": true,
		"directional_shadows": true,
		"procedural_density": 0.75,
	},
	Tier.HIGH: {
		"blur_samples": 24,
		"render_scale": 1.0,
		"msaa": Viewport.MSAA_4X,
		"screen_space_aa": false,
		"taa": false,
		"ssao": true,
		"ssil": true,
		"sdfgi": false,
		"glow": true,
		"volumetric_fog": true,
		"shadow_quality": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
		"shadow_softness": true,
		"directional_shadows": true,
		"procedural_density": 1.0,
	},
	Tier.ULTRA: {
		"blur_samples": 32,
		"render_scale": 1.0,
		"msaa": Viewport.MSAA_4X,
		"screen_space_aa": false,
		"taa": true,
		"ssao": true,
		"ssil": true,
		"sdfgi": true,
		"glow": true,
		"volumetric_fog": true,
		"shadow_quality": RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		"shadow_softness": true,
		"directional_shadows": true,
		"procedural_density": 1.0,
	},
}

## «ВЫСШЕЕ» по умолчанию — как требует арт-директива проекта.
var tier: Tier = Tier.ULTRA
## Сторож производительности: держит кадровую частоту, опуская масштаб рендера.
var auto_guard := true
var target_fps := 60
var render_scale := 1.0
## Комфортные настройки доступности (не понижают качество, а убирают эффекты,
## которые могут навредить: зерно, дрожание зрачка, вспышки).
var comfort := {
	"reduce_grain": false,
	"reduce_shake": false,
	"no_flash": false,
	"no_pupil_distortion": false,
}

var _frame_accumulator := 0.0
var _frame_count := 0
var _average_frame := 1.0 / 60.0
var _guard_cooldown := 0.0
var _applied_once := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	apply()


func _process(delta: float) -> void:
	if not auto_guard:
		return
	_frame_accumulator += delta
	_frame_count += 1
	if _frame_accumulator < 1.0:
		return
	var average := _frame_accumulator / float(maxi(_frame_count, 1))
	_average_frame = lerpf(_average_frame, average, 0.5)
	_frame_accumulator = 0.0
	_frame_count = 0

	_guard_cooldown -= 1.0
	if _guard_cooldown > 0.0:
		return
	var target := 1.0 / float(target_fps)
	if _average_frame > target * 1.22 and render_scale > 0.55:
		set_render_scale(render_scale - 0.05)
		_guard_cooldown = 3.0
	elif _average_frame < target * 0.86 and render_scale < 1.0:
		set_render_scale(render_scale + 0.05)
		_guard_cooldown = 8.0


func profile() -> Dictionary:
	return PROFILES[tier]


func density() -> float:
	return float(PROFILES[tier]["procedural_density"])


func blur_samples() -> int:
	return int(PROFILES[tier]["blur_samples"])


func set_tier(value: Tier, save := true) -> void:
	tier = value
	_applied_once = false
	apply()
	if save:
		SaveSystem.set_setting("video/tier", int(value))


func set_render_scale(value: float) -> void:
	render_scale = clampf(value, 0.5, 1.0)
	_apply_viewport()


func apply() -> void:
	var p := profile()
	var viewport := get_viewport()
	if viewport == null:
		return
	render_scale = float(p["render_scale"])
	_apply_viewport()

	RenderingServer.directional_soft_shadow_filter_set_quality(int(p["shadow_quality"]))
	RenderingServer.positional_soft_shadow_filter_set_quality(int(p["shadow_quality"]))
	RenderingServer.viewport_set_positional_shadow_atlas_size(viewport.get_viewport_rid(), _atlas_size())
	Engine.max_fps = 0

	# Настройки окружений подхватывают все уровни через группу.
	for node in get_tree().get_nodes_in_group(&"world_environment"):
		if node.has_method(&"apply_quality_profile"):
			node.call(&"apply_quality_profile", p)

	ShaderLibrary.refresh_all()
	_applied_once = true
	changed.emit(tier)


func _apply_viewport() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var p := profile()
	viewport.scaling_3d_scale = render_scale
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.msaa_3d = p["msaa"]
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if p["screen_space_aa"] else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = bool(p["taa"])
	viewport.positional_shadow_atlas_size = _atlas_size()
	# В 4.3 у Viewport есть только степени деления 1 / 4 / 16 / 64 …: «двойки» нет.
	viewport.shadow_atlas_quad_0 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4
	viewport.shadow_atlas_quad_1 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4
	viewport.shadow_atlas_quad_2 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_1
	viewport.shadow_atlas_quad_3 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_1


func _atlas_size() -> int:
	match tier:
		Tier.LOW:
			return 1024
		Tier.MEDIUM:
			return 2048
		Tier.HIGH:
			return 4096
		_:
			return 8192


func describe() -> String:
	var p := profile()
	return "%s · выборок блюра %d · масштаб %d%% · MSAA ×%d" % [
		TIER_NAMES[tier],
		int(p["blur_samples"]),
		int(render_scale * 100.0),
		int(p["msaa"]),
	]


## Комфорт: отключает то, что может физически навредить игроку,
## но никогда — то, что несёт смысл (зрачок, давление, дыхание).
func comfort_value(key: String) -> bool:
	return bool(comfort.get(key, false))


func set_comfort(key: String, value: bool) -> void:
	if not comfort.has(key):
		return
	comfort[key] = value
	SaveSystem.set_setting("comfort/" + key, value)
	ShaderLibrary.refresh_all()
