extends Control
## Заставка студии. По дизайн-документу: чёрный экран, глухой звук накачивающейся
## манжеты тонометра, одиночный резкий пик кардиомонитора и судорожное сжатие
## пальцев на глазу — со звуком влажного хруста. Затем переход в меню.
##
## Всё, что здесь есть, синтезировано процедурно: звук — AudioDirector,
## изображение — сгенерированный знак студии из art/branding.

const NEXT_SCENE := "res://scenes/ui/main_menu.tscn"

var logo: Control
var caption: Label
var _squeeze := 1.0
var _stage := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0, 0, 0)
	add_child(background)

	logo = UITheme.make_logo("res://art/branding/logo.png", 210.0)
	logo.set_anchors_preset(Control.PRESET_CENTER)
	logo.position = Vector2(-168, -105)
	logo.modulate.a = 0.0
	add_child(logo)

	caption = UITheme.make_label("", 15)
	caption.set_anchors_preset(Control.PRESET_CENTER)
	caption.position = Vector2(-200, 130)
	caption.custom_minimum_size = Vector2(400, 20)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color", UITheme.COLOR_DIM)
	add_child(caption)

	var hint := UITheme.make_label("ЛЮБАЯ КЛАВИША — ПРОПУСТИТЬ", 13)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.position = Vector2(-260, -46)
	hint.add_theme_color_override("font_color", Color(0.32, 0.36, 0.38))
	add_child(hint)

	_run_sequence()


func _run_sequence() -> void:
	# 1. Тишина и темнота. Манжета начинает накачиваться.
	await get_tree().create_timer(0.5).timeout
	AudioDirector.play(&"cuff_pump", -8.0, 1.0, AudioDirector.BUS_BODY)
	caption.text = "СИСТОЛИЧЕСКОЕ ДАВЛЕНИЕ — 0"
	await get_tree().create_timer(1.6).timeout
	caption.text = "СИСТОЛИЧЕСКОЕ ДАВЛЕНИЕ — 40"
	await get_tree().create_timer(1.6).timeout
	caption.text = "СИСТОЛИЧЕСКОЕ ДАВЛЕНИЕ — 90"
	# 2. Одиночный резкий пик кардиомонитора — и знак проявляется.
	await get_tree().create_timer(1.2).timeout
	_stage = 1
	AudioDirector.play(&"monitor_beep", -4.0, 1.0, AudioDirector.BUS_SFX)
	caption.text = "MYDRIASIS · ВНУТРЕННЯЯ СБОРКА"
	var tween := create_tween()
	tween.tween_property(logo, "modulate:a", 1.0, 0.5)
	# 3. Судорожное сжатие пальцев на склере глаза: влажный хруст.
	await get_tree().create_timer(1.0).timeout
	_stage = 2
	AudioDirector.play(&"wet_crunch", -10.0, 1.0, AudioDirector.BUS_BODY)
	var squeeze := create_tween()
	squeeze.tween_method(_set_squeeze, 1.0, 0.94, 0.18)
	squeeze.tween_method(_set_squeeze, 0.94, 1.0, 0.9)
	await get_tree().create_timer(2.2).timeout
	await _leave()


func _set_squeeze(value: float) -> void:
	_squeeze = value
	logo.scale = Vector2.ONE * value


func _leave() -> void:
	if _stage >= 3:
		return
	_stage = 3
	AudioDirector.play(&"ui_press", -18.0, 1.0, AudioDirector.BUS_SFX)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.1)
	await tween.finished
	SceneRouter.swap_scene(NEXT_SCENE)
	await get_tree().process_frame
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if _stage >= 3:
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		_leave()
