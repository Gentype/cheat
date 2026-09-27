class_name CameraDirector
extends Node3D
## Режиссёр камеры. Единственный, кто имеет право двигать камеру.
##
## Правила языка (утверждены арт-директивой проекта):
##   1. Камера НИКОГДА не вращается мышью. Мышью поворачивается только голова
##      героя, и то в ограниченном конусе.
##   2. Переход между ракурсами — жёсткая склейка. Никаких плавных переездов,
##      кроме специально поставленных сценарных доле.
##   3. Внутри ракурса камера живёт: дыхание, дрожь руки, саккады, микро-наезд,
##      удар сердца как осевой толчок.
##   4. Композиция важнее удобства: герой стоит не в центре, а в трети кадра,
##      передний план перекрывает часть кадра.
##
## Кадр меняется, когда: герой вышел из рабочей дистанции ракурса, истекло
## время доли, или ракурс-претендент выигрывает с заметным отрывом.

signal frame_changed(frame: CameraFrame, reason: StringName)

const RE_EVALUATE_INTERVAL := 0.35
const CUT_MARGIN := 0.22

## Камера, которой управляет режиссёр. Создаётся сама, если не задана.
@export var camera_path: NodePath
## Узел, к которому привязывается композиция (голова героя).
var anchor: Node3D
## Текущий ракурс.
var current_frame: CameraFrame
## Теги, которые уровень/скрипт объявляет «интересными» прямо сейчас.
var interest_tags: Array[StringName] = []

var camera: Camera3D
var _frames: Array[CameraFrame] = []
var _frame_time := 0.0
var _dwell := 3.0
var _evaluate_timer := 0.0
var _fov_base := 38.0
var _dolly_offset := 0.0
var _noise_x: FastNoiseLite
var _noise_y: FastNoiseLite
var _noise_z: FastNoiseLite
var _shake_amount := 0.0
var _shake_decay := 2.6
var _rng := RandomNumberGenerator.new()
var _saccade_offset := Vector2.ZERO
var _saccade_timer := 0.0
var _recoil := Vector3.ZERO
var _locked := false
var _scripted_frame: CameraFrame
var _last_cut_time := 0.0
var _frame_tags_active: Array[StringName] = []
var _target_offset_smoothed := Vector3.ZERO


func _ready() -> void:
	_rng.randomize()
	_noise_x = _make_noise(1)
	_noise_y = _make_noise(2)
	_noise_z = _make_noise(3)
	camera = get_node_or_null(camera_path) as Camera3D
	if camera == null:
		camera = _find_camera()
	if camera == null:
		camera = Camera3D.new()
		camera.name = "DirectorCamera"
		add_child(camera)
	camera.current = true
	camera.near = 0.05
	camera.far = 120.0
	camera.fov = 38.0


func _make_noise(seed_value: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.12
	noise.fractal_octaves = 3
	return noise


func _find_camera() -> Camera3D:
	for child in get_children():
		if child is Camera3D:
			return child
	return null


# --- Регистрация ракурсов -----------------------------------------------------

func register_frames(frames: Array) -> void:
	_frames.clear()
	for frame in frames:
		if frame is CameraFrame:
			_frames.append(frame)


func load_frames_from_json(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_ARRAY:
		return false
	var frames: Array = []
	for entry in (parsed as Array):
		if typeof(entry) == TYPE_DICTIONARY:
			frames.append(CameraFrame.from_dict(entry))
	if frames.is_empty():
		return false
	register_frames(frames)
	return true


func frame_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for frame in _frames:
		ids.append(frame.id)
	return ids


func find_frame(id: StringName) -> CameraFrame:
	for frame in _frames:
		if frame.id == id:
			return frame
	return null


func set_anchor(node: Node3D) -> void:
	anchor = node
	_target_offset_smoothed = Vector3.ZERO


# --- Управление ---------------------------------------------------------------

## Жёсткая склейка на конкретный ракурс (триггер, сценарий, дебют бита).
func cut_to(id: StringName, hold := 0.0, reason := &"scripted") -> void:
	var frame := find_frame(id)
	if frame == null:
		push_warning("CameraDirector: нет ракурса " + String(id))
		return
	_apply_frame(frame, reason)
	if hold > 0.0:
		_scripted_frame = frame
		_dwell = hold
	else:
		_scripted_frame = null


func release_scripted() -> void:
	_scripted_frame = null
	_dwell = current_frame.dwell_seconds() if current_frame != null else 3.0


## Полный стоп камеры: замирание, остановка сердца, финальный кадр.
func lock(value: bool) -> void:
	_locked = value


func set_interest_tags(tags: Array) -> void:
	interest_tags.clear()
	for tag in tags:
		interest_tags.append(StringName(String(tag)))


func add_interest_tag(tag: StringName) -> void:
	if not interest_tags.has(tag):
		interest_tags.append(tag)


func remove_interest_tag(tag: StringName) -> void:
	interest_tags.erase(tag)


## Толчок: удар, выстрел, падение тела, разряд.
func impact(amount: float) -> void:
	var scaled := amount
	if Quality.comfort_value("reduce_shake"):
		scaled *= 0.35
	_shake_amount = maxf(_shake_amount, scaled)
	_recoil += Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-0.4, 0.6),
		_rng.randf_range(-1.0, 1.0)
	) * scaled * 0.09


func set_fov_offset(value: float) -> void:
	_fov_base = value


# --- Кадровый цикл ------------------------------------------------------------

func _process(delta: float) -> void:
	if camera == null:
		return
	if current_frame == null:
		var opening := _pick_opening_frame()
		if opening != null:
			_apply_frame(opening, &"opening")
		return

	_frame_time += delta
	_evaluate_timer += delta

	var anchor_position := _anchor_position()
	var distance := camera.global_position.distance_to(anchor_position)

	if not _locked:
		if _evaluate_timer >= RE_EVALUATE_INTERVAL:
			_evaluate_timer = 0.0
			_consider_cut(anchor_position, distance)
		_update_dolly(delta, distance)
	else:
		_update_dolly(delta * 0.25, distance)

	_place_camera(delta, anchor_position, distance)


# --- Выбор ракурса ------------------------------------------------------------

func _pick_opening_frame() -> CameraFrame:
	var best: CameraFrame = null
	for frame in _frames:
		if frame.scripted_only:
			continue
		if frame.opening:
			return frame
		if best == null or frame.bias > best.bias:
			best = frame
	return best


func _score(frame: CameraFrame, anchor_position: Vector3) -> float:
	if frame.scripted_only and _scripted_frame != frame:
		return -1.0
	var d := _frame_distance(frame, anchor_position)
	var score := frame.distance_score(d)
	if score < 0.0:
		return -1.0
	score += frame.bias
	# Совпадение тегов интереса — сильный аргумент в пользу ракурса.
	for tag in frame.tags:
		if interest_tags.has(tag):
			score += 0.75
	# Ракурс, который уже стоит, не меняется без причины.
	if frame == current_frame:
		score += CUT_MARGIN
	# Свежий ракурс: сколько времени прошло с прошлой склейки.
	var since_cut := Time.get_ticks_msec() / 1000.0 - _last_cut_time
	if since_cut < 1.0:
		score -= (1.0 - since_cut) * 0.5
	return score


func _frame_distance(frame: CameraFrame, anchor_position: Vector3) -> float:
	if frame.fixed_in_world:
		return frame.position.distance_to(anchor_position)
	# Ракурс, привязанный к герою: дистанция — это смещение в его системе.
	return frame.position.length()


func _consider_cut(anchor_position: Vector3, distance: float) -> void:
	var dwell_over := _frame_time >= _dwell
	var out_of_range := distance > current_frame.max_distance
	if _scripted_frame != null and not dwell_over:
		return
	if _scripted_frame != null and dwell_over:
		_scripted_frame = null

	var best: CameraFrame = null
	var best_score := -1.0
	for frame in _frames:
		var score := _score(frame, anchor_position)
		if score > best_score:
			best_score = score
			best = frame

	if best == null:
		return
	if best == current_frame:
		if dwell_over:
			_dwell = current_frame.dwell_seconds()
			_frame_time = 0.0
		return
	if out_of_range or dwell_over:
		_apply_frame(best, &"range" if out_of_range else &"dwell")


func _apply_frame(frame: CameraFrame, reason: StringName) -> void:
	var previous := current_frame
	current_frame = frame
	_fov_base = frame.fov
	_dolly_offset = 0.0
	_frame_time = 0.0
	_dwell = frame.dwell_seconds()
	_last_cut_time = Time.get_ticks_msec() / 1000.0
	_recoil = Vector3.ZERO
	_shake_amount = 0.0
	_frame_tags_active = frame.tags
	if camera != null:
		camera.fov = frame.fov
		# Жёсткая склейка: ставим трансформ мгновенно, без интерполяции.
		_place_camera(0.0, _anchor_position(), 0.0, true)
	frame_changed.emit(frame, reason)
	if previous != null and reason != &"opening":
		# Щелчок склейки — часть языка: кадр «переключили», как в кино.
		AudioDirector.play(&"switch", -26.0, 0.7, AudioDirector.BUS_SFX)


# --- Движение внутри кадра ----------------------------------------------------

func _anchor_position() -> Vector3:
	if anchor != null and is_instance_valid(anchor):
		return anchor.global_position
	return global_position


func _update_dolly(delta: float, _distance: float) -> void:
	# Наезд при растущем ужасе: камера медленно придвигается к герою.
	var tension := clampf(GameState.dread * 0.6 + GameState.heartbeat_envelope() * 0.12, 0.0, 1.0)
	var rate := current_frame.push_in * (0.4 + tension * 1.8)
	_dolly_offset = minf(_dolly_offset + rate * delta, 1.4)


func _place_camera(delta: float, anchor_position: Vector3, distance: float, snap := false) -> void:
	if current_frame == null:
		return
	var frame := current_frame
	var target_position: Vector3
	var look_target: Vector3

	if frame.fixed_in_world:
		target_position = frame.position
	else:
		# Привязан к герою: позиция задана в его системе координат.
		var basis := anchor.global_transform.basis if anchor != null else global_transform.basis
		target_position = anchor_position + basis * frame.position

	# Наезд — по направлению к точке взгляда.
	look_target = anchor_position + frame.target_offset + Vector3(0.0, frame.height_bias, 0.0)
	if frame.composition_offset != 0.0 and anchor != null:
		var right := anchor.global_transform.basis.x
		look_target += right * frame.composition_offset * maxf(distance, 0.5) * 0.22
	var to_target := (look_target - target_position)
	var dir := to_target.normalized() if to_target.length() > 0.001 else Vector3.FORWARD
	target_position += dir * _dolly_offset

	# «Живая рука»: медленный дрейф по трём независимым шумам.
	var handheld := frame.handheld
	if Quality.comfort_value("reduce_shake"):
		handheld *= 0.3
	var t := Time.get_ticks_msec() / 1000.0
	var sway := GameState.breath_signed() * 0.012
	var drive := Vector3(
		_noise_x.get_noise_2d(t, 0.0),
		_noise_y.get_noise_2d(t, 0.0) + sway,
		_noise_z.get_noise_2d(t, 0.0)
	) * handheld * 0.06

	# Удар сердца: кадр вздрагивает в такт, сильнее при тахикардии.
	var beat := GameState.heartbeat_envelope()
	var beat_push := Vector3(0.0, 0.0, 0.0)
	if beat > 0.001:
		var intensity := clampf((GameState.heart_rate - 70.0) / 110.0, 0.0, 1.0)
		beat_push = dir * beat * 0.012 * (0.35 + intensity)

	# Тремор при высоком пульсе и падении сатурации.
	var tremor := GameState.tremor() * 0.004
	var jitter := Vector3(
		_noise_z.get_noise_2d(t * 9.0, 11.0),
		_noise_x.get_noise_2d(t * 11.0, 5.0),
		_noise_y.get_noise_2d(t * 8.0, 7.0)
	) * tremor

	# Тряска от событий с затуханием.
	if _shake_amount > 0.0001:
		_shake_amount = maxf(0.0, _shake_amount - delta * _shake_decay)
	var shake := Vector3(
		_noise_y.get_noise_2d(t * 24.0, 3.0),
		_noise_z.get_noise_2d(t * 27.0, 8.0),
		_noise_x.get_noise_2d(t * 21.0, 1.0)
	) * _shake_amount * 0.05
	_recoil = _recoil.lerp(Vector3.ZERO, minf(delta * 8.0, 1.0))

	target_position += drive + beat_push + jitter + shake + _recoil

	# Саккады: глаз дёргается, а не скользит. Раз в 1.5-4 с — микро-рывок.
	_saccade_timer -= delta
	if _saccade_timer <= 0.0:
		_saccade_timer = _rng.randf_range(1.5, 4.0)
		var amount := 0.0018 if Quality.comfort_value("reduce_shake") else 0.0042
		_saccade_offset = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.5, 0.5)) * amount
	_saccade_offset = _saccade_offset.lerp(Vector2.ZERO, minf(delta * 2.4, 1.0))

	if snap or delta <= 0.0:
		camera.global_position = target_position
	else:
		# Демпфирование сглаживает саккады и тряску, но не превращает склейку в переезд.
		camera.global_position = camera.global_position.lerp(target_position, minf(delta * 14.0, 1.0))

	# Наведение: камера смотрит в точку интереса, а не по своему forward.
	var look := look_target
	var up_vector := Vector3.UP.rotated(Vector3.FORWARD, deg_to_rad(frame.roll + _saccade_offset.y * 40.0))
	var offset_look := look + Vector3.RIGHT.rotated(up_vector, _saccade_offset.x * 26.0)
	var to_look := offset_look - camera.global_position
	if to_look.length_squared() > 0.000001:
		camera.global_transform = Transform3D(Basis.looking_at(to_look.normalized(), up_vector), camera.global_position)

	# Дыхание фокуса: FOV пульсирует на вдохе-выдохе и на ударе сердца.
	var fov_breath := GameState.breath_signed() * 0.18
	var fov_beat := beat * 0.35 * clampf((GameState.heart_rate - 80.0) / 100.0, 0.0, 1.0)
	camera.fov = lerpf(camera.fov, _fov_base + fov_breath + fov_beat, minf(delta * 6.0, 1.0))
