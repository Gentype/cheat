extends CanvasLayer
## Пауза. Кадр замирает — но не замолкает: сердце продолжает биться, потому что
## герой остаётся в блоке, даже когда игрок отпустил клавиатуру.
##
## Здесь единственное место в игре, где видно все цифры сразу: пульс, сатурация,
## давление, время смены и текущее состояние зрачка.

const SETTINGS_SCENE := "res://scenes/ui/settings_menu.tscn"

var _panel: Control
var _vitals: Label
var _clock: Label
var _settings: Control


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	get_tree().paused = true
	GameState.game_paused = true


func _build() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.01, 0.012, 0.015, 0.72)
	add_child(overlay)

	var art := UITheme.make_background("res://art/pause/background_pause.png")
	art.modulate = Color(1, 1, 1, 0.28)
	add_child(art)

	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-230, -170)
	_panel.custom_minimum_size = Vector2(460, 340)
	add_child(_panel)

	var title := UITheme.make_title("ПАУЗА", 34)
	title.position = Vector2(0, 0)
	_panel.add_child(title)

	_clock = UITheme.make_label("", 14)
	_clock.position = Vector2(0, 48)
	_clock.add_theme_color_override("font_color", UITheme.COLOR_DIM)
	_panel.add_child(_clock)

	_vitals = UITheme.make_label("", 15)
	_vitals.position = Vector2(0, 74)
	_vitals.custom_minimum_size = Vector2(460, 40)
	_vitals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_vitals)

	var buttons := VBoxContainer.new()
	buttons.position = Vector2(0, 140)
	buttons.add_theme_constant_override("separation", 2)
	buttons.custom_minimum_size = Vector2(320, 0)
	_panel.add_child(buttons)

	var resume := UITheme.make_button("ПРОДОЛЖИТЬ СМЕНУ", 18)
	resume.pressed.connect(close)
	buttons.add_child(resume)

	var save := UITheme.make_button("СОХРАНИТЬ ОБХОД", 18)
	save.pressed.connect(func() -> void:
		SaveSystem.save_run()
		_clock.text = "ОБХОД СОХРАНЁН · " + Time.get_datetime_string_from_system()
	)
	buttons.add_child(save)

	var settings := UITheme.make_button("НАСТРОЙКИ", 18)
	settings.pressed.connect(_open_settings)
	buttons.add_child(settings)

	var to_menu := UITheme.make_button("В ГЛАВНОЕ МЕНЮ", 18)
	to_menu.pressed.connect(func() -> void:
		get_tree().paused = false
		GameState.game_paused = false
		SaveSystem.save_run()
		SceneRouter.goto_menu("СМЕНА ПРЕРВАНА")
	)
	buttons.add_child(to_menu)

	var quit := UITheme.make_button("ВЫХОД ИЗ ИГРЫ", 18)
	quit.pressed.connect(func() -> void: get_tree().quit())
	buttons.add_child(quit)

	_update_readouts()


func _process(_delta: float) -> void:
	_update_readouts()


func _update_readouts() -> void:
	if _vitals == null:
		return
	var v := GameState.vitals()
	var total := int(GameState.run_time)
	_clock.text = "СМЕНА 03:%02d · %s · %s" % [
		total % 60, String(GameState.current_level).to_upper(), Quality.describe()
	]
	var pupil_text := "РЕАКЦИЯ ЕСТЬ"
	if float(v["pupil"]) > 0.72:
		pupil_text = "НЕТ РЕАКЦИИ"
	elif float(v["pupil"]) > 0.45:
		pupil_text = "ВЯЛАЯ"
	_vitals.text = "ЧСС %d   SpO2 %d%%   АД %d/%d   ЗРАЧОК %s" % [
		int(round(float(v["heart_rate"]))), int(round(float(v["spo2"]))),
		int(round(float(v["systolic"]))), int(round(float(v["diastolic"]))), pupil_text
	]


func close() -> void:
	get_tree().paused = false
	GameState.game_paused = false
	queue_free()


func _open_settings() -> void:
	if _settings == null:
		var scene := load(SETTINGS_SCENE)
		if scene == null:
			return
		_settings = (scene as PackedScene).instantiate()
		add_child(_settings)
		(_settings as Control).settings_closed.connect(_on_settings_closed)
	_settings.visible = true
	_panel.visible = false


func _on_settings_closed() -> void:
	_settings.visible = false
	_panel.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		close()
