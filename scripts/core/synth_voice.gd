class_name SynthVoice
extends RefCounted
## Синтезатор одного звука. Живёт как набор float-сэмплов, из которого потом
## собирается AudioStreamWAV. Ни одного внешнего аудиофайла в проекте нет:
## манжета, кардиомонитор, хруст, кафель — всё считается здесь.
##
## Все методы мутируют `data` на месте и возвращают self — можно писать цепочкой.

var data: PackedFloat32Array
var rate: int


func _init(seconds: float, sample_rate := 44100) -> void:
	rate = sample_rate
	var count := maxi(1, int(seconds * float(sample_rate)))
	data = PackedFloat32Array()
	data.resize(count)
	for i in range(0, count):
		data[i] = 0.0


func length() -> int:
	return data.size()


func duration() -> float:
	return float(data.size()) / float(rate)


# --- Генераторы ---------------------------------------------------------------

func noise(amp := 1.0, seed_value := 0, smoothing := 0.0) -> SynthVoice:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var last := 0.0
	for i in range(0, data.size()):
		var value := rng.randf_range(-1.0, 1.0)
		if smoothing > 0.0:
			last = lerpf(last, value, 1.0 - smoothing)
			value = last
		data[i] += value * amp
	return self


func sine(freq: float, amp := 1.0, phase := 0.0, freq_end := -1.0) -> SynthVoice:
	var end := freq_end if freq_end > 0.0 else freq
	var t := 0.0
	var step := 1.0 / float(rate)
	for i in range(0, data.size()):
		var progress := float(i) / float(maxi(data.size() - 1, 1))
		var f := lerpf(freq, end, progress)
		t += f * step
		data[i] += sin(TAU * t + phase) * amp
	return self


## Импульсный отклик металла: несколько расстроенных гармоник с разным затуханием.
func metal(amp: float, base_freq: float, decay: float, partials := 5, seed_value := 0) -> SynthVoice:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var freqs := PackedFloat32Array()
	var decays := PackedFloat32Array()
	var gains := PackedFloat32Array()
	for i in range(0, partials):
		freqs.append(base_freq * rng.randf_range(0.72, 3.4))
		decays.append(decay * rng.randf_range(0.35, 1.4))
		gains.append(amp * rng.randf_range(0.3, 1.0) / float(i + 1))
	for i in range(0, data.size()):
		var t := float(i) / float(rate)
		var value := 0.0
		for p in range(0, partials):
			value += sin(TAU * freqs[p] * t) * exp(-t / maxf(decays[p], 0.0005)) * gains[p]
		data[i] += value
	return self


## Влажный звук: шумовой всплеск с шероховатой амплитудой и «пузырями».
func wet_burst(amp: float, duration: float, seed_value := 0, pops := 6) -> SynthVoice:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var count := mini(data.size(), int(duration * float(rate)))
	var last := 0.0
	for i in range(0, count):
		var t := float(i) / float(rate)
		var env := exp(-t * 18.0)
		var v := rng.randf_range(-1.0, 1.0)
		last = lerpf(last, v, 0.35) # лёгкая окраска «мяса»
		data[i] += last * amp * env
	for p in range(0, pops):
		var pos := int(rng.randf_range(0.0, float(maxi(count - 1, 1))))
		var len := int(float(rate) * rng.randf_range(0.004, 0.014))
		var pf := rng.randf_range(320.0, 1800.0)
		for i in range(pos, mini(pos + len, data.size())):
			var lt := float(i - pos) / float(rate)
			data[i] += sin(TAU * pf * lt) * exp(-lt * 90.0) * amp * 0.8
	return self


func add_click(amp: float, at_seconds: float, tone := 1400.0, decay := 0.004) -> SynthVoice:
	var start := int(at_seconds * float(rate))
	var len := int(decay * 6.0 * float(rate))
	for i in range(start, mini(start + len, data.size())):
		var t := float(i - start) / float(rate)
		data[i] += (sin(TAU * tone * t) + sin(TAU * tone * 1.73 * t) * 0.5) * exp(-t / decay) * amp
	return self


# --- Огибающие ----------------------------------------------------------------

func env_ad(attack: float, decay: float, curve := 2.0) -> SynthVoice:
	var n := data.size()
	var a := maxi(1, int(attack * float(rate)))
	var d := maxi(1, int(decay * float(rate)))
	for i in range(0, n):
		var env := 1.0
		if i < a:
			env = float(i) / float(a)
		elif i < a + d:
			env = exp(-float(i - a) / float(d) * curve)
		else:
			env = 0.0
		data[i] *= env
	return self


## Атака — ровное удержание — отпускание. sustain задаёт длительность плато
## в секундах; всё, что осталось после плато, уходит в спад.
func env_asr(attack: float, sustain: float, release: float, level := 0.8) -> SynthVoice:
	var n := data.size()
	var a := maxi(1, int(attack * float(rate)))
	var s := maxi(1, int(sustain * float(rate)))
	var r := maxi(1, int(release * float(rate)))
	var hold_end := mini(a + s, n)
	var release_end := mini(hold_end + r, n)
	for i in range(0, n):
		var env := 0.0
		if i < a:
			env = float(i) / float(a)
		elif i < hold_end:
			env = level
		elif i < release_end:
			env = level * (1.0 - float(i - hold_end) / float(maxi(release_end - hold_end, 1)))
		else:
			env = 0.0
		data[i] *= env
	return self


## Ритмическая накачка (манжета тонометра, поршневой насос).
func env_pump(period: float, cycles: int, sharpness := 3.0) -> SynthVoice:
	var n := data.size()
	var period_samples := maxf(period * float(rate), 1.0)
	for i in range(0, n):
		var phase := fposmod(float(i) / period_samples, 1.0)
		var cycle_index := int(float(i) / period_samples)
		if cycle_index >= cycles:
			data[i] = 0.0
			continue
		var pulse := pow(maxf(0.0, 1.0 - phase), sharpness)
		data[i] *= pulse
	return self


## Срезает начало: нужно, чтобы фильтры «прогрелись» до рабочей точки и
## зацикленный слой не начинался с переходного процесса.
func trim_head(seconds: float) -> SynthVoice:
	var cut := int(seconds * float(rate))
	if cut <= 0 or cut >= data.size():
		return self
	var rest := PackedFloat32Array()
	rest.resize(data.size() - cut)
	for i in range(cut, data.size()):
		rest[i - cut] = data[i]
	data = rest
	return self


func fade_edges(ms := 4.0) -> SynthVoice:
	var n := data.size()
	var f := maxi(1, int(float(rate) * ms / 1000.0))
	for i in range(0, mini(f, n)):
		var k := float(i) / float(f)
		data[i] *= k
		data[n - 1 - i] *= k
	return self


# --- Фильтры ------------------------------------------------------------------

func lowpass(cutoff: float, resonance := 0.0) -> SynthVoice:
	var dt := 1.0 / float(rate)
	var rc := 1.0 / (TAU * maxf(cutoff, 1.0))
	var alpha := dt / (rc + dt)
	var previous := 0.0
	var previous_input := 0.0
	for i in range(0, data.size()):
		var x := data[i]
		previous = previous + alpha * (x - previous)
		if resonance > 0.0:
			previous += (x - previous_input) * resonance * alpha
			previous_input = x
		data[i] = previous
	return self


func highpass(cutoff: float) -> SynthVoice:
	var dt := 1.0 / float(rate)
	var rc := 1.0 / (TAU * maxf(cutoff, 1.0))
	var alpha := rc / (rc + dt)
	var previous_out := 0.0
	var previous_in := 0.0
	for i in range(0, data.size()):
		var x := data[i]
		previous_out = alpha * (previous_out + x - previous_in)
		previous_in = x
		data[i] = previous_out
	return self


func bandpass(low: float, high: float) -> SynthVoice:
	highpass(low)
	lowpass(high)
	return self


func saturate(drive := 1.6) -> SynthVoice:
	for i in range(0, data.size()):
		data[i] = tanh(data[i] * drive)
	return self


func normalize(peak := 0.95) -> SynthVoice:
	var max_value := 0.0
	for i in range(0, data.size()):
		max_value = maxf(max_value, absf(data[i]))
	if max_value < 0.00001:
		return self
	var gain := peak / max_value
	for i in range(0, data.size()):
		data[i] *= gain
	return self


# --- Компоновка ---------------------------------------------------------------

func mix_in(other: SynthVoice, at_seconds := 0.0, gain := 1.0) -> SynthVoice:
	var start := int(at_seconds * float(rate))
	for i in range(0, other.data.size()):
		var index := start + i
		if index < 0 or index >= data.size():
			continue
		data[index] += other.data[i] * gain
	return self


## Превращает накопленные сэмплы в поток. loop — зацикливание без щелчка.
func to_stream(loop := false) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	var count := data.size()
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in range(0, count):
		var value := clampf(data[i], -1.0, 1.0)
		bytes.encode_s16(i * 2, int(round(value * 32767.0)))
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = count
	else:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream
