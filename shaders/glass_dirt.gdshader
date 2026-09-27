// MYDRIASIS STUDIO — glass_dirt.gdshader
// ============================================================================
// Стекло блока: смотровое окно, дверь, экран, ампулы. Преломляет уже собранный
// кадр (в том числе блюр вместо тела), собирает разводы, отпечатки, следы
// перчаток, изнутри — конденсат. Толщина и грязь управляются раздельно.
// ============================================================================

shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded, shadows_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

group_uniforms Glass;
uniform float refraction : hint_range(0.0, 4.0) = 0.6;
uniform float chromatic : hint_range(0.0, 3.0) = 0.4;
uniform vec3 tint : source_color = vec3(0.70, 0.78, 0.82);
uniform float tint_density : hint_range(0.0, 1.0) = 0.22;
uniform float frost : hint_range(0.0, 1.0) = 0.25;      // матовость (морг, пар)

group_uniforms Fouling;
uniform float grime : hint_range(0.0, 1.0) = 0.6;        // разводы и налёт
uniform float fingerprints : hint_range(0.0, 1.0) = 0.5; // следы перчаток
uniform float runs : hint_range(0.0, 1.0) = 0.45;        // вертикальные потёки
uniform float chips : hint_range(0.0, 1.0) = 0.25;       // сколы и царапины

group_uniforms Edge;
uniform float fresnel_boost : hint_range(0.0, 3.0) = 1.1;
uniform float edge_tint_amount : hint_range(0.0, 1.0) = 0.5;

varying vec2 glass_uv;
varying vec3 world_normal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2(vec2 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 6; i++) {
		if (i >= octaves) {
			break;
		}
		sum += value_noise2(p) * amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return sum;
}

void vertex() {
	glass_uv = UV;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.2);

	// Слой 1: разводы от тряпки — вытянутые по диагонали.
	float smear = fbm2(vec2(glass_uv.x * 1.4 + glass_uv.y * 0.9, glass_uv.y * 5.0), 4) * grime;
	// Слой 2: вертикальные потёки (жидкость сохла сверху вниз).
	float run = smoothstep(0.35, 0.8, fbm2(vec2(glass_uv.x * 90.0, glass_uv.y * 3.5), 3)) * runs;
	// Слой 3: отпечатки перчаток — локальные пятна с более резкой кромкой.
	vec2 fp_uv = glass_uv * 5.0;
	vec2 fp_cell = floor(fp_uv);
	float fp_rnd = hash12(fp_cell);
	float fp = 0.0;
	if (fp_rnd > 1.0 - fingerprints * 0.75) {
		vec2 c = fract(fp_uv) - 0.5;
		fp = smoothstep(0.45, 0.16, length(c * vec2(0.7, 1.25)));
		fp *= 0.7 + 0.3 * fbm2(glass_uv * 120.0, 2);
	}
	// Слой 4: сколы — тонкие яркие линии.
	float chip = smoothstep(0.72, 0.9, fbm2(glass_uv * vec2(220.0, 30.0), 2)) * chips;

	float fouling = clamp(smear + run * 0.8 + fp + chip * 0.6, 0.0, 1.4);

	// Смещение выборки кадра: грязь и мороз искажают изображение.
	vec2 grad = vec2(
		fbm2(glass_uv * 24.0, 2) - fbm2(glass_uv * 24.0 + vec2(0.01, 0.0), 2),
		fbm2(glass_uv * 24.0, 2) - fbm2(glass_uv * 24.0 + vec2(0.0, 0.01), 2)
	);
	vec2 offset = grad * refraction * 0.02 * (1.0 + fouling * 0.6);
	offset *= mix(1.0, 1.7, fres);
	vec2 ca = offset * chromatic * 0.5;

	float r = texture(screen_texture, uv + offset + ca).r;
	float g = texture(screen_texture, uv + offset).g;
	float b = texture(screen_texture, uv + offset - ca).b;
	vec3 seen = vec3(r, g, b);

	// Мороз/пар: рассеивание в белое, сильнее к краям стекла.
	vec3 frost_col = vec3(0.82, 0.86, 0.88);
	seen = mix(seen, seen * 0.6 + frost_col * 0.35, frost * (0.35 + fres * 0.5));

	// Загрязнение вычитает свет, сколы его собирают.
	seen = mix(seen, seen * 0.62, clamp(fouling * 0.5, 0.0, 0.85));
	seen += frost_col * chip * 0.25;
	seen *= mix(vec3(1.0), tint, tint_density);

	// Кромка стекла всегда ярче — физически верный признак толстой линзы.
	seen += tint * pow(fres, 1.4) * fresnel_boost * edge_tint_amount;

	ALBEDO = seen;
	ALPHA = clamp(0.20 + fres * 0.75 + frost * 0.15 + fouling * 0.25, 0.0, 1.0);
}
