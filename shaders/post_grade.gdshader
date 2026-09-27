// MYDRIASIS STUDIO — post_grade.gdshader
// ============================================================================
// Финальный грейд кадра. Работает как «глаз»: экспозиция, зрачок, давление,
// зерно, гало, хроматика, виньетка. Все параметры — не украшение, а шкала
// состояния героя, ими управляет GameState каждый кадр.
//
// Вешается на ColorRect (anchors full rect) внутри CanvasLayer с максимальным
// layer, поверх 3D. Читает screen texture, поэтому рисуется последним.
// ============================================================================

shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

group_uniforms Exposure;
uniform float exposure : hint_range(0.0, 3.0) = 1.0;
uniform float contrast : hint_range(0.5, 2.0) = 1.08;
uniform float lift : hint_range(-0.2, 0.2) = -0.015;
uniform float gamma : hint_range(0.5, 2.0) = 1.02;
uniform float temperature : hint_range(-1.0, 1.0) = -0.12;
uniform float tint_amount : hint_range(-1.0, 1.0) = 0.03;

group_uniforms Color;
uniform float saturation : hint_range(0.0, 2.0) = 0.82;
uniform float red_selective : hint_range(0.0, 1.0) = 0.25; // кровь не выцветает
uniform vec3 shadow_tint : source_color = vec3(0.62, 0.68, 0.78);
uniform vec3 highlight_tint : source_color = vec3(1.0, 0.97, 0.92);

group_uniforms Pupil;
// 0 — зрачок сужен (смят, собран), 1 — предельный мидриаз (запредельная кома).
uniform float pupil : hint_range(0.0, 1.0) = 0.25;
uniform float pupil_irregularity : hint_range(0.0, 1.0) = 0.0;
uniform float pupil_bloom : hint_range(0.0, 1.0) = 0.0;
uniform float pressure : hint_range(0.0, 1.0) = 0.0;
uniform float heartbeat : hint_range(0.0, 1.0) = 0.0;

group_uniforms Optics;
uniform float glow : hint_range(0.0, 2.0) = 0.55;
uniform float chromatic : hint_range(0.0, 2.0) = 0.35;
uniform float vignette : hint_range(0.0, 1.5) = 0.7;
uniform float grain : hint_range(0.0, 1.0) = 0.35;
uniform float lens_dirt : hint_range(0.0, 1.0) = 0.25;
uniform float flash : hint_range(0.0, 1.0) = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 safe_sample(vec2 uv) {
	return texture(screen_tex, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - 0.5;

	// Давление: кадр «плывёт», как будто кровь не доходит до глаз.
	if (pressure > 0.001) {
		float t = TIME * 1.3;
		uv += vec2(sin(t + uv.y * 9.0), cos(t * 0.9 + uv.x * 7.0)) * 0.0016 * pressure;
	}
	// Пульс: микро-зум на систоле.
	float beat = heartbeat * 0.004;
	uv = (uv - 0.5) * (1.0 + beat) + 0.5;

	vec3 col;
	// Хроматика: каналы расходятся от центра линзы.
	float ca = chromatic * 0.0025 * (0.35 + length(centered) * 2.2);
	col.r = safe_sample(uv + centered * ca).r;
	col.g = safe_sample(uv).g;
	col.b = safe_sample(uv - centered * ca).b;

	// Гало: дешёвый двухмасштабный блюм по кадру.
	if (glow > 0.001) {
		vec3 glow_acc = vec3(0.0);
		float sp = 0.004;
		glow_acc += safe_sample(uv + vec2(sp, 0.0));
		glow_acc += safe_sample(uv - vec2(sp, 0.0));
		glow_acc += safe_sample(uv + vec2(0.0, sp));
		glow_acc += safe_sample(uv - vec2(0.0, sp));
		glow_acc += safe_sample(uv + vec2(sp * 2.6, sp * 2.6));
		glow_acc += safe_sample(uv - vec2(sp * 2.6, sp * 2.6));
		glow_acc += safe_sample(uv + vec2(sp * 2.6, -sp * 2.6));
		glow_acc += safe_sample(uv - vec2(sp * 2.6, -sp * 2.6));
		glow_acc /= 8.0;
		float lum = dot(glow_acc, vec3(0.299, 0.587, 0.114));
		col += glow_acc * pow(max(lum - 0.55, 0.0), 1.35) * glow * 1.8;
	}

	// Оптика: пыль и разводы на «линзе» камеры.
	if (lens_dirt > 0.001) {
		float dirt = texture(screen_tex, uv * 0.5 + vec2(0.13, 0.71)).g;
		float dirt2 = texture(screen_tex, uv * 0.17 + vec2(0.61, 0.22)).r;
		dirt = smoothstep(0.72, 0.98, dirt * dirt2 * 1.4);
		col += dirt * lens_dirt * 0.10 * (1.0 - length(centered));
	}

	// Экспозиция и контраст.
	col *= exposure;
	col = (col - 0.5) * contrast + 0.5;
	col += lift;

	// Грейд: тени холодные, свет тёплый — «морг при лампах дневного света».
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col *= mix(shadow_tint, highlight_tint, smoothstep(0.05, 0.75, lum));

	// Насыщенность с сохранением красного: кровь всегда остаётся красной.
	if (saturation < 0.999 || red_selective > 0.001) {
		float lum2 = dot(col, vec3(0.299, 0.587, 0.114));
		vec3 desat = vec3(lum2);
		vec3 graded = mix(desat, col, saturation);
		float redness = clamp(col.r - max(col.g, col.b), 0.0, 1.0);
		graded = mix(graded, mix(graded, col, 1.0), redness * red_selective);
		col = graded;
	}

	// Баланс белого.
	col.r *= 1.0 + temperature * 0.12;
	col.b *= 1.0 - temperature * 0.12;
	col.g *= 1.0 + tint_amount * 0.10;

	col = pow(max(col, vec3(0.0)), vec3(gamma));

	// Мидриаз как управляемый зрачок кадра.
	if (pupil > 0.001) {
		float r = length(centered * vec2(1.0, 1.06));
		// Неровность зрачка: реакция отсутствует, кромка дрожит.
		float ang = atan(centered.y, centered.x);
		float irr = 1.0 + pupil_irregularity * 0.34 * sin(ang * 3.0 + TIME * 1.4)
		              + pupil_irregularity * 0.22 * sin(ang * 7.0 - TIME * 2.1);
		float radius = (0.30 + pupil * 0.62) * irr;
		float mask = smoothstep(radius - 0.22, radius + 0.16, r);
		col = mix(col, mix(col, vec3(dot(col, vec3(0.299, 0.587, 0.114))) * 0.45, 0.6), mask);
		// Хроматическая ирис-кайма на границе зрачка.
		float ring = smoothstep(0.06, 0.0, abs(r - radius));
		col += vec3(0.55, 0.72, 0.95) * ring * pupil * 0.25;
	}

	// Виньетка — сужение поля зрения.
	float vig = length(centered * vec2(1.0, 1.05)) * 1.45;
	col *= mix(1.0, smoothstep(1.15, 0.25, vig), vignette);

	// Зерно: плёнка 800 ASA, всегда чуть живая.
	float g = hash12(uv * vec2(1920.0, 1080.0) * 0.5 + fract(TIME) * 733.0) - 0.5;
	float lum_now = dot(col, vec3(0.299, 0.587, 0.114));
	col += g * grain * mix(0.075, 0.028, lum_now);

	// Вспышка (переходы, шок, дефибрилляция).
	if (flash > 0.001) {
		col = mix(col, vec3(1.0), clamp(flash, 0.0, 1.0));
	}
	// Расширенный зрачок заливает кадр светом — «предельный мидриаз».
	if (pupil_bloom > 0.001) {
		col = mix(col, col + vec3(0.35, 0.38, 0.42), pupil_bloom * (0.3 + length(centered)));
	}

	COLOR = vec4(col, 1.0);
}
