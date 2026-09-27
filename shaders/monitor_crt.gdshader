// MYDRIASIS STUDIO — monitor_crt.gdshader
// ============================================================================
// Экран кардиомонитора. Рисуется целиком в шейдере: кардиограмма, развёртка,
// фосфорное послесвечение, дрожание строк, шум ЭМИ. Никаких текстур и
// SubViewport — один quad, нулевая стоимость на ассеты.
// ============================================================================

shader_type spatial;
render_mode unshaded, depth_draw_opaque, cull_back, shadows_disabled;

group_uniforms Rhythm;
uniform float bpm : hint_range(20.0, 200.0) = 68.0;
uniform float gain : hint_range(0.0, 2.0) = 1.0;
uniform float flatline : hint_range(0.0, 1.0) = 0.0;   // 1 — асистолия
uniform float arrhythmia : hint_range(0.0, 1.0) = 0.0; // рваный ритм
uniform float sweep_speed : hint_range(0.0, 3.0) = 1.15;

group_uniforms Phosphor;
uniform vec3 trace_color : source_color = vec3(0.35, 1.0, 0.62);
uniform vec3 grid_color : source_color = vec3(0.10, 0.42, 0.26);
uniform float glow : hint_range(0.0, 4.0) = 1.4;
uniform float scanline : hint_range(0.0, 1.0) = 0.35;
uniform float noise_amount : hint_range(0.0, 1.0) = 0.12;
uniform float vignette : hint_range(0.0, 1.0) = 0.7;
uniform float dpn : hint_range(0.0, 4.0) = 1.0; // децибелы бодрости: мерцание картинки

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float pulse_gauss(float x, float center, float width, float amp) {
	float d = (x - center) / width;
	return exp(-d * d) * amp;
}

// Форма одного кардиокомплекса на фазе t ∈ [0,1).
float ecg_wave(float t) {
	float v = 0.0;
	v += pulse_gauss(t, 0.14, 0.022, 0.06);          // зубец P
	v += pulse_gauss(t, 0.255, 0.008, -0.14);        // Q
	v += pulse_gauss(t, 0.275, 0.007, 1.00);         // R
	v += pulse_gauss(t, 0.296, 0.010, -0.30);        // S
	v += pulse_gauss(t, 0.44, 0.045, 0.18);          // зубец T
	return v;
}

void fragment() {
	vec2 uv = UV;
	// Экран не идеален: строки дрожат, изображение слегка плывёт.
	float jitter = (hash12(vec2(floor(uv.y * 240.0), floor(TIME * 30.0))) - 0.5) * 0.0015;
	uv.x += jitter;

	float beat_period = 60.0 / max(bpm, 1.0);
	float phase = fract(TIME / beat_period + arrhythmia * sin(TIME * 0.7) * 0.15);

	float ecg = ecg_wave(phase);
	// Дополнительная нестабильность при аритмии.
	if (arrhythmia > 0.001) {
		ecg = mix(ecg, ecg_wave(fract(phase * mix(1.0, 1.9, arrhythmia))), 0.5);
	}
	ecg = mix(ecg, 0.0, flatline);

	// Развёртка: яркая вертикальная полоса бежит слева направо.
	float sweep = fract(TIME * sweep_speed * 0.25);
	float sweep_line = smoothstep(0.02, 0.0, abs(fract(uv.x - sweep) - 0.0));
	sweep_line += smoothstep(0.10, 0.0, abs(fract(uv.x - sweep))) * 0.25;

	// Высота следа в текущем столбце.
	float wave_y = 0.5 + ecg * 0.32 * gain;
	float y_dist = abs(uv.y - wave_y);
	float line = smoothstep(0.006, 0.0, y_dist);

	// Сетка ЭКГ (миллиметровка).
	vec2 grid_uv = uv * vec2(56.0, 30.0);
	vec2 grid_line = abs(fract(grid_uv) - 0.5);
	float grid = smoothstep(0.47, 0.5, max(grid_line.x, grid_line.y)) * 0.5;
	vec2 big = abs(fract(uv * vec2(11.2, 6.0)) - 0.5);
	grid += smoothstep(0.49, 0.5, max(big.x, big.y)) * 0.7;

	// Фосфор: свечение вокруг следа и по развёртке.
	float halo = exp(-y_dist * 55.0) * 0.5;
	vec3 col = vec3(0.0);
	col += trace_color * (line * 2.4 + halo * glow);
	col += trace_color * sweep_line * 0.35;
	col += grid_color * grid * 0.9;

	// Строки, шум, биение яркости.
	float scan = 1.0 - scanline * smoothstep(0.35, 1.0, abs(fract(uv.y * 300.0) - 0.5) * 2.0);
	float grain = (hash12(uv * 421.0 + TIME * 13.0) - 0.5) * noise_amount;
	float bright = (0.94 + 0.06 * sin(TIME * 9.0)) * (1.0 + 0.05 * sin(TIME * 1.7) * dpn);

	col = (col * scan + grain * vec3(0.2, 0.5, 0.35)) * bright;

	// Виньетка панели.
	vec2 c = (uv - 0.5) * vec2(1.0, 1.35);
	col *= mix(1.0, smoothstep(0.85, 0.15, length(c)), vignette);

	// Асистолия: линия выпрямляется и дрожит — самый страшный кадр в игре.
	if (flatline > 0.001) {
		float flat_y = 0.5 + (hash12(vec2(floor(TIME * 60.0), 3.0)) - 0.5) * 0.004;
		float flat_line = smoothstep(0.004, 0.0, abs(uv.y - flat_y));
		col = mix(col, vec3(1.0, 0.32, 0.30) * (flat_line * 2.6 + halo * 0.4), flatline);
	}

	ALBEDO = col;
	EMISSION = col * 1.25;
}
