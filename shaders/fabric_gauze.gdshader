// MYDRIASIS STUDIO — fabric_gauze.gdshader
// ============================================================================
// Медицинская ткань: простыни, марля, халаты, шторы. Плетение считается
// процедурно, складки дают мягкую нормаль, биологические следы — только как
// пятна, без «дешёвого хоррор-декора».
// ============================================================================

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms Weave;
uniform vec2 uv_scale = vec2(8.0, 8.0);
uniform float thread_density : hint_range(20.0, 600.0) = 180.0;
uniform float weave_bump : hint_range(0.0, 3.0) = 1.0;
uniform float fuzz : hint_range(0.0, 1.0) = 0.6;   // ворс на кромке

group_uniforms Look;
uniform vec3 base_color : source_color = vec3(0.78, 0.79, 0.76);
uniform vec3 shadow_color : source_color = vec3(0.44, 0.46, 0.46);
uniform vec3 stain_color : source_color = vec3(0.36, 0.22, 0.16);
uniform float stain_amount : hint_range(0.0, 1.0) = 0.3;
uniform float soak : hint_range(0.0, 1.0) = 0.25;   // мокрое пятно
uniform float transparency : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;
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
		p *= 2.02;
		amp *= 0.5;
	}
	return sum;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV * uv_scale;

	// Плетение: основа + уток, со сдвигом ворса.
	vec2 weave = sin(uv * thread_density * 3.14159);
	float warp = weave.x * 0.5 + 0.5;
	float weft = weave.y * 0.5 + 0.5;
	float cloth = mix(warp, weft, 0.5) * 0.6 + warp * weft * 0.4;

	// Мягкие неровности ткани (посадка, складки, потёртость).
	float soft = fbm2(uv * 0.35, 4);
	float grain = fbm2(uv * 2.2 + 9.0, 3);

	// Пятна: органические, с рваной кромкой и лёгким «выцветанием» ядра.
	float stain_field = fbm2(uv * 0.55 + 31.0, 4);
	float stains = smoothstep(0.58, 0.78, stain_field) * stain_amount;

	// Промокание: ядро пятна темнее и глянцевее.
	float wet_core = smoothstep(0.66, 0.86, stain_field) * soak;

	vec3 col = mix(base_color, shadow_color, (1.0 - cloth) * 0.45 + soft * 0.25);
	col = mix(col, stain_color, stains * 0.8);
	col *= 0.95 + grain * 0.1;

	float h = cloth * weave_bump * 0.4 + soft * 0.5 + grain * 0.2;
	float dx = dFdx(h);
	float dy = dFdy(h);

	float rough = 0.88 - wet_core * 0.5 - soak * 0.1;
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);

	NORMAL_MAP = normalize(vec3(-dx, -dy, 1.0));
	NORMAL_MAP_DEPTH = 0.8;
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.06, 1.0);
	SPECULAR = 0.22 + wet_core * 0.4;
	METALLIC = 0.0;
	// Ворс светится на кромке — марля и халат «пушатся» против света.
	EMISSION += base_color * fres * fuzz * 0.22;
	if (transparency > 0.001) {
		ALPHA = clamp(transparency * (1.0 - cloth * 0.35), 0.0, 1.0);
	}
}
