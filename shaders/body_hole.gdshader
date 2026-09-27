// MYDRIASIS STUDIO — body_hole.gdshader
// ============================================================================
// Тело главного героя НЕ существует как изображение.
// Вместо тела — оптическая дыра: фон за телом размывается по диску рассеяния
// и подставляется в силуэт. Никакой модели человека, никакой фотографии,
// никакой генерации персонажа в кадре. Видны только руки и маска.
//
// Технически: материал идёт в transparent-пасс (используется ALPHA), поэтому
// он гарантированно рисуется ПОСЛЕ всей непрозрачной геометрии и может
// безопасно читать screen texture. Глубина не пишется, но тестируется — стена
// между камерой и героем корректно перекрывает дыру, а руки/маска (opaque)
// всегда остаются резкими и оказываются поверх.
// ============================================================================

shader_type spatial;
render_mode blend_mix, depth_draw_never, shadows_disabled, specular_disabled, cull_back, unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

group_uniforms Aperture;
// Радиус диска рассеяния в пикселях экрана.
uniform float blur_radius : hint_range(0.0, 96.0) = 22.0;
// Число выборок в диске. Индекс качества: 8 / 16 / 24 / 32.
uniform int blur_samples : hint_range(4, 32, 1) = 24;
// «Живость» размытия — лёгкое дрожание диска, будто взгляд не держит фокус.
uniform float living : hint_range(0.0, 1.0) = 0.25;
// Хроматическое расслоение на краях диска (стекло, а не воздух).
uniform float chromatic : hint_range(0.0, 1.0) = 0.30;
// Насколько фон вокруг дыры темнее — свет «застревает» там, где должно быть тело.
uniform float absorption : hint_range(0.0, 1.0) = 0.42;
uniform vec3 absorption_tint : source_color = vec3(0.72, 0.78, 0.84);

group_uniforms Silhouette;
// Мягкость кромки дыры.
uniform float edge_softness : hint_range(0.0, 1.0) = 0.55;
// Насколько кромка «толстеет» на скользящих углах — эффект мениска/линзы.
uniform float meniscus : hint_range(0.0, 2.0) = 0.75;
// Прижимать выборки к фону, за которым стоит тело (защита от размазывания переднего плана).
uniform float depth_reject : hint_range(0.0, 1.0) = 1.0;
uniform float depth_bias : hint_range(0.0, 2.0) = 0.05;
// Общая покрываемость (0 — тело полностью прозрачно исчезает, 1 — виден блюр).
uniform float coverage : hint_range(0.0, 1.0) = 1.0;

group_uniforms Vitals;
// 0..1 — удар сердца. Расширяет диск на пике, дыра «дышит».
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
// 0 — норма, 1 — давление упало, всё плывёт.
uniform float pressure : hint_range(0.0, 1.0) = 0.0;

varying float own_view_depth;
varying vec3 world_normal_v;

const float GOLDEN_ANGLE = 2.39996323;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Линеаризация глубины буфера (Godot 4 storage: reversed depth, ndc прямо из сэмпла).
float scene_depth(vec2 uv) {
	vec3 ndc = vec3(uv * 2.0 - 1.0, texture(depth_texture, uv).r);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	return -(view.z / view.w);
}

void vertex() {
	// Своя глубина считается в вершинном шейдере — так гарантированно нет
	// зависимости от доступности POSITION/VERTEX в fragment.
	own_view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	world_normal_v = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float self_depth = own_view_depth;

	// Уход кромки: мениск на скользящих углах + мягкость силуэта.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float grazing = pow(1.0 - facing, 2.0);
	float rim = mix(1.0, grazing, clamp(edge_softness, 0.0, 1.0));

	float radius = blur_radius * rim * (1.0 + meniscus * grazing);
	radius *= mix(1.0, 1.35, pulse);           // сердце расширяет диск
	radius *= mix(1.0, 1.6, pressure * 0.5);   // падение давления — всё плывёт

	// Диск Вогеля: плотная упаковка без текстурных ассетов.
	vec2 center = uv;
	float wobble = living * 0.004 * (1.0 + pressure);
	center += vec2(
		sin(TIME * 0.61 + uv.y * 37.0),
		cos(TIME * 0.47 + uv.x * 41.0)
	) * wobble;

	float radius_px = radius * mix(1.0, 0.35, float(blur_samples >= 32)) 
	                    * (0.85 + 0.3 * hash12(uv * 891.0));

	vec3 accum = vec3(0.0);
	vec3 accum_chroma = vec3(0.0);
	float weight_sum = 0.0;
	float highlight = 0.0;
	float inv_max = 1.0 / sqrt(float(blur_samples));

	for (int i = 0; i < 32; i++) {
		if (i >= blur_samples) {
			break;
		}
		float t = (float(i) + 0.5) * inv_max;      // нормированная площадь
		float ang = float(i) * GOLDEN_ANGLE;
		float rr = sqrt(t);
		vec2 offset = vec2(cos(ang), sin(ang)) * rr * radius_px * SCREEN_PIXEL_SIZE;

		vec2 suv = center + offset;
		if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
			continue; // за пределами экрана — не тянем пиксели с противоположной стороны
		}

		float sd = scene_depth(suv);
		// Отбрасываем то, что стоит ПЕРЕД телом: иначе блюр «съест» реквизит.
		float reject = step(self_depth - depth_bias, sd);
		float w = mix(1.0, clamp(reject, 0.0, 1.0), clamp(depth_reject, 0.0, 1.0));

		// Мягкое радиальное угасание выборки — край дыры не имеет границы.
		w *= 1.0 - rr * 0.35;
		vec3 s = texture(screen_texture, suv).rgb;

		accum += s * w;
		// Хроматика: сдвиг каналов к краю диска.
		float ca = chromatic * rr * 0.6 * SCREEN_PIXEL_SIZE.x * radius_px;
		accum_chroma.r += texture(screen_texture, suv + vec2(ca, 0.0)).r * w;
		accum_chroma.b += texture(screen_texture, suv - vec2(ca, 0.0)).b * w;

		highlight += max(dot(s, vec3(0.299, 0.587, 0.114)) - 0.72, 0.0) * w;
		weight_sum += w;
	}

	vec3 blurred = accum / max(weight_sum, 0.0001);
	if (chromatic > 0.001) {
		vec3 ca_col = accum_chroma / max(weight_sum, 0.0001);
		blurred = mix(blurred, vec3(ca_col.r, blurred.g, ca_col.b), 0.7);
	}

	// Боке-цветение: свет в размытии «вспухает», как от широкой диафрагмы.
	blurred += highlight * 0.08 * vec3(0.9, 0.95, 1.0);

	// Абсорбция: никакой чёрной фигуры, но свет в этом месте ведёт себя иначе.
	float core = 1.0 - grazing;
	vec3 absorb = mix(vec3(1.0), absorption_tint, absorption * core);
	blurred *= absorb;
	blurred *= mix(1.0, 0.88, absorption * core);

	ALBEDO = blurred;
	// Альфа: силуэт с мягкой кромкой. Множитель держит дыру «неплотной».
	ALPHA = clamp(coverage * (0.985 - 0.30 * grazing), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.0;
}
