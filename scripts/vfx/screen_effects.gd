class_name ScreenEffects
extends Node
## Экранные эффекты кадра: финальный грейд и «вуаль» расстроенного восприятия.
##
## Это не украшение, а шкала: post_grade показывает, насколько расширен зрачок,
## насколько упало давление и бьётся ли сердце; veil показывает, насколько
## герой ещё понимает, что видит.
##
## Слои:
##   80 — post_grade (грейд, зрачок, давление, зерно, гало)
##   81 — veil (двоение, туннель, помехи, распад)
##   HUD живёт выше и не обесцвечивается.

const LAYER_GRADE := 80
const LAYER_VEIL := 81

var grade: ShaderMaterial
var veil: ShaderMaterial

var _flash := 0.0
var _flash_decay := 3.0
var _extra_pupil := 0.0
var _drift := 0.0
var _time := 0.0
var _tone_lock := 0.0


func _ready() -> void:
	grade = ShaderLibrary.fullscreen_layer(self, &"post_grade", LAYER_GRADE)
	veil = ShaderLibrary.fullscreen_layer(self, &"veil", LAYER_VEIL, {
		"dread": 0.0, "doubling": 0.0, "tunnel": 0.0, "static_amount": 0.0,
		"rings": 0.0, "desaturate": 0.0,
	})


func _process(delta: float) -> void:
	_time += delta
	_drift = lerpf(_drift, 0.0, minf(delta * 1.2, 1.0))

	var dread := GameState.dread
	var pressure := GameState.pressure_level()
	var pupil := clampf(GameState.pupil_size() + _extra_pupil, 0.0, 1.0)
	var beat := GameState.heartbeat_envelope()
	var pulse := clampf((GameState.heart_rate - 70.0) / 110.0, 0.0, 1.0)

	# --- Грейд ---
	ShaderLibrary.set_uniform(grade, &"pupil", pupil)
	ShaderLibrary.set_uniform(grade, &"pressure", pressure * 0.85 + _drift * 0.3)
	ShaderLibrary.set_uniform(grade, &"heartbeat", beat * mixed_pulse(pulse))
	ShaderLibrary.set_uniform(grade, &"exposure", lerpf(1.0, 0.82, pressure * 0.5 + dread * 0.18))
	ShaderLibrary.set_uniform(grade, &"saturation", lerpf(0.86, 0.62, dread))
	ShaderLibrary.set_uniform(grade, &"vignette", lerpf(0.55, 1.05, dread))
	ShaderLibrary.set_uniform(grade, &"chromatic", lerpf(0.3, 0.85, dread) * (1.0 + pressure))
	ShaderLibrary.set_uniform(grade, &"glow", lerpf(0.5, 0.95, pupil))
	ShaderLibrary.set_uniform(grade, &"temperature", lerpf(-0.10, -0.28, dread))
	ShaderLibrary.set_uniform(grade, &"pupil_bloom", clampf(pupil - 0.72, 0.0, 1.0) * 0.9)
	ShaderLibrary.set_uniform(grade, &"pupil_irregularity",
		0.0 if Quality.comfort_value("no_pupil_distortion") else lerpf(0.0, 0.9, maxf(dread, 1.0 - GameState.consciousness)))
	ShaderLibrary.set_uniform(grade, &"lens_dirt", 0.2 + dread * 0.3)

	if _flash > 0.0001:
		_flash = maxf(0.0, _flash - delta * _flash_decay)
		ShaderLibrary.set_uniform(grade, &"flash", 0.0 if Quality.comfort_value("no_flash") else _flash)

	# --- Вуаль ---
	ShaderLibrary.set_uniform(veil, &"dread", clampf((dread - 0.35) / 0.65, 0.0, 1.0))
	ShaderLibrary.set_uniform(veil, &"doubling",
		clampf((1.0 - GameState.consciousness - 0.2) * 1.4 + (1.0 - GameState.spo2 / 100.0) * 0.6, 0.0, 1.0))
	ShaderLibrary.set_uniform(veil, &"tunnel", clampf(pressure * 0.6 + (1.0 - GameState.consciousness) * 0.7, 0.0, 1.0))
	ShaderLibrary.set_uniform(veil, &"static_amount", clampf((GameState.heart_rate - 130.0) / 90.0, 0.0, 0.5))
	ShaderLibrary.set_uniform(veil, &"rings", beat * pulse * 0.8)
	ShaderLibrary.set_uniform(veil, &"desaturate", clampf(dread * 0.8, 0.0, 1.0))
	ShaderLibrary.set_uniform(veil, &"breath", GameState.breath_signed())
	ShaderLibrary.set_uniform(veil, &"flash", _flash * 0.6)

	# Аудио-напряжение идёт следом за картинкой: картинка и звук — одно целое.
	AudioDirector.set_tension(clampf(dread * 0.8 + (1.0 - GameState.consciousness) * 0.5, 0.0, 1.0))


## Пульс, пришедшийся на удар, бьёт по кадру сильнее — но только на высоком пульсе.
func mixed_pulse(pulse: float) -> float:
	return clampf(0.25 + pulse * 0.9, 0.0, 1.0)


## Вспышка: удар, разряд, склейка перехода, «белый шум» перед обмороком.
func flash(amount := 1.0, decay := 3.0) -> void:
	if Quality.comfort_value("no_flash"):
		amount *= 0.25
	_flash = maxf(_flash, amount)
	_flash_decay = decay


## Временное расширение зрачка — ввод в транс, шок, потеря сознания.
func push_pupil(amount := 0.4, duration := 1.2) -> void:
	_extra_pupil = clampf(_extra_pupil + amount, -0.3, 1.0)
	var tween := create_tween()
	tween.tween_method(func(value: float) -> void: _extra_pupil = value, _extra_pupil, 0.0, duration)


## «Поехало»: короткий приступ дезориентации, кадр плывёт.
func drift(amount := 0.5, duration := 0.8) -> void:
	_drift = clampf(amount, 0.0, 1.0)
	var tween := create_tween()
	tween.tween_method(func(value: float) -> void: _drift = value, _drift, 0.0, duration)


func set_tone_lock(value: float) -> void:
	_tone_lock = value
