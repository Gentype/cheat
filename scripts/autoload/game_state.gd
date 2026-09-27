extends Node
## GameState — единственный источник правды о состоянии героя.
##
## Здесь живут виталитеты (пульс, сатурация, давление, сознание) и накопленный
## ужас `dread`. Отсюда их читают: камера (дрожание, дыхание, фокус), шейдеры
## (зрачок, вуаль, давление), звук (пульс, дыхание) и HUD.
##
## Важно: GameState НЕ знает о сценах и не управляет ими. Он только описывает
## состояние. Это позволяет любому биту игры подписаться на одни и те же шкалы.

signal vitals_changed(vitals: Dictionary)
signal dread_changed(value: float)
signal stress_spike(amount: float, reason: StringName)
signal beat(index: int)
signal breath_cycle(inhale: bool)
signal flag_changed(key: StringName, value: Variant)
signal consciousness_changed(value: float)

const HEART_MIN := 38.0
const HEART_MAX := 208.0
const BASE_HEART := 72.0

## Пульс, уд/мин.
var heart_rate := BASE_HEART
## Сатурация, %.
var spo2 := 98.0
## Давление, мм рт. ст.
var systolic := 118.0
var diastolic := 76.0
## Температура тела, °C.
var temperature := 36.6
## Сознание: 1 — ясное, 0 — запредельная кома.
var consciousness := 1.0
## Накопленный ужас 0..1 — основная шкала бита.
var dread := 0.0
## Дыхание: удерживается ли вдох.
var holding_breath := false
## Фаза дыхательного цикла 0..1 (0 — вдох, 0.5 — выдох).
var breath_phase := 0.0
## Текущее состояние смены (для сохранений и продолжений).
var current_level := &""
var run_time := 0.0
var run_flags: Dictionary = {}
var difficulty := 1
var game_paused := false

var _heart_envelope := 0.0
var _beat_index := 0
var _beat_accumulator := 0.0
var _vitals_dirty := false
var _tick_accumulator := 0.0
var _breath_was_inhale := true
var _stress_decay := 0.35
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Автолоады по умолчанию работают даже на паузе — нам это не нужно.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	reset_run()


func _process(delta: float) -> void:
	if game_paused:
		return
	_tick(delta)


## Полный сброс смены: герой «новый», ужаса нет.
func reset_run() -> void:
	heart_rate = BASE_HEART
	spo2 = 98.0
	systolic = 118.0
	diastolic = 76.0
	temperature = 36.6
	consciousness = 1.0
	dread = 0.0
	holding_breath = false
	breath_phase = 0.0
	run_time = 0.0
	run_flags.clear()
	current_level = &""
	_heart_envelope = 0.0
	_beat_index = 0
	_beat_accumulator = 0.0
	_vitals_dirty = true
	dread_changed.emit(dread)
	consciousness_changed.emit(consciousness)


## Нагрузка на организм: страх, боль, усилие, холод. Держит виталитеты
## согласованными — всё, что растёт, тянет за собой пульс и сатурацию.
func apply_stress(amount: float, reason: StringName = &"") -> void:
	if is_zero_approx(amount):
		return
	dread = clampf(dread + amount * 0.06, 0.0, 1.0)
	heart_rate = clampf(heart_rate + amount * 6.5, HEART_MIN, HEART_MAX)
	spo2 = clampf(spo2 - amount * 0.85 - maxf(0.0, heart_rate - 150.0) * 0.02, 55.0, 100.0)
	systolic = clampf(systolic + amount * 2.2, 55.0, 210.0)
	diastolic = clampf(diastolic + amount * 1.1, 30.0, 140.0)
	_vitals_dirty = true
	if amount > 0.35:
		stress_spike.emit(amount, reason)
		dread_changed.emit(dread)


## Успокоение: ровное дыхание, знакомый предмет, свет.
func soothe(amount: float, _reason: StringName = &"") -> void:
	if is_zero_approx(amount):
		return
	dread = clampf(dread - amount * 0.05, 0.0, 1.0)
	heart_rate = clampf(heart_rate - amount * 3.0, HEART_MIN, HEART_MAX)
	spo2 = clampf(spo2 + amount * 0.4, 55.0, 100.0)
	_vitals_dirty = true
	dread_changed.emit(dread)


func set_consciousness(value: float, _reason: StringName = &"") -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, consciousness):
		return
	consciousness = clamped
	consciousness_changed.emit(consciousness)
	_vitals_dirty = true
	if clamped <= 0.001:
		# Сознание ушло: пульс уходит в брадикардию, сатурация падает.
		heart_rate = maxf(38.0, heart_rate * 0.55)
		spo2 = minf(spo2, 68.0)


# --- Флаги бита ---------------------------------------------------------------

func set_flag(key: StringName, value: Variant = true) -> void:
	var previous: Variant = run_flags.get(key, false)
	if previous == value:
		return
	run_flags[key] = value
	flag_changed.emit(key, value)


func has_flag(key: StringName) -> bool:
	return truthy(run_flags.get(key, false))


static func truthy(value: Variant) -> bool:
	match typeof(value):
		TYPE_BOOL:
			return value
		TYPE_INT:
			return value != 0
		TYPE_FLOAT:
			return not is_zero_approx(value)
		TYPE_NIL:
			return false
		_:
			return true


func bump_counter(key: StringName, amount: int = 1) -> int:
	var current := int(run_flags.get(key, 0)) + amount
	run_flags[key] = current
	flag_changed.emit(key, current)
	return current


# --- Производные параметры для шейдеров и звука -------------------------------

## Размер зрачка 0..1. Считается не «для красоты»: расширение зрачка —
## прямой симптом гипоксии и запредельного торможения ЦНС.
func pupil_size() -> float:
	var hypoxic := clampf((98.0 - spo2) / 34.0, 0.0, 1.0)
	var failing := 1.0 - consciousness
	var value := 0.14 + dread * 0.55 + hypoxic * 0.45 + failing * 0.55
	return clampf(value, 0.0, 1.0)


## Насколько упало давление: 0 — норма, 1 — критическая гипотензия.
func pressure_level() -> float:
	return clampf((110.0 - systolic) / 60.0, 0.0, 1.0)


## Конверт удара сердца 0..1 — для микро-зума, вспышек и толчков камеры.
func heartbeat_envelope() -> float:
	return _heart_envelope


func tremor() -> float:
	return clampf((heart_rate - 90.0) / 90.0 + (1.0 - consciousness) * 0.4 + dread * 0.3, 0.0, 1.0)


func cold() -> float:
	return clampf((36.6 - temperature) / 3.0, 0.0, 1.0)


func breath_signed() -> float:
	# -1 выдох .. +1 вдох, для лёгкого затемнения кадра.
	return -cos(breath_phase * TAU)


func vitals() -> Dictionary:
	return {
		"heart_rate": heart_rate,
		"spo2": spo2,
		"systolic": systolic,
		"diastolic": diastolic,
		"temperature": temperature,
		"consciousness": consciousness,
		"dread": dread,
		"pupil": pupil_size(),
	}


# --- Внутренний такт ----------------------------------------------------------

func _tick(delta: float) -> void:
	run_time += delta
	var bpm := heart_rate

	# Дыхание: 12-20 вдохов в минуту, чаще при стрессе.
	var breath_rate := lerpf(0.19, 0.62, clampf((bpm - 60.0) / 110.0, 0.0, 1.0))
	if holding_breath:
		breath_rate *= 0.18
	breath_phase = fposmod(breath_phase + breath_rate * delta, 1.0)
	var inhaling := breath_phase < 0.45
	if inhaling != _breath_was_inhale:
		_breath_was_inhale = inhaling
		breath_cycle.emit(inhaling)

	# Удар сердца: конверт живёт ~0.28 с, поэтому на 180 bpm он почти не гаснет.
	_beat_accumulator += delta
	var beat_period := 60.0 / maxf(bpm, 1.0)
	if _beat_accumulator >= beat_period:
		_beat_accumulator = fposmod(_beat_accumulator, beat_period)
		_beat_index += 1
		_heart_envelope = 1.0
		beat.emit(_beat_index)
	_heart_envelope = maxf(0.0, _heart_envelope - delta * 3.6)

	# Естественное затухание ужаса и возврат виталитетов к норме.
	dread = clampf(dread - _stress_decay * delta * 0.05, 0.0, 1.0)
	var rest := 1.0 - dread
	heart_rate = lerpf(heart_rate, lerpf(BASE_HEART, 58.0, rest), delta * 0.08)
	systolic = lerpf(systolic, lerpf(128.0, 108.0, rest), delta * 0.06)
	diastolic = lerpf(diastolic, lerpf(84.0, 68.0, rest), delta * 0.06)
	temperature = lerpf(temperature, lerpf(35.9, 36.6, rest), delta * 0.01)

	# Гипоксия при задержке дыхания.
	if holding_breath:
		spo2 = clampf(spo2 - delta * 15.0 * (1.0 + dread), 48.0, 100.0)
	else:
		spo2 = lerpf(spo2, lerpf(99.0, 92.0, dread), delta * 0.35)

	if spo2 < 88.0:
		apply_stress(delta * 3.0 * (88.0 - spo2) * 0.1, &"hypoxia")

	# Сознание уходит, если мозг не получает кислород.
	if spo2 < 74.0:
		set_consciousness(consciousness - delta * (74.0 - spo2) * 0.02, &"hypoxia")

	_tick_accumulator += delta
	if _tick_accumulator >= 0.1 or _vitals_dirty:
		_tick_accumulator = 0.0
		_vitals_dirty = false
		vitals_changed.emit(vitals())
