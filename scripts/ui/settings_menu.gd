extends Control
## Настройки. Разделены на четыре раздела: изображение, звук, управление и
## доступность. Раздел доступности здесь не «галочка для галочки»: игра
## намеренно давит на физиологию, и игрок должен иметь право ослабить хватку.

signal settings_closed()

const LEVEL_SCENE := "res://scenes/game/ward_night.tscn"

enum Section { VIDEO, AUDIO, INPUT, COMFORT }

var _section: Section = Section.VIDEO
var _content: VBoxContainer
var _tabs: VBoxContainer
var _status: Label
var _preview: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(UITheme.make_background("res://art/settings/background_settings.png"))

	var title := UITheme.make_title("НАСТРОЙКИ", 30)
	title.position = Vector2(72, 56)
	add_child(title)

	_preview = UITheme.make_label("", 13)
	_preview.position = Vector2(72, 100)
	_preview.custom_minimum_size = Vector2(700, 20)
	_preview.add_theme_color_override("font_color", UITheme.COLOR_DIM)
	add_child(_preview)

	_tabs = VBoxContainer.new()
	_tabs.position = Vector2(72, 150)
	_tabs.add_theme_constant_override("separation", 2)
	_tabs.custom_minimum_size = Vector2(240, 0)
	add_child(_tabs)

	_build_tabs()

	_content = VBoxContainer.new()
	_content.position = Vector2(360, 150)
	_content.add_theme_constant_override("separation", 10)
	_content.custom_minimum_size = Vector2(620, 0)
	add_child(_content)

	_status = UITheme.make_label("", 13)
	_status.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_status.position = Vector2(72, -56)
	_status.add_theme_color_override("font_color", Color(0.42, 0.48, 0.50))
	add_child(_status)

	var back := UITheme.make_button("НАЗАД", 18)
	back.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	back.position = Vector2(-160, -64)
	back.pressed.connect(_close)
	add_child(back)

	_refresh()


func _build_tabs() -> void:
	var labels := ["ИЗОБРАЖЕНИЕ", "ЗВУК", "УПРАВЛЕНИЕ", "ДОСТУПНОСТЬ"]
	for i in range(0, labels.size()):
		var button := UITheme.make_button(labels[i], 17)
		button.pressed.connect(_select_section.bind(i))
		_tabs.add_child(button)


func _select_section(index: int) -> void:
	_section = index as Section
	_refresh()


func _refresh() -> void:
	for child in _content.get_children():
		child.queue_free()
	_preview.text = Quality.describe()
	match _section:
		Section.VIDEO:
			_build_video()
		Section.AUDIO:
			_build_audio()
		Section.INPUT:
			_build_input()
		Section.COMFORT:
			_build_comfort()


# --- Разделы ------------------------------------------------------------------

func _build_video() -> void:
	_add_section_label("УРОВЕНЬ КАЧЕСТВА")
	var tiers := HBoxContainer.new()
	tiers.add_theme_constant_override("separation", 6)
	_content.add_child(tiers)
	for tier in [Quality.Tier.LOW, Quality.Tier.MEDIUM, Quality.Tier.HIGH, Quality.Tier.ULTRA]:
		var button := UITheme.make_button(String(Quality.TIER_NAMES[tier]), 16)
		button.disabled = Quality.tier == tier
		button.pressed.connect(func() -> void:
			Quality.set_tier(tier)
			_status.text = "УРОВЕНЬ: %s" % Quality.describe()
			_refresh()
		)
		tiers.add_child(button)

	_add_slider("МАСШТАБ РЕНДЕРА", 0.6, 1.0, Quality.render_scale, func(value: float) -> void:
		Quality.auto_guard = false
		SaveSystem.set_setting("video/auto_guard", false)
		Quality.set_render_scale(value)
		_preview.text = Quality.describe()
	)

	var guard := UITheme.make_check("АВТОМАТИЧЕСКИЙ СТОРОЖ ПРОИЗВОДИТЕЛЬНОСТИ",
		bool(SaveSystem.get_setting("video/auto_guard", true)))
	guard.toggled.connect(func(pressed: bool) -> void:
		Quality.auto_guard = pressed
		SaveSystem.set_setting("video/auto_guard", pressed)
	)
	_content.add_child(guard)

	_add_slider("ЦЕЛЕВАЯ ЧАСТОТА КАДРОВ", 30.0, 144.0,
		float(SaveSystem.get_setting("video/target_fps", 60)), func(value: float) -> void:
		SaveSystem.set_setting("video/target_fps", int(value))
		Quality.target_fps = int(value)
	, 1.0)


func _build_audio() -> void:
	for entry in [
		["ОБЩАЯ ГРОМКОСТЬ", "audio/master", 0.85],
		["ПАЛАТА (ФОН)", "audio/bed", 0.7],
		["ТЕЛО (ПУЛЬС, ДЫХАНИЕ)", "audio/body", 0.9],
		["БЛОК (ШАГИ, МЕТАЛЛ)", "audio/sfx", 0.8],
		["ГОЛОСА", "audio/voices", 0.9],
	] as Array:
		var key: String = entry[1]
		var fallback: float = entry[2]
		_add_slider(String(entry[0]), 0.0, 1.0, float(SaveSystem.get_setting(key, fallback)),
			func(value: float) -> void: SaveSystem.set_setting(key, value))
	var mono := UITheme.make_check("СВЕСТИ В МОНО (ОДИН НАУШНИК)",
		bool(SaveSystem.get_setting("audio/mono", false)))
	mono.toggled.connect(func(pressed: bool) -> void:
		SaveSystem.set_setting("audio/mono", pressed)
		AudioDirector.set_mono(pressed)
	)
	_content.add_child(mono)


func _build_input() -> void:
	_add_slider("ЧУВСТВИТЕЛЬНОСТЬ МЫШИ", 0.0005, 0.006,
		float(SaveSystem.get_setting("input/sensitivity", 0.0022)), func(value: float) -> void:
		SaveSystem.set_setting("input/sensitivity", value)
		var level := get_tree().get_first_node_in_group(&"level")
		if level != null and level.has_method(&"get") and level.get("player") != null:
			level.get("player").mouse_sensitivity = value
	, 0.0001)

	var invert := UITheme.make_check("ИНВЕРТИРОВАТЬ ВЕРТИКАЛЬ",
		bool(SaveSystem.get_setting("input/invert_y", false)))
	invert.toggled.connect(func(pressed: bool) -> void:
		SaveSystem.set_setting("input/invert_y", pressed)
	)
	_content.add_child(invert)

	_add_section_label("КАМЕРА НЕ ВРАЩАЕТСЯ МЫШЬЮ")
	var note := UITheme.make_label(
		"Мышью поворачивается только голова героя. Ракурс выбирает режиссёр: это язык игры, а не настройка.",
		14)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(600, 60)
	note.add_theme_color_override("font_color", UITheme.COLOR_DIM)
	_content.add_child(note)

	_add_section_label("КЛАВИШИ")
	var keys := UITheme.make_label(
		"WASD — движение · E — взаимодействие · SHIFT — задержать дыхание\n"
		+ "ESC — пауза · F1 — отладочная камера · F2 — следующий ракурс · F10 — качество",
		14)
	keys.custom_minimum_size = Vector2(620, 60)
	keys.add_theme_color_override("font_color", UITheme.COLOR_DIM)
	_content.add_child(keys)


func _build_comfort() -> void:
	_add_section_label("ИГРА ДАВИТ НА ФИЗИОЛОГИЮ — ЭТО МОЖНО ОСЛАБИТЬ")
	for entry in [
		["УБРАТЬ ЗЕРНО ПЛЁНКИ", "comfort/reduce_grain"],
		["УМЕНЬШИТЬ ДРОЖАНИЕ КАДРА", "comfort/reduce_shake"],
		["БЕЗ ВСПЫШЕК", "comfort/no_flash"],
		["БЕЗ ДЕФОРМАЦИИ ЗРАЧКА", "comfort/no_pupil_distortion"],
	] as Array:
		var key := String(entry[1])
		var check := UITheme.make_check(String(entry[0]),
			bool(SaveSystem.get_setting(key, false)))
		check.toggled.connect(func(pressed: bool) -> void:
			SaveSystem.set_setting(key, pressed)
			Quality.comfort[key.split("/")[1]] = pressed
			ShaderLibrary.refresh_all()
		)
		_content.add_child(check)

	var note := UITheme.make_label(
		"Смысловые эффекты (сужение поля зрения, падение давления, остановка сердца) "
		+ "не отключаются: без них бит теряет содержание. Отключается только оптика.",
		14)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(620, 70)
	note.add_theme_color_override("font_color", UITheme.COLOR_DIM)
	_content.add_child(note)

	var reset := UITheme.make_button("СБРОСИТЬ ВСЕ НАСТРОЙКИ", 16)
	reset.pressed.connect(func() -> void:
		SaveSystem.reset_everything()
		_status.text = "НАСТРОЙКИ СБРОШЕНЫ"
		_refresh()
	)
	_content.add_child(reset)


# --- Помощники -----------------------------------------------------------------

func _add_section_label(text: String) -> void:
	var label := UITheme.make_label(text, 14)
	label.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	_content.add_child(label)


func _add_slider(label_text: String, minimum: float, maximum: float, value: float,
		on_change: Callable, step := 0.01) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := UITheme.make_label(label_text, 15)
	label.custom_minimum_size = Vector2(300, 0)
	row.add_child(label)
	var slider := UITheme.make_slider(minimum, maximum, value, step)
	row.add_child(slider)
	var readout := UITheme.make_label(_format(value), 14)
	readout.custom_minimum_size = Vector2(80, 0)
	row.add_child(readout)
	slider.value_changed.connect(func(new_value: float) -> void:
		readout.text = _format(new_value)
		on_change.call(new_value)
	)
	_content.add_child(row)


func _format(value: float) -> String:
	if value <= 0.01:
		return "%.4f" % value
	return "%d%%" % int(round(value * 100.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		_close()


func _close() -> void:
	settings_closed.emit()
	if get_parent() is Control:
		# Открыты из меню — просто прячемся, меню вернёт свою панель.
		var parent := get_parent()
		if parent.has_method(&"settings_closed"):
			parent.call(&"settings_closed")
		visible = false
		return
	queue_free()
