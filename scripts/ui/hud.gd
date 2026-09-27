class_name HUD
extends Control
## Интерфейс боя за жизнь. Решён как показания прикроватного монитора:
## цифры, единицы, никакой «геймовой» плашки. Всё, что видит игрок, врач
## увидел бы на экране у койки.
##
## Панель виталитетов показывает то же, что и шейдеры: пульс, сатурацию,
## давление, зрачок. Расхождение между картинкой и цифрами невозможно —
## оба читают GameState.

const COLOR_OK := Color(0.62, 0.88, 0.72)
const COLOR_WARN := Color(0.92, 0.80, 0.42)
const COLOR_BAD := Color(0.95, 0.42, 0.38)
const COLOR_DIM := Color(0.55, 0.62, 0.66)

var vitals_label: Label
var objective_label: Label
var prompt_label: Label
var subtitle_label: Label
var look_indicator: Control
var cuff_panel: Control
var cuff_value: Label
var cuff_bar: ProgressBar
var stress_frame: ColorRect

var _objective := ""
var _prompt := ""
var _subtitle := ""
var _subtitle_timer := 0.0
var _look_x := 0.0
var _cuff_visible := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build()
	GameState.vitals_changed.connect(_on_vitals_changed)
	_on_vitals_changed(GameState.vitals())


func _build() -> void:
	# Верхняя строка: номер смены и таймер.
	var top := _make_label(Vector2(24, 18), HORIZONTAL_ALIGNMENT_LEFT)
	top.name = "Clock"
	top.text = "СМЕНА 03:00"
	top.add_theme_color_override("font_color", COLOR_DIM)
	top.add_theme_font_size_override("font_size", 15)

	# Объектив — по центру сверху, мелко: игра не кричит игроку, что делать.
	objective_label = _make_label(Vector2(0, 40), HORIZONTAL_ALIGNMENT_CENTER)
	objective_label.name = "Objective"
	objective_label.add_theme_font_size_override("font_size", 16)
	objective_label.add_theme_color_override("font_color", Color(0.80, 0.84, 0.86, 0.85))
	objective_label.set_anchors_preset(Control.PRESET_TOP_WIDE)

	# Панель виталитетов — левый нижний угол, как у монитора на стойке.
	vitals_label = _make_label(Vector2(24, 0), HORIZONTAL_ALIGNMENT_LEFT)
	vitals_label.name = "Vitals"
	vitals_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	vitals_label.position = Vector2(24, -108)
	vitals_label.add_theme_font_size_override("font_size", 14)

	# Индикатор направления головы: короткая риска снизу по центру.
	look_indicator = Control.new()
	look_indicator.name = "LookIndicator"
	look_indicator.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	look_indicator.custom_minimum_size = Vector2(180, 8)
	look_indicator.position = Vector2(-90, -46)
	look_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	look_indicator.draw.connect(_draw_look_indicator)
	add_child(look_indicator)

	# Подсказка взаимодействия — под центром, спокойная.
	prompt_label = _make_label(Vector2(0, -70), HORIZONTAL_ALIGNMENT_CENTER)
	prompt_label.name = "Prompt"
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.add_theme_font_size_override("font_size", 15)
	prompt_label.add_theme_color_override("font_color", Color(0.92, 0.90, 0.84, 0.92))

	subtitle_label = _make_label(Vector2(0, -130), HORIZONTAL_ALIGNMENT_CENTER)
	subtitle_label.name = "Subtitle"
	subtitle_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	subtitle_label.add_theme_font_size_override("font_size", 16)
	subtitle_label.add_theme_color_override("font_color", Color(0.88, 0.90, 0.92))

	# Панель манжеты: то, что видит герой, когда измеряет себе давление.
	cuff_panel = _build_cuff_panel()

	# Рамка стресса: тонкая красная кромка при критическом пульсе.
	stress_frame = ColorRect.new()
	stress_frame.name = "StressFrame"
	stress_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	stress_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stress_frame.color = Color(0.7, 0.1, 0.08, 0.0)
	add_child(stress_frame)


func _make_label(at: Vector2, alignment: int) -> Label:
	var label := Label.new()
	label.position = at
	label.horizontal_alignment = alignment
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)
	return label


func _build_cuff_panel() -> Control:
	var panel := Control.new()
	panel.name = "CuffPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-150, -90)
	panel.custom_minimum_size = Vector2(300, 150)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	add_child(panel)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.035, 0.82)
	panel.add_child(backdrop)

	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_stylebox_override("panel", _frame_style())
	panel.add_child(frame)

	var title := Label.new()
	title.text = "МАНЖЕТА · АВТОМАТИЧЕСКОЕ ИЗМЕРЕНИЕ"
	title.position = Vector2(12, 8)
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", COLOR_DIM)
	panel.add_child(title)

	cuff_value = Label.new()
	cuff_value.text = "— / —"
	cuff_value.position = Vector2(12, 34)
	cuff_value.add_theme_font_size_override("font_size", 38)
	cuff_value.add_theme_color_override("font_color", COLOR_OK)
	panel.add_child(cuff_value)

	cuff_bar = ProgressBar.new()
	cuff_bar.position = Vector2(12, 96)
	cuff_bar.custom_minimum_size = Vector2(276, 14)
	cuff_bar.max_value = 200.0
	cuff_bar.value = 0.0
	cuff_bar.show_percentage = false
	cuff_bar.add_theme_stylebox_override("background", _bar_style(Color(0.10, 0.13, 0.14)))
	cuff_bar.add_theme_stylebox_override("fill", _bar_style(Color(0.55, 0.82, 0.68)))
	panel.add_child(cuff_bar)

	var hint := Label.new()
	hint.text = "НЕ ШЕВЕЛИТЬСЯ · НЕ ДЫШАТЬ ГЛУБОКО"
	hint.position = Vector2(12, 118)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", COLOR_WARN)
	panel.add_child(hint)
	return panel


func _frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0.35, 0.48, 0.46, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	return style


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style


func _process(delta: float) -> void:
	# Показания живут в такт сердцу: цифры чуть ярче на систоле.
	var beat := GameState.heartbeat_envelope()
	if vitals_label != null:
		vitals_label.modulate.a = 0.86 + beat * 0.14
		var clock := get_node_or_null("Clock") as Label
		if clock != null:
			var total := int(GameState.run_time)
			clock.text = "СМЕНА %02d:%02d · %s" % [
				int(total / 60.0) + 3, total % 60, _tier_name()
			]

	if _subtitle_timer > 0.0:
		_subtitle_timer -= delta
		if _subtitle_timer <= 0.0:
			_subtitle = ""
			subtitle_label.text = ""

	var dread := GameState.dread
	stress_frame.color.a = lerpf(stress_frame.color.a, clampf((dread - 0.55) * 0.5, 0.0, 0.35), minf(delta * 2.0, 1.0))

	if look_indicator != null:
		look_indicator.queue_redraw()


func _tier_name() -> String:
	return String(Quality.TIER_NAMES[Quality.tier])


func _draw_look_indicator() -> void:
	# Риска показывает, куда смотрит ГОЛОВА (не камера): при жёстких склейках
	# игроку нужно понимать, куда направлен его взгляд.
	var width := look_indicator.size.x
	var center := width * 0.5
	var offset := clampf(_look_x, -1.0, 1.0) * (width * 0.32)
	look_indicator.draw_line(Vector2(center - 40, 4), Vector2(center + 40, 4), Color(0.5, 0.6, 0.62, 0.25), 1.0)
	look_indicator.draw_line(Vector2(center + offset, 0), Vector2(center + offset, 8), Color(0.85, 0.9, 0.92, 0.75), 2.0)


# --- Публичный интерфейс -------------------------------------------------------

func set_look(value: float) -> void:
	_look_x = value


func set_objective(text: String) -> void:
	_objective = text
	objective_label.text = text


func set_prompt(text: String) -> void:
	_prompt = text
	prompt_label.text = text


func say(text: String, duration := 3.5) -> void:
	_subtitle = text
	subtitle_label.text = text
	_subtitle_timer = duration


func show_cuff(visible: bool) -> void:
	_cuff_visible = visible
	cuff_panel.visible = visible


func set_cuff_pressure(value: float, pulse: int) -> void:
	cuff_bar.value = clampf(value, 0.0, 200.0)
	var pulse_color := COLOR_OK
	if pulse > 120 or pulse < 50:
		pulse_color = COLOR_WARN
	if pulse > 150:
		pulse_color = COLOR_BAD
	cuff_value.add_theme_color_override("font_color", pulse_color)
	cuff_value.text = "%d" % pulse


func set_cuff_result(systolic: int, diastolic: int) -> void:
	cuff_value.text = "%d / %d" % [systolic, diastolic]
	var color := COLOR_OK
	if systolic > 150 or systolic < 95:
		color = COLOR_WARN
	if systolic < 85:
		color = COLOR_BAD
	cuff_value.add_theme_color_override("font_color", color)


func _on_vitals_changed(vitals: Dictionary) -> void:
	var bpm := int(round(float(vitals.get("heart_rate", 72.0))))
	var spo2 := int(round(float(vitals.get("spo2", 98.0))))
	var sys := int(round(float(vitals.get("systolic", 118.0))))
	var dia := int(round(float(vitals.get("diastolic", 76.0))))
	var pupil := float(vitals.get("pupil", 0.2))
	var pupil_text := "РЕАКЦИЯ ЕСТЬ"
	if pupil > 0.72:
		pupil_text = "НЕТ РЕАКЦИИ"
	elif pupil > 0.45:
		pupil_text = "ВЯЛАЯ"

	vitals_label.text = "ЧСС %d   SpO2 %d%%   АД %d/%d   ЗРАЧОК %s" % [
		bpm, spo2, sys, dia, pupil_text
	]
	# Цвет показывает худшее из показателей, а не среднее: монитор не льстит.
	var worst := COLOR_OK
	if bpm > 120 or spo2 < 94.0 or sys > 150.0:
		worst = COLOR_WARN
	if bpm > 150 or spo2 < 88.0 or sys < 85.0:
		worst = COLOR_BAD
	vitals_label.add_theme_color_override("font_color", worst.lerp(Color(0.78, 0.84, 0.86), 0.45))
