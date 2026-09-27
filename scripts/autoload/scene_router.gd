extends Node
## SceneRouter — переходы между сценами с кинематографической шторкой.
##
## Шторка всегда одна и та же: короткое затемнение, вспышка кардиомонитора,
## тишина. Это часть языка игры, поэтому она живёт в роутере, а не в меню.

signal transition_started(to: String)
signal transition_finished(to: String)
signal scene_ready(to: String)

const MENU := "res://scenes/ui/main_menu.tscn"

var current_scene_path := ""
var transitioning := false

var _layer: CanvasLayer
var _fade: ColorRect
var _label: Label
var _busy_guard := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "TransitionLayer"
	_layer.layer = 200
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)

	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_fade)

	_label = Label.new()
	_label.name = "Caption"
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.80, 0.0))
	_label.add_theme_font_size_override("font_size", 15)
	_label.modulate.a = 0.0
	_layer.add_child(_label)


## Переход к сцене. caption — строка на чёрном (имя бита, время, диагноз).
func goto(path: String, caption := "", fade_time := 0.65, hold := 0.35) -> void:
	if _busy_guard:
		return
	_busy_guard = true
	transitioning = true
	transition_started.emit(path)
	GameState.game_paused = true

	_label.text = caption
	_label.set_anchors_preset(Control.PRESET_CENTER)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_fade, "color:a", 1.0, fade_time).set_ease(Tween.EASE_IN_OUT)
	if caption != "":
		tween.parallel().tween_property(_label, "modulate:a", 0.85, fade_time * 0.9)
	await tween.finished

	if hold > 0.0:
		await get_tree().create_timer(hold, true, false, true).timeout

	_swap_scene(path)
	GameState.game_paused = false

	var out := create_tween()
	out.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	out.tween_property(_fade, "color:a", 0.0, fade_time * 1.25).set_ease(Tween.EASE_IN_OUT)
	out.parallel().tween_property(_label, "modulate:a", 0.0, fade_time * 0.6)
	await out.finished
	transitioning = false
	_busy_guard = false
	transition_finished.emit(path)


## Немедленная подмена сцены (без шторки) — для инструментов и загрузки меню.
func swap_scene(path: String) -> void:
	_swap_scene(path)


func _swap_scene(path: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	# Ждём кадр, чтобы текущая сцена успела отдать ресурсы (важно на слабых ПК).
	tree.call_deferred("change_scene_to_file", path)
	current_scene_path = path
	await tree.process_frame
	await tree.process_frame
	scene_ready.emit(path)


func reload_current() -> void:
	if current_scene_path != "":
		goto(current_scene_path, "ПЕРЕЗАПУСК", 0.25, 0.1)


func goto_menu(caption := "") -> void:
	goto(MENU, caption, 0.7, 0.2)


func quit() -> void:
	# goto — корутина: ждём именно её, иначе выход случится до конца шторки.
	await goto(MENU, "СМЕНА ЗАВЕРШЕНА", 0.7, 0.2)
	get_tree().quit()
