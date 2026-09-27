// MYDRIASIS STUDIO — hands_reveal.gdshader
// ============================================================================
// Руки — единственная «настоящая» плоть в кадре. Они должны быть предельно
// резкими: поры, грязь под ногтями, латексная плёнка, пот, холод.
// Никаких текстур-ассетов: всё считается процедурно, поэтому уровень детализации
// не упирается в разрешение картинки.
// ============================================================================

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms Surface;
uniform vec3 skin_deep : source_color = vec3(0.62, 0.30, 0.26);
uniform vec3 skin_tone : source_color = vec3(0.86, 0.71, 0.63);
uniform vec3 dirt_color : source_color = vec3(0.13, 0.12, 0.10);
uniform float pore_amount : hint_range(0.0, 1.0) = 0.75;
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.55;
uniform float wetness : hint_range(0.0, 1.0) = 0.25;
uniform float latex : hint_range(0.0, 1.0) = 0.0; // 1 — рука в медицинской перчатке

group_uniforms Detail;
uniform float detail_scale : hint_range(1.0, 400.0) = 42.0;
uniform float vein_amount : hint_range(0.0, 1.0) = 0.35;
uniform float rim_strength : hint_range(0.0, 4.0) = 0.85;
uniform vec3 rim_color : source_color = vec3(0.62, 0.78, 0.92);

group_uniforms Vitals;
uniform float tremor : hint_range(0.0, 1.0) = 0.0;
uniform float cold : hint_range(0.0, 1.0) = 0.0; // посинение, замедление крови

varying vec3 world_pos;
varying vec3 world_normal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash12(i.xy + i.z * 71.0);
	float n100 = hash12((i.xy + vec2(1.0, 0.0)) + i.z * 71.0);
	float n010 = hash12((i.xy + vec2(0.0, 1.0)) + i.z * 71.0);
	float n110 = hash12((i.xy + vec2(1.0, 1.0)) + i.z * 71.0);
	float n001 = hash12(i.xy + (i.z + 1.0) * 71.0);
	float n101 = hash12((i.xy + vec2(1.0, 0.0)) + (i.z + 1.0) * 71.0);
	float n011 = hash12((i.xy + vec2(0.0, 1.0)) + (i.z + 1.0) * 71.0);
	float n111 = hash12((i.xy + vec2(1.0, 1.0)) + (i.z + 1.0) * 71.0);
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}

float fbm3(vec3 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		if (i >= octaves) {
			break;
		}
		sum += value_noise(p) * amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return sum;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Тремор: дрожь рук на грани усталости. Смещение микроскопическое, но читается.
	if (tremor > 0.001) {
		float t = TIME * mix(9.0, 26.0, tremor);
		VERTEX += NORMAL * sin(t + VERTEX.z * 40.0) * 0.0009 * tremor
		        + vec3(sin(t * 1.7), cos(t * 1.3), 0.0) * 0.0012 * tremor;
	}
}

void fragment() {
	vec3 p = world_pos;
	float scale = detail_scale;

	// Поры: два масштаба, чтобы не читалось как однородный шум.
	float pores = fbm3(p * scale, 3);
	float micro = fbm3(p * scale * 5.0 + 13.0, 2);

	// Вены — вытянутые структуры вдоль оси предплечья.
	float vein_field = fbm3(vec3(p.x * scale * 0.12, p.y * scale * 0.5, p.z * scale * 0.12), 3);
	float veins = smoothstep(0.52, 0.62, vein_field) * vein_amount;

	// Грязь: прижимается к сгибам и краям (условно — по градиенту нормали).
	float dirt = smoothstep(0.35, 0.75, fbm3(p * scale * 0.35 + 41.0, 3)) * dirt_amount;

	vec3 albedo = mix(skin_tone, skin_deep, pores * 0.55 + micro * 0.15);
	albedo = mix(albedo, skin_deep * 0.55, veins);
	if (latex > 0.001) {
		// Перчатка: холодный латекс поверх кожи, блики мягче, пор не видно.
		vec3 latex_col = vec3(0.80, 0.82, 0.80);
		albedo = mix(albedo, latex_col * (0.85 + 0.15 * micro), latex);
		pores *= 1.0 - latex;
	}
	albedo = mix(albedo, dirt_color, dirt * (1.0 - latex * 0.4));

	// Холод: кровь уходит с периферии — руки синеют.
	albedo = mix(albedo, vec3(0.42, 0.48, 0.60), cold * 0.55);

	// Высотная карта для нормалей через производные — бесплатный микрорельеф.
	float h = pores * 0.6 + micro * 0.4;
	float dx = dFdx(h) * 26.0;
	float dy = dFdy(h) * 26.0;

	// Шероховатость: пот даёт локальный глянец, грязь — матовость.
	float rough = 0.62 - wetness * 0.30 + dirt * 0.22 + pores * 0.06;
	rough = mix(rough, 0.34, latex);

	NORMAL_MAP = normalize(vec3(-dx, -dy, 1.0));
	NORMAL_MAP_DEPTH = 1.0;
	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	SPECULAR = mix(0.5, 0.72, wetness) + latex * 0.15;
	METALLIC = 0.0;

	// Контурный свет: холодная кромка, отделяющая живую руку от пустоты тела.
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.2);
	EMISSION += rim_color * fres * rim_strength * mix(1.0, 0.4, cold);
}
