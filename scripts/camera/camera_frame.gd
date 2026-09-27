class_name CameraFrame
extends Resource
## Один ракурс. Не «камера, которую двигает игрок», а заранее поставленная
## точка зрения, между которыми режиссёр жёстко склеивает кадр — язык Buckshot
## Roulette: статика, резкая склейка, микро-движение внутри кадра.
##
## Ракурсы описываются данными (JSON в resources/camera_frames), поэтому
## уровень можно перекомпоновать, не трогая код.

## Уникальный идентификатор ракурса.
@export var id: StringName = &""
## Позиция в мире. Если attach_to_anchor — смещение относительно головы героя.
@export var position := Vector3.ZERO
## Точка, на которую смотрит камера: смещение от головы героя (в его системе).
@export var target_offset := Vector3(0.0, 1.35, 0.0)
@export var fov := 38.0
## Предпочтение при выборе: чем выше, тем охотнее режиссёр встаёт сюда.
@export var bias := 0.0
## Теги интереса («коридор», «каталка», «стекло») — сопоставляются с флагами бита.
@export var tags: Array[StringName] = []
## Диапазон дистанций, в котором ракурс вообще имеет право быть выбранным.
@export var min_distance := 0.0
@export var max_distance := 14.0
## Сколько секунд кадр держится минимум и максимум.
@export var dwell_min := 2.4
@export var dwell_max := 6.5
## Амплитуда «живой руки»: 0 — штатив, 1 — камера в чужих руках.
@export var handheld := 0.35
## Наезд, м/с. При растущем ужасе кадр сам подъезжает к герою.
@export var push_in := 0.045
## Камера приколочена к миру и не меняет позицию вслед за героем.
@export var fixed_in_world := true
## Едва заметный крен (градусы) — «голова набок».
@export var roll := 0.0
## Смещение героя в кадре: 0 — центр, +1 — правая треть, -1 — левая треть.
@export var composition_offset := 0.0
## Высота, с которой смотрит камера, относительно пола (для эффекта «сверху вниз»).
@export var height_bias := 0.0
## Принудительная склейка на этот ракурс при старте бита.
@export var opening := false
## Ракурс-ловушка: используется только по триггеру сцены.
@export var scripted_only := false


static func from_dict(data: Dictionary) -> CameraFrame:
	var frame := CameraFrame.new()
	frame.id = StringName(data.get("id", ""))
	var pos: Array = data.get("position", [0, 0, 0])
	frame.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	var target: Array = data.get("target_offset", [0, 1.35, 0])
	frame.target_offset = Vector3(float(target[0]), float(target[1]), float(target[2]))
	frame.fov = float(data.get("fov", 38.0))
	frame.bias = float(data.get("bias", 0.0))
	var raw_tags: Array = data.get("tags", [])
	var tags: Array[StringName] = []
	for tag in raw_tags:
		tags.append(StringName(String(tag)))
	frame.tags = tags
	frame.min_distance = float(data.get("min_distance", 0.0))
	frame.max_distance = float(data.get("max_distance", 14.0))
	frame.dwell_min = float(data.get("dwell_min", 2.4))
	frame.dwell_max = float(data.get("dwell_max", 6.5))
	frame.handheld = float(data.get("handheld", 0.35))
	frame.push_in = float(data.get("push_in", 0.045))
	frame.fixed_in_world = bool(data.get("fixed_in_world", true))
	frame.roll = float(data.get("roll", 0.0))
	frame.composition_offset = float(data.get("composition_offset", 0.0))
	frame.height_bias = float(data.get("height_bias", 0.0))
	frame.opening = bool(data.get("opening", false))
	frame.scripted_only = bool(data.get("scripted_only", false))
	return frame


func to_dict() -> Dictionary:
	var tag_list: Array = []
	for tag in tags:
		tag_list.append(String(tag))
	return {
		"id": String(id),
		"position": [position.x, position.y, position.z],
		"target_offset": [target_offset.x, target_offset.y, target_offset.z],
		"fov": fov,
		"bias": bias,
		"tags": tag_list,
		"min_distance": min_distance,
		"max_distance": max_distance,
		"dwell_min": dwell_min,
		"dwell_max": dwell_max,
		"handheld": handheld,
		"push_in": push_in,
		"fixed_in_world": fixed_in_world,
		"roll": roll,
		"composition_offset": composition_offset,
		"height_bias": height_bias,
		"opening": opening,
		"scripted_only": scripted_only,
	}


func dwell_seconds() -> float:
	return randf_range(dwell_min, dwell_max)


## Насколько ракурс уместен: чем ближе герой к рабочей дистанции, тем лучше.
func distance_score(distance: float) -> float:
	if distance < min_distance or distance > max_distance:
		return -1.0
	var span := maxf(max_distance - min_distance, 0.001)
	var normalized := (distance - min_distance) / span
	# Оптимум — первая треть диапазона: камера любит стоять близко.
	return 1.0 - absf(normalized - 0.33) * 1.4


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)
