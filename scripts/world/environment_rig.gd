class_name EnvironmentRig
extends WorldEnvironment
## Окружение блока. Настраивается кодом, чтобы уровень-блокинг не зависел от
## .tres-файлов, и умеет перестраиваться под уровень качества.
##
## Свет в игре — часть языка: он не «красивый», он патологический. Холодные
## лампы дневного света, зелёный оттенок мониторов, туман, который стоит в
## воздухе морга, и почти чёрные провалы между ракурсами.

enum Mood { MORGUE_NIGHT, CORRIDOR_EMERGENCY, PROCEDURE_ROOM, DEAD_ROOM }

var mood: Mood = Mood.MORGUE_NIGHT


func _ready() -> void:
	add_to_group(&"world_environment")
	build(mood)


func set_mood(value: Mood) -> void:
	mood = value
	build(value)


func build(value: Mood) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.92
	env.tonemap_white = 4.0

	match value:
		Mood.MORGUE_NIGHT:
			env.background_color = Color(0.012, 0.016, 0.019)
			env.ambient_light_color = Color(0.34, 0.44, 0.55)
			env.ambient_light_energy = 0.22
			env.fog_light_color = Color(0.30, 0.40, 0.48)
			env.fog_density = 0.012
		Mood.CORRIDOR_EMERGENCY:
			env.background_color = Color(0.016, 0.014, 0.012)
			env.ambient_light_color = Color(0.46, 0.36, 0.28)
			env.ambient_light_energy = 0.26
			env.fog_light_color = Color(0.38, 0.30, 0.22)
			env.fog_density = 0.02
		Mood.PROCEDURE_ROOM:
			env.background_color = Color(0.010, 0.013, 0.016)
			env.ambient_light_color = Color(0.52, 0.58, 0.62)
			env.ambient_light_energy = 0.30
			env.fog_light_color = Color(0.42, 0.48, 0.52)
			env.fog_density = 0.009
		Mood.DEAD_ROOM:
			env.background_color = Color(0.004, 0.005, 0.006)
			env.ambient_light_color = Color(0.18, 0.24, 0.30)
			env.ambient_light_energy = 0.12
			env.fog_light_color = Color(0.16, 0.22, 0.28)
			env.fog_density = 0.03

	env.fog_enabled = true
	env.fog_aerial_perspective = 0.35

	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_strength = 1.05
	env.glow_bloom = 0.22
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 0.92
	env.glow_hdr_scale = 2.0

	env.ssao_enabled = true
	env.ssao_radius = 0.9
	env.ssao_intensity = 2.1
	env.ssao_power = 1.6
	env.ssao_detail = 0.6

	env.ssil_enabled = true
	env.ssil_radius = 1.8
	env.ssil_intensity = 0.9

	env.sdfgi_enabled = false
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.12

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.014
	env.volumetric_fog_albedo = Color(0.72, 0.80, 0.86)
	env.volumetric_fog_emission = Color(0.04, 0.06, 0.07)
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_detail_spread = 2.0

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.92
	env.adjustment_brightness = 1.0

	environment = env
	apply_quality_profile(Quality.profile())


## Вызывается автоматически из Quality при смене уровня качества.
func apply_quality_profile(profile: Dictionary) -> void:
	if environment == null:
		return
	environment.ssao_enabled = bool(profile.get("ssao", true))
	environment.ssil_enabled = bool(profile.get("ssil", false)) and environment.ssao_enabled
	environment.sdfgi_enabled = bool(profile.get("sdfgi", false))
	environment.glow_enabled = bool(profile.get("glow", true))
	environment.volumetric_fog_enabled = bool(profile.get("volumetric_fog", true))
	if not environment.volumetric_fog_enabled:
		environment.fog_enabled = true
	# Плотность тумана — единственное, что меняется «на глаз» между уровнями.
	var density_scale := lerpf(1.6, 1.0, float(profile.get("procedural_density", 1.0)))
	environment.volumetric_fog_density = 0.014 * density_scale
