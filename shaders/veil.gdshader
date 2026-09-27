// MYDRIASIS STUDIO — veil.gdshader
// ============================================================================
// «Вуаль» — слой расстроенного восприятия. Накладывается между кадром и HUD.
// Работает как нарастающая шкала: от лёгкой рассинхронии до полного распада
// картинки. Управляется одним параметром dread и производными от виталитета.
// ============================================================================

shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

uniform float dread : hint_range(0.0, 1.0) = 0.0;        // общая шкала распада
uniform float doubling : hint_range(0.0, 1.0) = 0.0;     // двоение
uniform float tunnel : hint_range(0.0, 1.0) = 0.0;       // сужение поля
uniform float static_amount : hint_range(0.0, 1.0) = 0.0; // помехи
uniform float rings : hint_range(0.0, 1.0) = 0.0;        // волны от пульса
uniform float desaturate : hint_range(0.0, 1.0) = 0.0;
uniform float breath : hint_range(-1.0, 1.0) = 0.0;      // -1 выдох, +1 вдох
uniform vec3 veil_color : source_color = vec3(0.72, 0.84, 0.92);
uniform float flash : hint_range(0.0, 1.0) = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Двоение: второй глаз не сходится с первым.
	float d = doubling * 0.006 * (1.0 + dread);
	vec3 a = texture(screen_tex, uv).rgb;
	vec3 b = texture(screen_tex, uv + vec2(d, d * 0.35)).rgb;
	vec3 col = mix(a, mix(a, b, 0.5), clamp(doubling * 1.6, 0.0, 1.0));

	// Волны от пульса: кадр расходится кругами от центра взгляда.
	if (rings > 0.001) {
		vec2 c = (uv - 0.5) * vec2(1.0, 1.02);
		float r = length(c);
		float w = sin(r * 26.0 - TIME * 4.2) * rings * 0.0025 * (1.0 - r);
		col = texture(screen_tex, uv + normalize(c + 1e-5) * w).rgb * 0.75 + col * 0.25;
	}

	// Дыхание: лёгкое затемнение на выдохе.
	col *= 1.0 + breath * 0.05;

	// Обесцвечивание периферии: зрение уходит от краёв к центру.
	float vig = length((uv - 0.5) * vec2(1.0, 1.06)) * 1.4;
	if (desaturate > 0.001) {
		float lum = dot(col, vec3(0.299, 0.587, 0.114));
		float edge = smoothstep(0.35, 1.1, vig);
		col = mix(col, vec3(lum) * 0.92, desaturate * edge);
	}

	// Туннель: края кадра съедаются темнотой.
	col *= mix(1.0, smoothstep(1.25, 0.30 - tunnel * 0.25, vig), tunnel * 0.9);

	// Шум помех: строки и точки, как на сломанном мониторе.
	if (static_amount > 0.001) {
		float line = hash12(vec2(floor(uv.y * 420.0), floor(TIME * 24.0)));
		float dots = hash12(uv * vec2(1280.0, 720.0) + TIME * 31.0);
		float s = (line - 0.5) * 0.5 + (dots - 0.5) * 0.5;
		col += s * static_amount * 0.22;
	}

	// Вуаль: обесцвеченный холодный туман поверх, сильнее в тенях.
	float lum2 = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, mix(veil_color, col, 0.45), dread * (1.0 - lum2) * 0.5);

	if (flash > 0.001) {
		col = mix(col, vec3(1.0), clamp(flash, 0.0, 1.0) * 0.85);
	}

	// Сохраняем альфу 1 — слой полностью закрывает кадр, но только там, где
	// реально что-то изменилось (прозрачность задаётся значением dread).
	float alpha = clamp(dread * 0.9 + doubling * 0.5 + tunnel * 0.6 + static_amount, 0.0, 1.0);
	COLOR = vec4(col, alpha);
}
