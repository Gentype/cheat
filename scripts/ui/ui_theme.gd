class_name UITheme
extends RefCounted
## Единая тема интерфейса: шрифты, цвета, типовые элементы.
##
## Интерфейс сделан под медицинский монитор: холодные полутона, монотипные
## цифры, минимум декора. Никаких «игровых» рамок и градиентов — только то,
## что могло бы стоять на стойке в реанимации.
##
## Шрифты лежат в art/fonts. Если их нет (например, чистая выкачка без
## арт-ассетов), интерфейс молча падает на шрифт движка — игра остаётся
## читаемой, потому что все размеры и отступы заданы кодом.

const COLOR_TEXT := Color(0.86, 0.89, 0.90)
const COLOR_DIM := Color(0.52, 0.58, 0.60)
const COLOR_ACCENT := Color(0.62, 0.82, 0.86)
const COLOR_WARN := Color(0.92, 0.78, 0.42)
const COLOR_BAD := Color(0.95, 0.42, 0.38)
const COLOR_OK := Color(0.62, 0.88, 0.72)
const COLOR_PANEL := Color(0.03, 0.04, 0.045, 0.86)

const FONT_DIR := "res://art/fonts/"
const MONO_CANDIDATES := [
	"DejaVuSansMono.ttf", "mono.ttf",
]
const DISPLAY_CANDIDATES := [
	"DejaVuSansCondensed-Bold.ttf", "DejaVuSans-Bold.ttf", "display.ttf",
]

static var _mono: Font = null
static var _display: Font = null


static func mono_font() -> Font:
	if _mono != null:
		return _mono
	_mono = _load_first(MONO_CANDIDATES)
	return _mono


static func display_font() -> Font:
	if _display != null:
		return _display
	_display = _load_first(DISPLAY_CANDIDATES)
	return _display


static func _load_first(names: Array) -> Font:
	for name in names:
		var path := FONT_DIR + String(name)
		if ResourceLoader.exists(path):
			var resource := load(path)
			if resource is Font:
				return resource
	# Фолбэк: шрифт темы движка. Он есть всегда, поэтому интерфейс не сломается.
	return ThemeDB.fallback_font


static func apply_label(label: Label, size := 16, font: Font = null) -> void:
	label.add_theme_font_override("font", font if font != null else mono_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)


static func make_label(text: String, size := 16, font: Font = null) -> Label:
	var label := Label.new()
	label.text = text
	apply_label(label, size, font)
	return label


static func make_title(text: String, size := 34) -> Label:
	var label := make_label(text, size, display_font())
	label.add_theme_color_override("font_color", Color(0.94, 0.95, 0.95))
	return label


## Кнопка: тонкая линия, никакой заливки. Наведение — свет и звук.
static func make_button(text: String, size := 17) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", mono_font())
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_color_override("font_color", COLOR_DIM)
	button.add_theme_color_override("font_hover_color", Color(0.96, 0.97, 0.97))
	button.add_theme_color_override("font_pressed_color", COLOR_ACCENT)
	button.add_theme_color_override("font_disabled_color", Color(0.30, 0.33, 0.34))
	button.add_theme_color_override("font_focus_color", COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _flat_box(Color(0, 0, 0, 0)))
	button.add_theme_stylebox_override("hover", _flat_box(Color(1, 1, 1, 0.05)))
	button.add_theme_stylebox_override("pressed", _flat_box(Color(1, 1, 1, 0.10)))
	button.add_theme_stylebox_override("disabled", _flat_box(Color(0, 0, 0, 0)))
	button.add_theme_stylebox_override("focus", _flat_box(Color(1, 1, 1, 0.04)))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.mouse_entered.connect(func() -> void:
		AudioDirector.play(&"ui_hover", -22.0, 1.0, AudioDirector.BUS_SFX))
	button.pressed.connect(func() -> void:
		AudioDirector.play(&"ui_press", -14.0, 1.0, AudioDirector.BUS_SFX))
	return button


static func _flat_box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	style.set_corner_radius_all(2)
	return style


static func make_slider(minimum: float, maximum: float, value: float, step := 0.01) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(240, 22)
	return slider


static func make_check(text: String, pressed: bool) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = pressed
	box.focus_mode = Control.FOCUS_NONE
	box.add_theme_font_override("font", mono_font())
	box.add_theme_font_size_override("font_size", 15)
	box.add_theme_color_override("font_color", COLOR_DIM)
	box.add_theme_color_override("font_hover_color", COLOR_TEXT)
	return box


## Фон меню. Если картинки нет — остаётся процедурная подложка, и меню
## всё равно выглядит цельно (важно для чистой выкачки репозитория).
static func make_background(path: String) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015, 0.018, 0.021)
	root.add_child(backdrop)

	if ResourceLoader.exists(path):
		var texture := TextureRect.new()
		texture.texture = load(path)
		texture.set_anchors_preset(Control.PRESET_FULL_RECT)
		texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture.modulate = Color(0.72, 0.76, 0.78)
		root.add_child(texture)

	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.85), Color(0.0, 0.0, 0.0, 0.15), Color(0.0, 0.0, 0.0, 0.7),
	])
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill_from = Vector2(0.5, 0.0)
	gradient_texture.fill_to = Vector2(0.5, 1.0)
	var rect := TextureRect.new()
	rect.texture = gradient_texture
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rect)
	return root


static func make_logo(path: String, height := 190.0) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(height * 1.6, height)
	if not ResourceLoader.exists(path):
		var title := make_title("MYDRIASIS", int(height * 0.32))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.add_child(title)
		return holder
	var texture := TextureRect.new()
	texture.texture = load(path)
	texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	holder.add_child(texture)
	return holder
