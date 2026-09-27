extends Node
## AudioDirector — весь звук игры синтезируется процедурно на старте (лениво,
## по первому запросу). Ни одного внешнего сэмпла: звук морга собран из
## физики звука морга — манжета, мотор монитора, влажный хруст, кафель.
##
## Синтез идёт по «рецептам» ниже. Каждый рецепт — цепочка SynthVoice.
## Это даёт три вещи, которых не даёт библиотека сэмплов: вариативность без
## дублей, точное соответствие виталитетам (пульс = темп игры) и нулевой вес.

signal bank_ready(id: StringName)

const BUS_MASTER := "Master"
const BUS_BED := "Bed"
const BUS_BODY := "Body"
const BUS_SFX := "SFX"
const BUS_VOICES := "Voices"

const MAX_2D_PLAYERS := 24
const MAX_3D_PLAYERS := 20

## Готовые потоки: id -> Array[AudioStreamWAV].
var _bank: Dictionary = {}
## Долгие слои: id -> AudioStreamWAV (зацикленные).
var _loops: Dictionary = {}
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _loop_players: Dictionary = {}
var _bus_indices: Dictionary = {}
var _rr_2d := 0
var _rr_3d := 0
var _tension := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_setup_buses()
	GameState.beat.connect(_on_beat)
	GameState.breath_cycle.connect(_on_breath)
	GameState.stress_spike.connect(_on_stress_spike)
	GameState.dread_changed.connect(_on_dread_changed)


# --- Шины ---------------------------------------------------------------------

func _setup_buses() -> void:
	# Повторный вызов (возврат из меню, смена настроек) не должен плодить эффекты.
	if not _bus_indices.is_empty():
		return
	if AudioServer.get_bus_index(BUS_MASTER) == -1:
		AudioServer.add_bus(0)
		AudioServer.set_bus_name(0, BUS_MASTER)
	_bus_indices[BUS_MASTER] = 0

	for bus_name in [BUS_BED, BUS_BODY, BUS_SFX, BUS_VOICES]:
		var index := AudioServer.get_bus_index(bus_name)
		if index == -1:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, BUS_MASTER)
		_bus_indices[bus_name] = index

	# Мастер: лимитер и компрессор — кадр не должен «рвать» на ударе сердца.
	# AudioEffectHardLimiter есть с 4.3, и он заменяет устаревший AudioEffectLimiter.
	var master_index: int = _bus_indices[BUS_MASTER]
	var compressor := AudioEffectCompressor.new()
	compressor.threshold = -14.0
	compressor.ratio = 2.6
	compressor.attack_us = 12000.0
	compressor.release_ms = 220.0
	AudioServer.add_bus_effect(master_index, compressor)
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -1.2
	limiter.pre_gain_db = 0.0
	limiter.soft_clip_db = -1.0
	limiter.soft_clip_ratio = 4.0
	AudioServer.add_bus_effect(master_index, limiter)

	# Палата: реверберация кафеля и металла.
	var bed_index: int = _bus_indices[BUS_BED]
	var hall := AudioEffectReverb.new()
	hall.room_size = 0.78
	hall.damping = 0.55
	hall.wet = 0.32
	hall.dry = 0.85
	hall.spread = 0.9
	AudioServer.add_bus_effect(bed_index, hall)

	var sfx_index: int = _bus_indices[BUS_SFX]
	var room := AudioEffectReverb.new()
	room.room_size = 0.55
	room.damping = 0.68
	room.wet = 0.18
	room.dry = 0.92
	AudioServer.add_bus_effect(sfx_index, room)

	# Тело: тяжёлый компрессор — дыхание и пульс прижаты к голове.
	var body_index: int = _bus_indices[BUS_BODY]
	var body_comp := AudioEffectCompressor.new()
	body_comp.threshold = -20.0
	body_comp.ratio = 3.4
	AudioServer.add_bus_effect(body_index, body_comp)
	var body_lp := AudioEffectLowPassFilter.new()
	body_lp.cutoff_hz = 6200.0
	AudioServer.add_bus_effect(body_index, body_lp)

	# Моно-режим: для игроков с одним рабочим наушником или на динамике.
	var stereo := AudioEffectStereoEnhance.new()
	stereo.stereo_width = 1.0
	stereo.set_meta(&"mono_switch", true)
	AudioServer.add_bus_effect(master_index, stereo)


func set_bus_volume(bus_name: String, linear: float) -> void:
	var index := int(_bus_indices.get(bus_name, 0))
	var db := -80.0 if linear <= 0.001 else linear_to_db(clampf(linear, 0.0, 2.0))
	AudioServer.set_bus_volume_db(index, db)


func set_mono(enabled: bool) -> void:
	var index: int = _bus_indices[BUS_MASTER]
	for effect_index in range(0, AudioServer.get_bus_effect_count(index)):
		var effect := AudioServer.get_bus_effect(index, effect_index)
		if effect is AudioEffectStereoEnhance:
			(effect as AudioEffectStereoEnhance).stereo_width = 0.0 if enabled else 1.0


# --- Банк звуков --------------------------------------------------------------

func has_sound(id: StringName) -> bool:
	return _bank.has(id) or _loops.has(id)


## Пул голосов: берём свободный, иначе самый давний. Никаких новых нод в бою.
func _get_player2d(bus: String) -> AudioStreamPlayer:
	for player in _players_2d:
		if not player.playing:
			player.bus = bus
			return player
	if _players_2d.size() < MAX_2D_PLAYERS:
		var created := AudioStreamPlayer.new()
		created.bus = bus
		add_child(created)
		_players_2d.append(created)
		return created
	_rr_2d = (_rr_2d + 1) % _players_2d.size()
	_players_2d[_rr_2d].bus = bus
	return _players_2d[_rr_2d]


func _get_player3d(bus: String) -> AudioStreamPlayer3D:
	for player in _players_3d:
		if not player.playing:
			player.bus = bus
			return player
	if _players_3d.size() < MAX_3D_PLAYERS:
		var created := AudioStreamPlayer3D.new()
		created.bus = bus
		created.unit_size = 4.0
		created.max_distance = 42.0
		created.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(created)
		_players_3d.append(created)
		return created
	_rr_3d = (_rr_3d + 1) % _players_3d.size()
	_players_3d[_rr_3d].bus = bus
	return _players_3d[_rr_3d]


## Проиграть короткий звук. variations — потоков на выбор, даёт живой повтор.
func play(id: StringName, volume_db := 0.0, pitch := 1.0, bus := BUS_SFX) -> void:
	var variations := _get_variations(id)
	if variations.is_empty():
		return
	var stream: AudioStreamWAV = variations[_rng.randi_range(0, variations.size() - 1)]
	var player := _get_player2d(bus)
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch * _rng.randf_range(0.97, 1.03), 0.05, 4.0)
	player.play()


func play_at(id: StringName, position: Vector3, volume_db := 0.0, pitch := 1.0, bus := BUS_SFX) -> void:
	var variations := _get_variations(id)
	if variations.is_empty():
		return
	var stream: AudioStreamWAV = variations[_rng.randi_range(0, variations.size() - 1)]
	var player := _get_player3d(bus)
	player.global_position = position
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch * _rng.randf_range(0.94, 1.06), 0.05, 4.0)
	player.play()


## Шаги: поверхность решает тембр, громкость — вес и усталость.
func footstep(surface: StringName, position: Vector3, volume_db := -6.0, pitch := 1.0) -> void:
	var id := StringName("step_" + String(surface))
	if not has_sound(id):
		id = &"step_tile"
	play_at(id, position, volume_db, pitch, BUS_SFX)


# --- Зацикленные слои ---------------------------------------------------------

func start_loop(id: StringName, bus := BUS_BED, volume_db := -12.0, pitch := 1.0) -> void:
	if _loop_players.has(id):
		_loop_players[id].volume_db = volume_db
		return
	var stream := _get_loop_stream(id)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.name = "Loop_" + String(id)
	player.stream = stream
	player.bus = bus
	player.volume_db = volume_db
	player.pitch_scale = pitch
	add_child(player)
	player.play()
	_loop_players[id] = player


func stop_loop(id: StringName, fade_time := 1.0) -> void:
	if not _loop_players.has(id):
		return
	var player: AudioStreamPlayer = _loop_players[id]
	_loop_players.erase(id)
	if fade_time <= 0.0:
		player.queue_free()
		return
	var start_db := player.volume_db
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(func(value: float) -> void: player.volume_db = value, start_db, -60.0, fade_time)
	tween.tween_callback(player.queue_free)


func set_loop_volume(id: StringName, volume_db: float) -> void:
	if _loop_players.has(id):
		_loop_players[id].volume_db = volume_db


func is_loop_playing(id: StringName) -> bool:
	return _loop_players.has(id)


# --- Состояние героя влияет на звук -------------------------------------------

## Напряжение 0..1: то, насколько близко тело к отказу.
func set_tension(value: float) -> void:
	_tension = clampf(value, 0.0, 1.0)
	if is_loop_playing(&"tinnitus"):
		set_loop_volume(&"tinnitus", lerpf(-60.0, -22.0, _tension))
	if is_loop_playing(&"blood_rush"):
		set_loop_volume(&"blood_rush", lerpf(-60.0, -19.0, _tension * maxf(_tension, 0.4)))
	if is_loop_playing(&"ward_amb"):
		set_loop_volume(&"ward_amb", lerpf(-16.0, -24.0, _tension))


func _on_beat(_index: int) -> void:
	var bpm := GameState.heart_rate
	# На высоком пульсе сердце слышно громче — это уже не фон, а симптом.
	var loud := clampf((bpm - 80.0) / 90.0, 0.0, 1.0)
	var volume := lerpf(-30.0, -8.0, maxf(loud, _tension))
	play(&"heart_beat", volume, clampf(72.0 / maxf(bpm, 40.0), 0.7, 1.25), BUS_BODY)


func _on_breath(inhale: bool) -> void:
	if GameState.holding_breath:
		return
	var loud := clampf((GameState.heart_rate - 70.0) / 80.0, 0.0, 1.0)
	var volume := lerpf(-32.0, -18.0, maxf(loud, _tension * 0.7))
	play(&"breath_in" if inhale else &"breath_out", volume, 1.0, BUS_BODY)


func _on_stress_spike(amount: float, _reason: StringName) -> void:
	play(&"whoosh", lerpf(-22.0, -8.0, amount), 1.0, BUS_BODY)


func _on_dread_changed(value: float) -> void:
	set_tension(value)
	if value > 0.55 and not is_loop_playing(&"tinnitus"):
		start_loop(&"tinnitus", BUS_BODY, -54.0)


## Приглушение на переходах (шторка, склейка, остановка сердца).
func duck(amount := 0.35, time := 0.6) -> void:
	var master: int = _bus_indices[BUS_MASTER]
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var from := AudioServer.get_bus_volume_db(master)
	tween.tween_method(func(db: float) -> void: AudioServer.set_bus_volume_db(master, db),
		from, linear_to_db(amount), time)


## Полная пересборка: смена настроек, «глухой» звук, выход из игры.
func rebuild() -> void:
	for player in _loop_players.values():
		(player as AudioStreamPlayer).queue_free()
	_loop_players.clear()
	_bank.clear()
	_loops.clear()


## Прогрев банка во время загрузки — чтобы не было микро-фризов в бою.
func prebuild(ids: Array) -> void:
	for id in ids:
		_get_variations(StringName(id))
		await get_tree().process_frame
	bank_ready.emit(&"prebuild_done")


# --- Рецепты синтеза ----------------------------------------------------------

func _get_variations(id: StringName) -> Array:
	if _bank.has(id):
		return _bank[id]
	var variations: Array = []
	match id:
		&"ui_hover":
			variations.append(_r_ui_tick(1800.0, 0.10))
		&"ui_press":
			variations.append(_r_ui_press(false))
			variations.append(_r_ui_press(true))
		&"ui_back":
			variations.append(_r_ui_tick(620.0, 0.16))
		&"heart_beat":
			for i in range(0, 3):
				variations.append(_r_heartbeat(i))
		&"breath_in":
			variations.append(_r_breath(true, 0))
			variations.append(_r_breath(true, 1))
		&"breath_out":
			variations.append(_r_breath(false, 0))
			variations.append(_r_breath(false, 1))
		&"whoosh":
			variations.append(_r_whoosh())
		&"wet_crunch":
			for i in range(0, 3):
				variations.append(_r_wet_crunch(i))
		&"cuff_pump":
			variations.append(_r_cuff())
		&"monitor_beep":
			variations.append(_r_beep())
		&"drip":
			for i in range(0, 4):
				variations.append(_r_drip(i))
		&"door_metal":
			variations.append(_r_door())
		&"drawer":
			var d0 := _r_drawer(3)
			var d1 := _r_drawer(9)
			variations.append(d0)
			variations.append(d1)
		&"glass_tap":
			variations.append(_r_glass())
		&"switch":
			variations.append(_r_switch())
		&"metal_clang":
			variations.append(_r_clang(3))
			variations.append(_r_clang(11))
		&"paper":
			variations.append(_r_paper())
		&"cloth_move":
			variations.append(_r_cloth())
		&"valve":
			variations.append(_r_valve())
		&"impact":
			variations.append(_r_impact())
		&"shock":
			variations.append(_r_shock())
		&"flatline_start":
			variations.append(_r_flatline_start())
		&"step_tile":
			for i in range(0, 5):
				variations.append(_r_step("tile", i))
		&"step_wet":
			for i in range(0, 4):
				variations.append(_r_step("wet", i))
		&"step_cloth":
			for i in range(0, 4):
				variations.append(_r_step("cloth", i))
		&"step_metal":
			for i in range(0, 4):
				variations.append(_r_step("metal", i))
		_:
			# Неизвестный id — тишина вместо падения: звук не должен ломать бит.
			push_warning("AudioDirector: нет рецепта для " + String(id))
	_bank[id] = variations
	return variations


func _get_loop_stream(id: StringName) -> AudioStreamWAV:
	if _loops.has(id):
		return _loops[id]
	var stream: AudioStreamWAV = null
	match id:
		&"ward_amb":
			stream = _r_ward_ambience()
		&"vent_amb":
			stream = _r_vent_ambience()
		&"static":
			stream = _r_static_loop()
		&"drone_low":
			stream = _r_drone()
		&"tinnitus":
			stream = _r_tinnitus()
		&"blood_rush":
			stream = _r_blood_rush()
		&"wheel":
			stream = _r_wheel_loop()
		&"flatline":
			stream = _r_flatline_loop()
		_:
			push_warning("AudioDirector: нет зацикленного слоя " + String(id))
	if stream != null:
		_loops[id] = stream
	return stream


## Частота, укладывающаяся в целое число периодов за длину петли —
## так зацикленные слои не щёлкают на стыке.
func _loop_freq(freq: float, seconds: float) -> float:
	var cycles := maxf(1.0, round(freq * seconds))
	return cycles / seconds


# --- Конкретные рецепты -------------------------------------------------------

func _r_ui_tick(freq: float, seconds: float) -> AudioStreamWAV:
	var voice := SynthVoice.new(seconds)
	voice.sine(freq, 0.5, 0.0, freq * 0.92)
	voice.noise(0.12, 7, 0.2)
	return voice.bandpass(300.0, 7800.0).env_ad(0.0015, seconds * 0.7).normalize(0.5).to_stream()


func _r_ui_press(heavy: bool) -> AudioStreamWAV:
	var voice := SynthVoice.new(0.18 if heavy else 0.12)
	voice.sine(1180.0, 0.5, 0.0, 760.0)
	voice.sine(240.0, 0.35)
	voice.noise(0.25, 21, 0.1)
	return voice.lowpass(5200.0).env_ad(0.002, 0.09).normalize(0.85).to_stream()


func _r_heartbeat(variation: int) -> AudioStreamWAV:
	var voice := SynthVoice.new(0.6)
	# S1 — закрытие клапанов, низкий и глухой; S2 — короче и выше.
	voice.sine(64.0, 0.95, 0.0, 38.0)
	var second := SynthVoice.new(0.5)
	second.sine(78.0, 0.55, 0.0, 52.0)
	voice.mix_in(second, 0.26 + variation * 0.01)
	voice.noise(0.22, 100 + variation, 0.55)
	# Ниже 260 Гц: сердце слышно не как звук, а как давление в груди.
	return voice.lowpass(260.0).env_ad(0.004, 0.42, 3.0).normalize(0.95).to_stream()


func _r_breath(inhale: bool, variation: int) -> AudioStreamWAV:
	var seconds := 0.85 if inhale else 0.95
	var voice := SynthVoice.new(seconds)
	voice.noise(1.0, 300 + variation * 13, 0.0)
	# Свист воздуха в верхних дыхательных путях.
	voice.sine(lerpf(520.0, 780.0, 0.5 if inhale else 0.2) , 0.06)
	var filtered := voice.bandpass(180.0 if inhale else 140.0, 2600.0 if inhale else 1900.0)
	if inhale:
		filtered.env_asr(0.28, 0.15, 0.42, 0.85)
	else:
		filtered.env_asr(0.10, 0.20, 0.65, 0.8)
	return filtered.normalize(0.6).saturate(1.2).to_stream()


func _r_whoosh() -> AudioStreamWAV:
	var voice := SynthVoice.new(1.2)
	voice.noise(1.0, 411, 0.0)
	var second := SynthVoice.new(0.9)
	second.sine(1200.0, 0.08, 0.0, 200.0)
	voice.mix_in(second, 0.05)
	return voice.bandpass(220.0, 3400.0).env_asr(0.12, 0.25, 0.75, 0.9).normalize(0.65).to_stream()


## Влажный хруст — звук, который не должен быть приятным. Он звучит на заставке
## студии и в моменты, когда реальность рвётся: хрящ, плёнка, давление на глаз.
func _r_wet_crunch(seed_value: int) -> AudioStreamWAV:
	var voice := SynthVoice.new(0.9)
	voice.wet_burst(0.9, 0.7, 700 + seed_value * 17, 9)
	# Стеклянный призвук: не мясо, а что-то, что не должно так звучать.
	var glass := SynthVoice.new(0.7)
	glass.sine(2400.0 + seed_value * 120.0, 0.12, 0.0, 900.0)
	voice.mix_in(glass, 0.05, 0.6)
	var result := voice.bandpass(140.0, 6200.0)
	result.env_ad(0.002, 0.55, 2.6)
	return result.saturate(1.2).normalize(0.85).to_stream()


func _r_cuff() -> AudioStreamWAV:
	# Манжета тонометра: поршневой насос гонит воздух в манжету.
	var seconds := 4.4
	var voice := SynthVoice.new(seconds)
	voice.noise(1.0, 909, 0.0)
	voice.metal(0.05, 74.0, 0.25, 4, 5)   # корпус манометра
	voice.bandpass(160.0, 1150.0)
	voice.env_pump(0.52, 8, 2.6)
	var hiss := SynthVoice.new(seconds)
	hiss.noise(0.35, 77, 0.05)
	hiss.bandpass(900.0, 4200.0)
	hiss.env_ad(0.4, 3.6)
	voice.mix_in(hiss, 0.2, 0.5)
	voice.fade_edges(8.0)
	return voice.normalize(0.78).to_stream()


func _r_beep() -> AudioStreamWAV:
	var voice := SynthVoice.new(0.11)
	voice.sine(1046.5, 0.85)
	voice.sine(2093.0, 0.18)
	voice.noise(0.05, 3, 0.4)
	return voice.env_ad(0.001, 0.06, 3.4).normalize(0.7).to_stream()


func _r_drip(variation: int) -> AudioStreamWAV:
	var voice := SynthVoice.new(0.4)
	var start := 1900.0 + variation * 90.0
	voice.sine(start, 0.6, 0.0, start * 0.35)
	voice.noise(0.25, 500 + variation, 0.0)
	var result := voice.bandpass(300.0, 5200.0)
	result.env_ad(0.001, 0.18, 3.0)
	return result.normalize(0.55).to_stream()


func _r_door() -> AudioStreamWAV:
	var voice := SynthVoice.new(1.6)
	voice.metal(0.35, 170.0, 0.75, 8, 64)  # лист металла
	voice.noise(0.5, 64, 0.0)
	var thud := SynthVoice.new(0.4)
	thud.sine(88.0, 0.7, 0.0, 44.0)
	voice.mix_in(thud, 0.02)
	var result := voice.bandpass(90.0, 4200.0)
	result.env_ad(0.004, 1.1, 2.2)
	return result.normalize(0.85).to_stream()


func _r_drawer(seed_value: int) -> AudioStreamWAV:
	var voice := SynthVoice.new(0.85)
	voice.noise(1.0, seed_value, 0.0)
	voice.metal(0.18, 240.0, 0.4, 6, seed_value + 1)
	var result := voice.bandpass(280.0, 3600.0)
	result.env_asr(0.02, 0.55, 0.25, 0.75)
	return result.normalize(0.7).to_stream()


func _r_glass() -> AudioStreamWAV:
	var voice := SynthVoice.new(0.5)
	voice.sine(2680.0, 0.7)
	voice.sine(4020.0, 0.25)
	voice.metal(0.1, 1500.0, 0.18, 4, 8)
	return voice.highpass(700.0).env_ad(0.001, 0.2, 3.2).normalize(0.5).to_stream()


func _r_switch() -> AudioStreamWAV:
	var voice := SynthVoice.new(0.14)
	voice.sine(3000.0, 0.4)
	voice.noise(0.4, 17, 0.1)
	return voice.highpass(900.0).env_ad(0.0008, 0.05).normalize(0.65).to_stream()


func _r_clang(seed_value: int) -> AudioStreamWAV:
	var voice := SynthVoice.new(1.9)
	voice.metal(0.7, 130.0, 1.1, 10, seed_value)
	voice.noise(0.35, seed_value + 4, 0.0)
	var result := voice.bandpass(80.0, 6000.0)
	result.env_ad(0.002, 1.3, 2.0)
	return result.normalize(0.9).to_stream()


func _r_paper() -> AudioStreamWAV:
	var voice := SynthVoice.new(1.1)
	voice.noise(1.0, 231, 0.0)
	var result := voice.bandpass(1200.0, 7000.0)
	result.env_asr(0.03, 0.5, 0.4, 0.6)
	# Хруст бумаги — рваные импульсы.
	for i in range(0, 26):
		var rng := RandomNumberGenerator.new()
		rng.seed = 231 + i
		voice.add_click(rng.randf_range(0.15, 0.5), rng.randf_range(0.02, 0.9),
			rng.randf_range(1200.0, 5200.0), 0.003)
	return voice.bandpass(700.0, 7500.0).normalize(0.55).to_stream()


func _r_cloth() -> AudioStreamWAV:
	var voice := SynthVoice.new(0.9)
	voice.noise(1.0, 55, 0.35)
	var result := voice.bandpass(320.0, 3200.0)
	result.env_asr(0.09, 0.4, 0.4, 0.5)
	return result.normalize(0.4).to_stream()


func _r_valve() -> AudioStreamWAV:
	var voice := SynthVoice.new(1.4)
	voice.noise(0.7, 71, 0.08)
	var hiss := SynthVoice.new(0.9)
	hiss.noise(0.9, 72, 0.0)
	voice.mix_in(hiss.bandpass(1600.0, 8000.0), 0.25, 0.6)
	var result := voice.bandpass(200.0, 6000.0)
	result.env_asr(0.02, 0.5, 0.7, 0.6)
	voice.add_click(0.5, 0.02, 2200.0, 0.006)
	return result.normalize(0.7).to_stream()


func _r_impact() -> AudioStreamWAV:
	var voice := SynthVoice.new(0.8)
	voice.sine(120.0, 1.0, 0.0, 34.0)
	voice.noise(0.6, 88, 0.2)
	var result := voice.lowpass(900.0)
	result.env_ad(0.001, 0.32, 2.6)
	return result.normalize(0.95).to_stream()


func _r_shock() -> AudioStreamWAV:
	# Разряд дефибриллятора: щелчок, удар, гул 50 Гц, звон в ушах.
	var voice := SynthVoice.new(1.6)
	voice.noise(0.8, 303, 0.0)
	voice.sine(50.0, 0.35)
	voice.sine(150.0, 0.2)
	voice.metal(0.25, 420.0, 0.7, 6, 12)
	var envd := voice.bandpass(60.0, 7000.0)
	envd.env_ad(0.001, 1.0, 2.4)
	envd.add_click(1.0, 0.0, 3400.0, 0.01)
	return envd.saturate(1.35).normalize(0.95).to_stream()


func _r_flatline_start() -> AudioStreamWAV:
	var voice := SynthVoice.new(0.5)
	voice.sine(180.0, 0.6, 0.0, 60.0)
	voice.noise(0.3, 12, 0.3)
	return voice.lowpass(1200.0).env_ad(0.002, 0.3).normalize(0.7).to_stream()


func _r_step(surface: String, variation: int) -> AudioStreamWAV:
	var voice := SynthVoice.new(0.42)
	var seed_value := 400 + variation * 7 + surface.length() * 31
	voice.noise(1.0, seed_value, 0.0)
	var seconds_part := SynthVoice.new(0.3)
	match surface:
		"tile":
			voice.noise(0.9, seed_value, 0.0)
			voice.metal(0.12, 900.0, 0.05, 4, seed_value)  # звон плитки
			seconds_part.sine(90.0, 0.5, 0.0, 50.0)          # вес тела
		"wet":
			voice.noise(1.0, seed_value, 0.0)
			voice.metal(0.1, 700.0, 0.06, 4, seed_value)
			var splash := SynthVoice.new(0.3)
			splash.noise(0.8, seed_value + 3, 0.4)
			voice.mix_in(splash.bandpass(600.0, 4000.0), 0.02, 0.7)
			seconds_part.sine(84.0, 0.5, 0.0, 46.0)
		"cloth":
			voice.noise(1.0, seed_value, 0.5)
			seconds_part.sine(70.0, 0.35, 0.0, 40.0)
		"metal":
			voice.noise(0.7, seed_value, 0.0)
			voice.metal(0.4, 260.0, 0.5, 7, seed_value)
			seconds_part.sine(96.0, 0.5, 0.0, 48.0)
		_:
			voice.noise(1.0, seed_value, 0.0)
	voice.mix_in(seconds_part, 0.0, 0.6)
	var result := voice.bandpass(150.0 if surface != "cloth" else 90.0, 4200.0 if surface != "cloth" else 1400.0)
	result.env_ad(0.001, 0.11, 3.6)
	result.fade_edges(2.0)
	return result.normalize(0.5).to_stream()


# --- Зацикленные слои ---------------------------------------------------------

func _r_ward_ambience() -> AudioStreamWAV:
	var seconds := 8.0
	var voice := SynthVoice.new(seconds + 0.5)
	# Гул ламп и трансформатора: 50 Гц и его гармоники, уложенные в петлю.
	voice.sine(_loop_freq(50.0, seconds), 0.16)
	voice.sine(_loop_freq(100.0, seconds), 0.07)
	voice.sine(_loop_freq(150.0, seconds), 0.03)
	# Воздух палаты: широкополосный шум, мягко обрезанный.
	var air := SynthVoice.new(seconds + 0.5)
	air.noise(0.5, 1234, 0.0)
	voice.mix_in(air.bandpass(120.0, 1200.0), 0.0, 0.55)
	# Капель в раковине — строго на равных долях петли, иначе стык слышен.
	for i in range(0, 3):
		var drip := SynthVoice.new(0.35)
		drip.sine(1500.0, 0.5, 0.0, 520.0)
		drip.env_ad(0.001, 0.12, 3.0)
		voice.mix_in(drip, seconds / 3.0 * float(i) + 0.7, 0.5)
	var result := voice.lowpass(3600.0)
	result.trim_head(0.4)
	result.fade_edges(25.0)
	return result.normalize(0.5).to_stream(true)


func _r_vent_ambience() -> AudioStreamWAV:
	var seconds := 7.0
	var voice := SynthVoice.new(seconds + 0.5)
	voice.noise(1.0, 777, 0.15)
	var result := voice.bandpass(90.0, 700.0)
	# Ритм аппарата ИВЛ: вдох-выдох каждые 3.5 с (7 с петли = ровно два цикла).
	for i in range(0, result.length()):
		var t := float(i) / float(result.rate)
		var phase := fposmod(t / 3.5, 1.0)
		var breath := 0.55 + 0.45 * sin(TAU * phase)
		result.data[i] *= breath
	result.trim_head(0.4)
	result.fade_edges(30.0)
	return result.normalize(0.42).to_stream(true)


func _r_static_loop() -> AudioStreamWAV:
	var seconds := 6.0
	var voice := SynthVoice.new(seconds)
	voice.noise(1.0, 4242, 0.0)
	var result := voice.lowpass(5200.0)
	result.highpass(180.0)
	result.fade_edges(20.0)
	return result.normalize(0.35).to_stream(true)


func _r_drone() -> AudioStreamWAV:
	var seconds := 10.0
	var voice := SynthVoice.new(seconds)
	voice.sine(_loop_freq(41.0, seconds), 0.5)
	voice.sine(_loop_freq(41.7, seconds), 0.42)  # биения — «дыхание» тона
	voice.sine(_loop_freq(61.5, seconds), 0.22)
	voice.sine(_loop_freq(123.0, seconds), 0.08)
	var grit := SynthVoice.new(seconds)
	grit.noise(0.25, 991, 0.6)
	voice.mix_in(grit.bandpass(200.0, 1400.0), 0.0, 0.35)
	voice.fade_edges(40.0)
	return voice.normalize(0.55).to_stream(true)


func _r_tinnitus() -> AudioStreamWAV:
	var seconds := 5.0
	var voice := SynthVoice.new(seconds)
	voice.sine(_loop_freq(5200.0, seconds), 0.35)
	voice.sine(_loop_freq(7350.0, seconds), 0.18)
	# Медленная амплитудная модуляция, уложенная в петлю.
	for i in range(0, voice.length()):
		var t := float(i) / float(voice.rate)
		voice.data[i] *= 0.65 + 0.35 * sin(TAU * t / seconds * 2.0)
	voice.fade_edges(20.0)
	return voice.normalize(0.45).to_stream(true)


func _r_blood_rush() -> AudioStreamWAV:
	var seconds := 6.0
	var voice := SynthVoice.new(seconds)
	voice.noise(1.0, 313, 0.25)
	var result := voice.lowpass(340.0)
	# Пульсация на 72 уд/мин, уложенная в длину петли.
	var beats := roundf(seconds * 72.0 / 60.0)
	for i in range(0, result.length()):
		var t := float(i) / float(result.rate)
		var phase := fposmod(t * (beats / seconds), 1.0)
		var pulse := exp(-phase * 5.0)
		result.data[i] *= 0.3 + 0.7 * pulse
	result.fade_edges(25.0)
	return result.normalize(0.7).to_stream(true)


func _r_wheel_loop() -> AudioStreamWAV:
	var seconds := 2.4
	var voice := SynthVoice.new(seconds)
	voice.noise(0.5, 202, 0.3)
	voice.metal(0.35, 190.0, 0.12, 9, 5)
	var result := voice.bandpass(240.0, 4800.0)
	for i in range(0, result.length()):
		var t := float(i) / float(result.rate)
		result.data[i] *= 0.5 + 0.5 * sin(TAU * t / seconds * 6.0)
	result.fade_edges(12.0)
	return result.normalize(0.5).to_stream(true)


func _r_flatline_loop() -> AudioStreamWAV:
	var seconds := 2.0
	var voice := SynthVoice.new(seconds)
	voice.sine(_loop_freq(1046.5, seconds), 0.8)
	voice.noise(0.02, 60, 0.0)
	voice.fade_edges(10.0)
	return voice.normalize(0.6).to_stream(true)
