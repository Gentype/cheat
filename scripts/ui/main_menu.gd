extends Control
## Главное меню.
##
## Тут можно позволить себе арт: меню — единственное место, где проект
## показывает изображения (сгенерированный знак студии и фон). В игровом
## кадре генерации нет: там всё процедурное.

const LEVEL_SCENE := "res://scenes/game/ward_night.tscn"
const SETTINGS_SCENE := "res://scenes/ui/settings_menu.tscn"

var _menu_root: VBoxContainer
var _settings: Control
var _ecg_phase := 0.0
var _ecg: Control
var _log: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UITheme.make_background("res://art/menu/background_menu.png"))

	_build_title()
	_build_menu()
	_build_footer()
	_build_ecg_strip()

	# Звук меню: палата вдалеке, редкая капель, сердце на 58.
	AudioDirector.start_loop(&"ward_amb", AudioDirector.BUS_BED, -26.0)
	AudioDirector.set_tension(0.0)
	if SaveSystem.has_run():
		_log.text = "НАЙДЕН НЕЗАВЕРШЁННЫЙ ОБХОД"


func _build_title() -> void:
	var logo := UITheme.make_logo("res://art/branding/logo.png", 150.0)
	logo.position = Vector2(72, 62)
	add_child(logo)

	var title := UITheme.make_title("MYDRIASIS", 52)
	title.position = Vector2(76, 218)
	add_child(title)

	var subtitle := UITheme.make_label("ПСИХОЛОГИЧЕСКИЙ БОДИ-ХОРРОР · МОРГ · НОЧНАЯ СМЕНА", 15)
	subtitle.position = Vector2(80, 282)
	subtitle.add_theme_color_override("font_color", UITheme.COLOR_DIM)
	add_child(subtitle)


func _build_menu() -> void:
	_menu_root = VBoxContainer.new()
	_menu_root.position = Vector2(80, 372)
	_menu_root.add_theme_constant_override("separation", 2)
	_menu_root.custom_minimum_size = Vector2(320, 0)
	add_child(_menu_root)

	var new_run := UITheme.make_button("НОВАЯ СМЕНА", 19)
	new_run.pressed.connect(_start_new_run)
	_menu_root.add_child(new_run)

	var cont := UITheme.make_button("ПРОДОЛЖИТЬ ОБХОД", 19)
	cont.disabled = not SaveSystem.has_run()
	cont.pressed.connect(_continue_run)
	_menu_root.add_child(cont)

	var settings := UITheme.make_button("НАСТРОЙКИ", 19)
	settings.pressed.connect(_open_settings)
	_menu_root.add_child(settings)

	var credits := UITheme.make_button("О СТУДИИ", 19)
	credits.pressed.connect(func() -> void:
		_log.text = "MYDRIASIS · ВНУТРЕННЯЯ СБОРКА 0.1.0 · GODOT 4.3 · АРТ МЕНЮ СГЕНЕРИРОВАН, ИГРА — ПРОЦЕДУРНАЯ")
	_menu_root.add_child(credits)

	var quit := UITheme.make_button("ВЫХОД", 19)
	quit.pressed.connect(func() -> void: get_tree().quit())
	_menu_root.add_child(quit)


func _build_footer() -> void:
	_log = UITheme.make_label("СМЕНА НЕ НАЧАТА", 13)
	_log.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_log.position = Vector2(80, -56)
	_log.add_theme_color_override("font_color", Color(0.42, 0.48, 0.50))
	add_child(_log)

	var build := UITheme.make_label("СБОРКА 0.1.0 · %s" % Quality.describe(), 13)
	build.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	build.position = Vector2(-430, -56)
	build.add_theme_color_override("font_color", Color(0.38, 0.44, 0.46))
	add_child(build)


func _build_ecg_strip() -> void:
	# Полоска кардиограммы по нижней кромке: меню дышит вместе с героем,
	# которого ещё нет в кадре. Рисуется кодом, без картинок и шейдеров.
	_ecg = Control.new()
	_ecg.name = "ECG"
	_ecg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_ecg.custom_minimum_size = Vector2(0, 34)
	_ecg.position = Vector2(0, -36)
	_ecg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ecg.draw.connect(_draw_ecg)
	add_child(_ecg)


func _draw_ecg() -> void:
	var width := _ecg.size.x
	var center := _ecg.size.y * 0.5
	var points := PackedVector2Array()
	var steps := 420
	for i in range(0, steps):
		var x := float(i) / float(steps)
		var phase := fposmod(x * 3.0 - _ecg_phase, 1.0)
		var value := _ecg_sample(phase)
		points.append(Vector2(x * width, center - value * 9.0))
	_ecg.draw_polyline(points, Color(0.35, 0.85, 0.55, 0.34), 1.4, true)


func _ecg_sample(phase: float) -> float:
	# Один комплекс: P, Q, R, S, T. В меню пульс спокойный — 58.
	var value := 0.0
	value += exp(-pow((phase - 0.14) / 0.022, 2.0)) * 0.06
	value += exp(-pow((phase - 0.255) / 0.008, 2.0)) * -0.14
	value += exp(-pow((phase - 0.275) / 0.007, 2.0)) * 1.0
	value += exp(-pow((phase - 0.296) / 0.010, 2.0)) * -0.30
	value += exp(-pow((phase - 0.44) / 0.045, 2.0)) * 0.18
	return value


func _process(delta: float) -> void:
	_ecg_phase = fposmod(_ecg_phase + delta * 58.0 / 60.0 * 3.0 / 6.0, 1.0)
	_ecg.queue_redraw()
	if randf() < delta * 0.08:
		AudioDirector.play(&"drip", -30.0, 1.0, AudioDirector.BUS_BED)


# --- Действия -----------------------------------------------------------------

func _start_new_run() -> void:
	SaveSystem.clear_run()
	GameState.reset_run()
	_leave_to_level("НОЧНАЯ СМЕНА · 03:00")


func _continue_run() -> void:
	var data := SaveSystem.load_run()
	if data.is_empty():
		_start_new_run()
		return
	_leave_to_level("ПРОДОЛЖЕНИЕ · %s" % String(data.get("level", "МОРГ")).to_upper())


func _leave_to_level(caption: String) -> void:
	AudioDirector.stop_loop(&"ward_amb", 1.2)
	AudioDirector.stop_loop(&"drone_low", 1.2)
	SceneRouter.goto(LEVEL_SCENE, caption, 0.9, 0.8)


func _open_settings() -> void:
	if _settings == null:
		var scene := load(SETTINGS_SCENE)
		if scene == null:
			return
		_settings = (scene as PackedScene).instantiate()
		add_child(_settings)
		(_settings as Control).visible = true
	_settings.visible = true
	_menu_root.visible = false


func settings_closed() -> void:
	_menu_root.visible = true
