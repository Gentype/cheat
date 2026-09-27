// MYDRIASIS STUDIO — wet_tile.gdshader
// ============================================================================
// Мокрый кафель реанимационного блока. Уровень «высший»: каждая плитка имеет
// собственный сдвиг и поворот, шов собирает грязь, вода читается как плёнка
// с менiscus-кромкой, потоки идут вниз, пудлы дают зеркальный блик.
// Всё процедурно — детализация не ограничена разрешением текстур.
// ============================================================================

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms Tiling;
uniform vec2 uv_scale = vec2(6.0, 6.0);
uniform vec2 tile_size = vec2(1.0, 1.0);
uniform float grout_width : hint_range(0.0, 0.15) = 0.035;
uniform float tile_variation : hint_range(0.0, 1.0) = 0.55;

group_uniforms Ceramic;
uniform vec3 tile_color : source_color = vec3(0.72, 0.76, 0.74);
uniform vec3 tile_color_alt : source_color = vec3(0.58, 0.63, 0.63);
uniform vec3 grout_color : source_color = vec3(0.26, 0.25, 0.23);
uniform float grout_dirt : hint_range(0.0, 1.0) = 0.7;
uniform float glaze : hint_range(0.0, 1.0) = 0.85;

group_uniforms Wetness;
uniform float wetness : hint_range(0.0, 1.0) = 0.65;
uniform float puddle : hint_range(0.0, 1.0) = 0.45;
uniform float flow : hint_range(0.0, 1.0) = 0.4;      // вода стекает по стене
uniform float wet_roughness : hint_range(0.0, 0.3) = 0.045;
uniform float bump_strength : hint_range(0.0, 6.0) = 1.5;

group_uniforms Dirt;
uniform float stain : hint_range(0.0, 1.0) = 0.45;
uniform vec3 stain_color : source_color = vec3(0.24, 0.20, 0.14);
uniform float rust : hint_range(0.0, 1.0) = 0.15;

varying vec3 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
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
		p *= 2.05;
		amp *= 0.5;
	}
	return sum;
}

// Возвращает: x — маска плитки, y — маска шва, z — случайная вариация плитки.
vec3 tile_field(vec2 uv) {
	vec2 t = uv / tile_size;
	vec2 cell = floor(t);
	vec2 local = fract(t);
	vec2 rnd = hash22(cell);

	// Каждая плитка чуть повёрнута и сдвинута — идеальной сетки не бывает.
	vec2 c = local - 0.5;
	float a = (rnd.x - 0.5) * 0.03 * tile_variation;
	c = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a))) * c;
	local = c + 0.5 + (rnd - 0.5) * 0.02 * tile_variation;

	vec2 edge = min(local, 1.0 - local);
	float dist = min(edge.x / grout_width, edge.y / grout_width);
	float grout = 1.0 - clamp(dist, 0.0, 1.0);
	float tile = 1.0 - step(1.0, clamp(dist, 0.0, 1.0));
	return vec3(tile, grout, rnd.x);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 tf = tile_field(uv);
	float tile_mask = tf.x;
	float grout_mask = tf.y;
	float rnd = tf.z;

	// Шов глубже плоскости плитки — основа микрорельефа.
	float height = tile_mask * 1.0 - grout_mask * 0.65;

	// Крупные неровности заливки и потёки воды.
	float macro = fbm2(uv * 0.08 + 3.0, 3);
	float streak = fbm2(vec2(uv.x * 3.0, uv.y * 0.35 - TIME * 0.05), 4);
	float drip = smoothstep(0.45, 0.85, streak) * flow;

	// Мокрость: где вода есть, шероховатость падает почти до нуля.
	float wet_mask = clamp(wetness * (0.35 + macro * 0.75) + drip * 0.6, 0.0, 1.0);
	float puddle_mask = clamp(smoothstep(0.55, 0.25, abs(macro - 0.5) * 2.0) * puddle, 0.0, 1.0);
	float water = clamp(wet_mask + puddle_mask * 0.7, 0.0, 1.0);

	// Загрязнение шва: грязь живёт именно в стыках.
	float grout_grime = grout_mask * grout_dirt * (0.4 + fbm2(uv * 6.0, 3) * 0.9);
	float stain_mask = smoothstep(0.5, 0.85, fbm2(uv * 0.35 + 17.0, 4)) * stain;
	float rust_mask = smoothstep(0.62, 0.9, fbm2(uv * 1.6 + 61.0, 3)) * rust * grout_mask;

	vec3 ceramic = mix(tile_color, tile_color_alt, rnd * tile_variation);
	vec3 col = mix(ceramic, grout_color, grout_mask);
	col = mix(col, stain_color, stain_mask * 0.7);
	col = mix(col, vec3(0.32, 0.16, 0.07), rust_mask);
	col *= 0.86 + grout_grime * 0.4;
	col *= 0.92 + macro * 0.16;

	// Плёночная вода слегка темнит и насыщает цвет поверхности.
	col = mix(col, col * 0.72, water * 0.35);

	// Микрорельеф: швы + пудлы + потёки + крупная неровность основания.
	float h = height * bump_strength + macro * 0.8 + puddle_mask * 0.5 + drip * 0.35;
	float dx = dFdx(h);
	float dy = dFdy(h);

	float rough = mix(0.55, 0.16, glaze) - water * 0.5;
	rough += grout_grime * 0.35 + stain_mask * 0.12;
	rough = mix(rough, wet_roughness, puddle_mask * 0.85);

	NORMAL_MAP = normalize(vec3(-dx, -dy, 1.0));
	NORMAL_MAP_DEPTH = mix(1.0, 2.4, bump_strength * 0.33);
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.03, 1.0);
	SPECULAR = 0.5 + glaze * 0.35 + water * 0.15;
	METALLIC = 0.0;
	// Мокрый кафель ловит холодный свет блока и отдаёт его обратно.
	EMISSION += mix(vec3(0.0), vec3(0.05, 0.07, 0.08), water * 0.8);
}
