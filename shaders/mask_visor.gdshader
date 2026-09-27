// MYDRIASIS STUDIO — mask_visor.gdshader
// ============================================================================
// Визор маски. Единственное место, где игрок смотрит на мир «через себя».
// Стекло не идеальное: оно преломляет фон (включая блюр-дыру тела), собирает
// конденсат изнутри и грязь снаружи, ведёт себя как толстая линза.
//
// Это transparent-материал с высоким render_priority: он рисуется ПОСЛЕ дыры
// тела, поэтому преломляет уже размытый фон — рядом стоят резкое стекло и
// пустота, и разница между ними читается как присутствие человека.
// ============================================================================

shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

group_uniforms Glass;
uniform float refraction : hint_range(0.0, 4.0) = 0.75;      // сила преломления
uniform float thickness : hint_range(0.0, 3.0) = 1.0;        // «толщина» линзы
uniform float chromatic : hint_range(0.0, 3.0) = 0.55;
uniform float tint_density : hint_range(0.0, 1.0) = 0.30;
uniform vec3 tint : source_color = vec3(0.74, 0.82, 0.86);

group_uniforms Fouling;
uniform float condensation : hint_range(0.0, 1.0) = 0.45; // конденсат ИЗНУТРИ
uniform float outer_grime : hint_range(0.0, 1.0) = 0.55;  // грязь и разводы СНАРУЖИ
uniform float droplets : hint_range(0.0, 1.0) = 0.35;     // капли, ползущие по стеклу
uniform float scratches : hint_range(0.0, 1.0) = 0.30;

group_uniforms Reveal;
// Затемнение по периферии визора — «туннель» страха.
uniform float tunnel : hint_range(0.0, 1.0) = 0.35;
uniform float breath_fog = 0.0; // 0..1 от дыхания, нарастает и спадает

varying vec3 world_pos;
varying vec3 world_normal;
varying vec2 mask_uv;

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
	for (int i = 0; i < 5; i++) {
		if (i >= octaves) {
			break;
		}
		sum += value_noise2(p) * amp;
		p *= 2.07;
		amp *= 0.5;
	}
	return sum;
}

// Капля: круг с хвостом, ползущий вниз.
float drop_layer(vec2 uv, float t, float density) {
	float acc = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float seed = hash12(vec2(fi * 7.13, 3.7));
		if (seed > density) {
			continue;
		}
		float speed = mix(0.006, 0.035, hash12(vec2(fi, 9.1)));
		float y = fract(seed * 31.0 + t * speed);
		vec2 c = vec2(hash12(vec2(fi, 1.3)), 1.0 - y);
		float r = mix(0.012, 0.036, hash12(vec2(fi, 5.5)));
		float d = length((uv - c) * vec2(1.0, 0.72));
		float head = smoothstep(r, r * 0.35, d);
		float trail = smoothstep(0.5, 0.0, abs(uv.x - c.x) * 22.0)
		            * smoothstep(1.0, 0.6, uv.y - c.y)
		            * smoothstep(c.y - 0.5, c.y - 0.05, uv.y);
		acc += head + trail * 0.25;
	}
	return clamp(acc, 0.0, 1.0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	mask_uv = UV;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);

	// Грязь и конденсат управляют локальной кривизной стекла.
	float cond = fbm2(mask_uv * 26.0 + vec2(0.0, TIME * 0.01), 3) * condensation;
	float grime = fbm2(mask_uv * 11.0 + 5.0, 4) * outer_grime;
	float drops = drop_layer(mask_uv, TIME * 0.05, droplets);
	float scr = smoothstep(0.55, 0.75, fbm2(mask_uv * vec2(140.0, 8.0), 2)) * scratches;

	float fog = clamp(breath_fog * 1.2 + cond, 0.0, 1.0);

	// Локальная кривизна: капля работает как микро-линза.
	float lens = drops * 0.6 + fog * 0.35 + scr * 0.1;
	vec2 grad = vec2(
		fbm2(mask_uv * 40.0 + 7.0, 2) - fbm2(mask_uv * 40.0 + vec2(0.01, 0.0) + 7.0, 2),
		fbm2(mask_uv * 40.0 + 7.0, 2) - fbm2(mask_uv * 40.0 + vec2(0.0, 0.01) + 7.0, 2)
	);

	vec2 offset = (grad * (thickness * 40.0) + vec2(0.0, lens * 0.02)) * refraction * 0.01;
	offset *= mix(1.0, 1.6, fres);

	// Хроматика толстого стекла.
	vec2 ca = offset * chromatic * 0.5;
	float r = texture(screen_texture, uv + offset + ca).r;
	float g = texture(screen_texture, uv + offset).g;
	float b = texture(screen_texture, uv + offset - ca).b;
	vec3 seen = vec3(r, g, b);

	// Грязь вычитает свет, конденсат его рассеивает.
	vec3 milky = vec3(0.80, 0.84, 0.87);
	seen = mix(seen, seen * tint, tint_density * (0.4 + fres));
	seen = mix(seen, seen * 0.55 + milky * 0.25, fog * 0.35 + grime * 0.18);
	seen += milky * drops * 0.10;

	// Блик по кромке стекла — отделяет визор от провала тела.
	seen += vec3(0.85, 0.92, 1.0) * pow(fres, 1.6) * 0.35;

	// Туннель: края визора уходят в темноту.
	float radial = length(mask_uv - vec2(0.5)) * 1.42;
	seen *= mix(1.0, smoothstep(1.0, 0.35, radial), tunnel);

	ALBEDO = seen;
	ALPHA = clamp(0.92 + fres * 0.08, 0.0, 1.0);
}
