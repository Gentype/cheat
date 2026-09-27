extends LevelBase
## «НОЧНОЙ ОБХОД» — игровой бит-слайс.
##
## Блок морга ночью: коридор, палата 301, процедурная, склад и санузел.
## Герой приходит в себя на полу, берёт фонарь, ищет журнал поста и находит
## в палате 301 пациента, у которого нет реакции зрачка.
##
## Здесь проверяется весь язык игры сразу: жёсткие склейки ракурсов, микро-дрожь
## кадра, «переезжающие» предметы, склейки через момент, когда игрок отвернулся,
## и постепенное расширение зрачка как шкала состояния.
##
## ВАЖНО: в кадре нет ни одного человека. Тело героя — дыра, пациент под
## простынёй — объём ткани, и это принципиально: игрок достраивает остальное сам.

const SURFACE_TILE := "tile"
const SURFACE_CLOTH := "cloth"

var _broken_lamp: OmniLight3D
var _broken_lamp_panel: MeshInstance3D
var _sheet_figure: Node3D
var _station_screen: MeshInstance3D
var _shifters: Array = []
var _door_storage: Node3D
var _flicker_time := 0.0
var _flatline := false
var _cuff_sequence := false
var _finale_started := false
var _examined_bed := false
var _wheelchair: Node3D


func spawn_position() -> Vector3:
	return Vector3(0.0, 0.1, -6.1)


func spawn_yaw() -> float:
	return PI


func _build_level() -> void:
	_build_shell()
	_build_ward_301()
	_build_procedure_room()
	_build_storage()
	_build_bathroom()
	_build_corridor()
	_build_lighting()
	_build_camera_work()
	_build_interactables()


# --- Оболочка здания ----------------------------------------------------------

func _build_shell() -> void:
	# Полы: коридор, три западных помещения, санузел. Поверхность шага — кафель,
	# но на складе лежит резиновый мат, и звук шага там другой.
	add_child(Props.create_floor(Vector2(3.0, 14.0), Vector3(0, 0, 0), SURFACE_TILE))
	add_child(Props.create_floor(Vector2(6.0, 4.5), Vector3(-4.5, 0, -4.75), SURFACE_TILE))
	add_child(Props.create_floor(Vector2(6.0, 4.0), Vector3(-4.5, 0, 0.5), SURFACE_TILE))
	add_child(Props.create_floor(Vector2(6.0, 3.5), Vector3(-4.5, 0, 5.25), SURFACE_TILE))
	add_child(Props.create_floor(Vector2(3.0, 4.0), Vector3(3.0, 0, 4.0), SURFACE_TILE))
	add_child(Props.create_ceiling(Vector2(12.0, 14.0), Vector3(-1.5, 0, 0)))

	# Стены коридора с проёмами под двери.
	_wall(Vector3(-1.5, 0, -7.0), Vector3(-1.5, 0, -5.1))
	_wall(Vector3(-1.5, 0, -3.9), Vector3(-1.5, 0, -0.6))
	_wall(Vector3(-1.5, 0, 0.6), Vector3(-1.5, 0, 4.4))
	_wall(Vector3(-1.5, 0, 5.6), Vector3(-1.5, 0, 7.0))
	_wall(Vector3(1.5, 0, -7.0), Vector3(1.5, 0, 3.4))
	_wall(Vector3(1.5, 0, 4.6), Vector3(1.5, 0, 7.0))
	_wall(Vector3(-7.5, 0, -7.0), Vector3(1.5, 0, -7.0))
	_wall(Vector3(-7.5, 0, 7.0), Vector3(1.5, 0, 7.0))
	# Внешняя стена западных помещений и перегородки между ними.
	_wall(Vector3(-7.5, 0, -7.0), Vector3(-7.5, 0, 7.0))
	_wall(Vector3(-7.5, 0, -2.5), Vector3(-1.5, 0, -2.5))
	_wall(Vector3(-7.5, 0, 2.5), Vector3(-1.5, 0, 2.5))
	_wall(Vector3(-7.5, 0, 3.5), Vector3(-1.5, 0, 3.5))
	# Санузел.
	_wall(Vector3(4.5, 0, 2.0), Vector3(4.5, 0, 6.0))
	_wall(Vector3(1.5, 0, 2.0), Vector3(4.5, 0, 2.0))
	_wall(Vector3(1.5, 0, 6.0), Vector3(4.5, 0, 6.0))

	# Двери. Склад заперт не до конца — это важно для второй половины бита.
	_place_door(Vector3(-1.5, 0, -5.1), -PI * 0.5, 0.28)
	_place_door(Vector3(-1.5, 0, -0.6), -PI * 0.5, 0.72)
	_place_door(Vector3(1.5, 0, 3.4), -PI * 0.5, -0.06)
	_door_storage = _place_door(Vector3(-1.5, 0, 4.4), -PI * 0.5, 0.02)

	# Трубы и кабели под потолком коридора — обязательная деталь больничного кадра.
	add_child(Props.create_pipe_run(PackedVector3Array([
		Vector3(-1.35, 2.62, -6.9), Vector3(-1.35, 2.62, 6.9),
	]), 0.035))
	add_child(Props.create_pipe_run(PackedVector3Array([
		Vector3(-1.2, 2.5, -6.9), Vector3(-1.2, 2.5, 2.0),
		Vector3(-1.2, 2.5, 2.0),
	]), 0.02))
	add_child(Props.create_pipe_run(PackedVector3Array([
		Vector3(1.3, 2.56, -6.9), Vector3(1.3, 2.56, 6.9),
	]), 0.028))


func _wall(from: Vector3, to: Vector3, height := Props.WALL_HEIGHT) -> void:
	add_child(Props.create_wall(from, to, height))


func _place_door(position: Vector3, yaw: float, open_angle: float) -> Node3D:
	var door := Props.create_door(position, yaw, open_angle)
	add_child(door)
	return door


# --- Помещения -----------------------------------------------------------------

func _build_ward_301() -> void:
	# Палата на две койки. Одна занята — но под простынёй нет человека.
	var occupied := Props.create_bed(Vector3(-4.6, 0, -6.0), 0.0, true)
	add_child(occupied)
	_sheet_figure = occupied.get_node_or_null("Occupant")
	add_child(Props.create_bed(Vector3(-6.2, 0, -3.6), PI * 0.5, false))
	add_child(Props.create_curtain(Vector3(-4.9, 0, -4.3), 0.0, 2.4))
	add_child(Props.create_iv_stand(Vector3(-3.4, 0, -5.4), Vector3(-4.5, 0.8, -5.9)))
	var monitor := Props.create_monitor(Vector3(-2.5, 0, -6.4), -PI * 0.5, 74.0, 0.0)
	monitor.name = "WardMonitor"
	add_child(monitor)
	add_child(Props.create_cabinet(Vector3(-7.1, 0, -5.4), PI * 0.5, 0.5, 0.15))
	add_child(Props.create_chair(Vector3(-3.0, 0, -3.0), PI * 0.25))
	# Коляска: она умеет «переезжать», пока на неё не смотрят.
	_wheelchair = Props.create_wheelchair(Vector3(-6.6, 0, -3.0), PI * 0.7)
	add_child(_wheelchair)
	_register_shifter(_wheelchair, [
		Vector3(-6.6, 0, -3.0),
		Vector3(-2.6, 0, -4.6),
		Vector3(-6.9, 0, -6.3),
	])


func _build_procedure_room() -> void:
	# Процедурная: каталка под простынёй, монитор, штатив, умывальник.
	var covered := Props.create_covered_gurney(Vector3(-4.6, 0, 0.7), PI * 0.5)
	add_child(covered)
	_register_shifter(covered, [
		Vector3(-4.6, 0, 0.7),
		Vector3(-6.4, 0, 1.6),
		Vector3(-3.2, 0, -0.4),
	], 3.5)
	add_child(Props.create_monitor(Vector3(-2.6, 0, 2.1), -PI * 0.5, 58.0, 0.0))
	add_child(Props.create_iv_stand(Vector3(-3.2, 0, -0.6), Vector3(-4.2, 0.85, 0.5)))
	add_child(Props.create_sink(Vector3(-7.15, 0, 1.9), PI * 0.5))
	add_child(Props.create_cabinet(Vector3(-7.1, 0, -0.9), PI * 0.5, 0.9, 0.35))
	add_child(Props.create_chair(Vector3(-3.4, 0, 2.2), -PI * 0.2))


func _build_storage() -> void:
	# Склад: темно, тесно, много металла. Здесь живёт звук «уронили что-то тяжёлое».
	add_child(Props.create_cabinet(Vector3(-7.1, 0, 4.2), PI * 0.5, 0.12, 0.05))
	add_child(Props.create_cabinet(Vector3(-7.1, 0, 5.8), PI * 0.5, 0.05, 0.9))
	add_child(Props.create_cabinet(Vector3(-4.4, 0, 6.8), PI, 0.35, 0.2))
	add_child(Props.create_gurney(Vector3(-3.0, 0, 4.4), PI * 0.5, true))
	add_child(Props.create_chair(Vector3(-5.6, 0, 4.0), PI * 0.6))
	add_child(Props.create_pipe_run(PackedVector3Array([
		Vector3(-7.3, 2.4, 3.7), Vector3(-2.0, 2.4, 3.7),
	]), 0.05))


func _build_bathroom() -> void:
	add_child(Props.create_sink(Vector3(2.15, 0, 5.5), 0.0))
	add_child(Props.create_chair(Vector3(3.6, 0, 3.0), -PI * 0.3))
	# Ведро и швабра: детали, которые делают помещение обжитым.
	var bucket := MeshBuilder.new()
	bucket.cylinder(Vector3(3.9, 0.0, 5.4), Vector3(3.9, 0.28, 5.4), 0.14, 0.17, 16, false)
	bucket.torus(Vector3(3.9, 0.28, 5.4), Vector3(0, 1, 0), 0.16, 0.008, 16, 8)
	var bucket_node := MeshInstance3D.new()
	bucket_node.mesh = bucket.commit("bucket")
	bucket_node.material_override = MaterialFactory.plastic()
	add_child(bucket_node)


func _build_corridor() -> void:
	# Пост медсестры в южном конце: стол, монитор, стул, журнал.
	add_child(Props.create_cabinet(Vector3(0.9, 0, 6.4), -PI * 0.5, 0.1, 0.1))
	add_child(Props.create_cabinet(Vector3(0.9, 0, 5.4), -PI * 0.5, 0.1, 0.1))
	add_child(Props.create_chair(Vector3(0.1, 0, 6.2), PI * 0.5))
	var station := Props.create_monitor(Vector3(0.7, 0, 5.9), -PI * 1.5, 96.0, 0.0)
	station.name = "StationMonitor"
	add_child(station)
	_station_screen = station.get_node_or_null("Screen")

	# Каталка у стены и коляска в коридоре.
	add_child(Props.create_gurney(Vector3(1.05, 0, -1.4), PI * 0.5, true))
	add_child(Props.create_gurney(Vector3(-1.15, 0, 1.2), PI * 0.5, false))
	add_child(Props.create_wheelchair(Vector3(1.15, 0, 3.2), -PI * 0.5))

	# Часы в северном конце: на них останавливается время во время финала.
	add_child(Props.create_clock(Vector3(0.0, 2.05, -6.92), 0.0))

	# Таблички: зелёная у выхода, жёлтая у склада.
	var exit_sign := MeshBuilder.new()
	exit_sign.rect(Vector3(0.0, 2.35, 6.92), Vector3(0.42, 0, 0), Vector3(0, 0.16, 0))
	var exit_node := MeshInstance3D.new()
	exit_node.mesh = exit_sign.commit("exit_sign")
	exit_node.material_override = MaterialFactory.sign_plate(Color(0.32, 0.72, 0.42))
	add_child(exit_node)

	var warn_sign := MeshBuilder.new()
	warn_sign.rect(Vector3(-1.43, 1.55, 4.9), Vector3(0.0, 0, -0.34), Vector3(0, 0.24, 0))
	var warn_node := MeshInstance3D.new()
	warn_node.mesh = warn_sign.commit("warn_sign")
	warn_node.material_override = MaterialFactory.sign_plate(Color(0.85, 0.72, 0.28))
	add_child(warn_node)


# --- Свет ---------------------------------------------------------------------

func _build_lighting() -> void:
	# Рабочий свет коридора: холодные панели, две из них ещё держатся.
	add_child(Props.create_lamp(Vector3(0.0, 0, -5.0), 0.0, 1.35))
	add_child(Props.create_lamp(Vector3(0.0, 0, -1.0), 0.0, 1.15))
	add_child(Props.create_lamp(Vector3(0.0, 0, 3.0), 0.0, 1.05))
	var station_lamp := Props.create_lamp(Vector3(0.0, 0, 6.4), 0.0, 0.95)
	add_child(station_lamp)

	# Мигающий светильник: один умирает весь бит.
	var broken := Props.create_lamp(Vector3(-4.5, 0, -4.6), 0.0, 0.8)
	broken.name = "BrokenLamp"
	add_child(broken)
	_broken_lamp = broken.get_node_or_null("Light") as OmniLight3D
	_broken_lamp_panel = broken.get_node_or_null("Panel") as MeshInstance3D

	# Дежурный свет в помещениях.
	add_child(Props.create_lamp(Vector3(-4.8, 0, 0.6), 0.0, 0.7))
	add_child(Props.create_lamp(Vector3(3.0, 0, 4.0), 0.0, 0.55))
	add_child(Props.create_lamp(Vector3(-4.6, 0, 5.2), 0.0, 0.28))


# --- Камера и ракурсы ---------------------------------------------------------

func _build_camera_work() -> void:
	add_camera_trigger(Vector3(0.0, 0, -3.6), &"corridor_mid", 4.0, Vector3(2.6, 2.5, 1.6))
	var ward_tags: Array[StringName] = [&"ward"]
	add_camera_trigger(Vector3(-1.5, 0, -4.5), &"door_301", 4.5, Vector3(1.6, 2.5, 2.2), ward_tags)
	var patient_tags: Array[StringName] = [&"ward", &"patient"]
	add_camera_trigger(Vector3(-4.6, 0, -3.8), &"bed_side", 5.0, Vector3(3.0, 2.5, 2.0), patient_tags)
	var procedure_tags: Array[StringName] = [&"procedure"]
	add_camera_trigger(Vector3(-1.5, 0, 0.0), &"door_302", 4.0, Vector3(1.6, 2.5, 2.2), procedure_tags)
	var mirror_tags: Array[StringName] = [&"mirror"]
	add_camera_trigger(Vector3(1.5, 0, 4.0), &"mirror_reverse", 6.0, Vector3(1.8, 2.5, 1.8), mirror_tags)
	var station_tags: Array[StringName] = [&"station"]
	add_camera_trigger(Vector3(0.0, 0, 5.2), &"station", 4.5, Vector3(2.4, 2.5, 1.6), station_tags)
	var storage_tags: Array[StringName] = [&"storage"]
	add_camera_trigger(Vector3(-1.5, 0, 5.0), &"storage_dark", 4.0, Vector3(1.6, 2.5, 1.6), storage_tags)

	add_event_zone(Vector3(0.0, 0, -3.6), &"corridor_entered", Vector3(2.6, 2.5, 1.2))
	add_event_zone(Vector3(-1.5, 0, -4.5), &"ward_entered", Vector3(1.6, 2.5, 2.0))
	add_event_zone(Vector3(1.5, 0, 4.0), &"bathroom_entered", Vector3(1.6, 2.5, 1.8))
	add_event_zone(Vector3(-1.5, 0, 5.0), &"storage_entered", Vector3(1.6, 2.5, 1.6))
	add_event_zone(Vector3(0.0, 0, 6.3), &"station_reached", Vector3(2.8, 2.5, 1.4))


# --- Интерактив ---------------------------------------------------------------

func _build_interactables() -> void:
	# Фонарь лежит на каталке рядом с тем местом, где герой пришёл в себя.
	var flashlight := Interactable.new()
	flashlight.name = "Flashlight"
	flashlight.prompt = "ВЗЯТЬ ФОНАРЬ"
	flashlight.event_name = &"take_flashlight"
	flashlight.position = Vector3(1.05, 0.86, -1.9)
	flashlight.set_meta(&"size", Vector3(0.4, 0.3, 0.4))
	flashlight.interacted.connect(_on_interacted)
	add_child(flashlight)

	# Манжета тонометра на штативе.
	var cuff := Interactable.new()
	cuff.name = "Cuff"
	cuff.prompt = "НАДЕТЬ МАНЖЕТУ"
	cuff.event_name = &"use_cuff"
	cuff.position = Vector3(-3.2, 1.15, -0.6)
	cuff.interacted.connect(_on_interacted)
	add_child(cuff)

	# Журнал поста.
	var log_book := Interactable.new()
	log_book.name = "Log"
	log_book.prompt = "ЧИТАТЬ ЖУРНАЛ"
	log_book.event_name = &"read_log"
	log_book.position = Vector3(0.9, 1.02, 5.9)
	log_book.interacted.connect(_on_interacted)
	add_child(log_book)

	# Пациент в 301.
	var patient := Interactable.new()
	patient.name = "Patient301"
	patient.prompt = "ОСМОТРЕТЬ ПАЦИЕНТА"
	patient.event_name = &"examine_patient"
	patient.position = Vector3(-4.6, 1.0, -6.2)
	patient.interacted.connect(_on_interacted)
	add_child(patient)

	# Зеркало в санузле.
	var mirror := Interactable.new()
	mirror.name = "Mirror"
	mirror.prompt = "ПОСМОТРЕТЬ В ЗЕРКАЛО"
	mirror.event_name = &"use_mirror"
	mirror.position = Vector3(2.15, 1.2, 5.42)
	mirror.interacted.connect(_on_interacted)
	add_child(mirror)

	# Свет в коридоре: щиток у поста.
	var lights := Interactable.new()
	lights.name = "LightSwitch"
	lights.prompt = "ВКЛЮЧИТЬ ДЕЖУРНЫЙ СВЕТ"
	lights.event_name = &"restore_lights"
	lights.position = Vector3(1.42, 1.35, 5.2)
	lights.one_shot = true
	lights.interacted.connect(_on_interacted)
	add_child(lights)

	# Монитор поста — финальная точка бита.
	var monitor := Interactable.new()
	monitor.name = "StationScreen"
	monitor.prompt = "ПРОВЕРИТЬ ПОКАЗАНИЯ"
	monitor.event_name = &"check_screen"
	monitor.interacted.connect(_on_interacted)
	monitor.position = Vector3(0.7, 1.3, 5.8)
	add_child(monitor)


func _on_interacted(interactable: Interactable, _player: PlayerController) -> void:
	match interactable.event_name:
		&"take_flashlight":
			player.avatar.set_flashlight(true)
			AudioDirector.play(&"switch", -12.0, 1.1, AudioDirector.BUS_SFX)
			interactable.prompt = "ФОНАРЬ В РУКЕ"
			interactable.enabled = false
			objective("НАЙТИ ЖУРНАЛ ПОСТА")
			say("Фонарь в правой руке. Левая пустая — и это правильно.", 4.0)
			GameState.soothe(0.8, &"flashlight")
		&"use_cuff":
			_start_cuff_sequence()
		&"read_log":
			_read_log(interactable)
		&"examine_patient":
			_examine_patient(interactable)
		&"use_mirror":
			_use_mirror(interactable)
		&"restore_lights":
			_restore_lights(interactable)
		&"check_screen":
			_check_screen(interactable)
		_:
			pass


# --- События уровня -----------------------------------------------------------

func _on_event(event_name: StringName, _zone: Area3D) -> void:
	match event_name:
		&"corridor_entered":
			if not GameState.has_flag(&"corridor_seen"):
				GameState.set_flag(&"corridor_seen")
				director.add_interest_tag(&"corridor")
				GameState.apply_stress(0.6, &"corridor")
				say("Смена началась в 03:00. Сейчас 03:14. Пятнадцать минут стёрты.", 4.5)
		&"ward_entered":
			director.add_interest_tag(&"ward")
			if not GameState.has_flag(&"ward_seen"):
				GameState.set_flag(&"ward_seen")
				say("Палата 301. Две койки. Одна занята — по документам здесь никого нет.", 5.0)
				GameState.apply_stress(0.9, &"ward")
		&"bathroom_entered":
			director.add_interest_tag(&"mirror")
		&"storage_entered":
			director.add_interest_tag(&"storage")
			if not GameState.has_flag(&"storage_seen"):
				GameState.set_flag(&"storage_seen")
				_move_storage_object()
		&"station_reached":
			var station_interest: Array[StringName] = [&"station", &"corridor"]
			director.set_interest_tags(station_interest)
		_:
			pass


func _on_frame_changed(_frame: CameraFrame, reason: StringName) -> void:
	# Язык склейки: то, что игрок не видит, живёт своей жизнью. Как только
	# кадр уходит, предмет меняет положение. Именно так работает страх в
	# Buckshot Roulette — не скримером, а расхождением между двумя кадрами.
	if reason == &"opening" or director == null or director.camera == null:
		return
	for entry in _shifters:
		var node: Node3D = entry["node"]
		if node == null or not is_instance_valid(node):
			continue
		var point := node.global_position
		var min_distance: float = entry["min_distance"]
		var too_close := player != null and player.global_position.distance_to(point) < min_distance
		var visible := director.camera.is_position_in_frustum(point + Vector3(0, 0.5, 0))
		if visible or too_close:
			continue
		var points: Array = entry["points"]
		var index := int(entry["index"])
		index = (index + 1) % points.size()
		entry["index"] = index
		node.global_position = points[index]
		# Едва слышимый отзвук переноса: металл по кафелю.
		if player != null and player.global_position.distance_to(point) < 12.0:
			AudioDirector.play_at(&"metal_clang", point, -34.0, 0.8, AudioDirector.BUS_SFX)


func _register_shifter(node: Node3D, points: Array, min_distance := 2.2) -> void:
	_shifters.append({
		"node": node,
		"points": points,
		"index": 0,
		"min_distance": min_distance,
	})


# --- Сценарные моменты --------------------------------------------------------

func _on_level_ready() -> void:
	objective("ПРИЙТИ В СЕБЯ")
	var avatar := player.avatar
	avatar.set_pose_asymmetric(&"limp", &"limp")
	avatar.set_flashlight(false)
	AudioDirector.start_loop(&"static", AudioDirector.BUS_BED, -38.0)
	AudioDirector.play(&"cuff_pump", -10.0, 1.0, AudioDirector.BUS_SFX)
	await get_tree().create_timer(1.4).timeout
	AudioDirector.play(&"monitor_beep", -14.0, 1.0, AudioDirector.BUS_SFX)
	await get_tree().create_timer(0.8).timeout
	effects.drift(0.7, 1.6)
	say("Очнулся на полу. Кто-то стянул простыню, а маску оставил.", 4.5)
	avatar.set_pose(&"brace")
	await get_tree().create_timer(2.4).timeout
	avatar.set_pose_asymmetric(&"idle", &"idle")
	objective("ВЗЯТЬ ФОНАРЬ")


func _start_cuff_sequence() -> void:
	if _cuff_sequence:
		return
	_cuff_sequence = true
	player.can_move = false
	director.cut_to(&"cuff_close", 7.0, &"scripted")
	hud.show_cuff(true)
	AudioDirector.play(&"cuff_pump", -6.0, 1.0, AudioDirector.BUS_BODY)
	# Манжета надувается: давление в кадре совпадает с давлением в цифрах.
	var pressure := 0.0
	var steps := 90
	for i in range(0, steps):
		pressure = lerpf(0.0, 172.0, float(i) / float(steps))
		hud.set_cuff_pressure(pressure, int(GameState.heart_rate))
		await get_tree().create_timer(0.045).timeout
	# Спуск: цифры берутся прямо из виталитетов, а не из скрипта.
	for i in range(0, 40):
		pressure = lerpf(172.0, 0.0, float(i) / 40.0)
		hud.set_cuff_pressure(pressure, int(GameState.heart_rate))
		await get_tree().create_timer(0.05).timeout
	await get_tree().create_timer(0.6).timeout
	hud.set_cuff_result(int(GameState.systolic), int(GameState.diastolic))
	AudioDirector.play(&"valve", -10.0, 1.0, AudioDirector.BUS_SFX)
	await get_tree().create_timer(2.2).timeout
	hud.show_cuff(false)
	player.can_move = true
	director.release_scripted()
	GameState.apply_stress(1.4, &"cuff")
	objective("НАЙТИ ЖУРНАЛ ПОСТА")
	say("Давление падает. Зрачок не отвечает на свет. Это не усталость.", 5.0)


func _read_log(interactable: Interactable) -> void:
	interactable.enabled = false
	director.cut_to(&"log_close", 5.0, &"scripted")
	GameState.apply_stress(1.0, &"log")
	objective("ПРОВЕРИТЬ ПАЛАТУ 301")
	say("Запись 03:11 — «пациент 301, зрачки фиксированы, реакции нет».", 5.0)
	await get_tree().create_timer(4.4).timeout
	director.release_scripted()


func _examine_patient(interactable: Interactable) -> void:
	if _examined_bed:
		return
	_examined_bed = true
	interactable.enabled = false
	player.can_move = false
	# Кульминация бита: кадр наезжает на простыню, и там — вдох, которого нет.
	director.cut_to(&"patient_close", 9.0, &"scripted")
	GameState.apply_stress(2.6, &"patient")
	effects.push_pupil(0.45, 3.0)
	effects.drift(1.0, 2.4)
	AudioDirector.play(&"whoosh", -8.0, 0.9, AudioDirector.BUS_BODY)
	say("Простыня поднимается. Медленно. Ровно.", 4.0)
	await get_tree().create_timer(3.6).timeout
	# Простыня опадает: под ней нет никого — и никогда не было.
	if _sheet_figure != null and is_instance_valid(_sheet_figure):
		var tween := create_tween()
		tween.tween_property(_sheet_figure, "scale", Vector3(1.0, 0.25, 1.0), 1.6)
	AudioDirector.play(&"cloth_move", -14.0, 0.9, AudioDirector.BUS_SFX)
	say("Под простынёй нет тела. Есть только форма тела.", 4.5)
	await get_tree().create_timer(3.0).timeout
	player.can_move = true
	director.release_scripted()
	objective("ДОЙТИ ДО ПОСТА")
	GameState.set_flag(&"patient_seen", true)


func _use_mirror(interactable: Interactable) -> void:
	interactable.enabled = false
	player.can_move = false
	director.cut_to(&"mirror_reverse", 8.0, &"scripted")
	GameState.apply_stress(1.2, &"mirror")
	# Главный кадр игры: в зеркале нет человека — есть маска и дыра вместо тела.
	effects.push_pupil(0.6, 4.0)
	player.avatar.gesture([&"cover", 0.9, &"check_pulse", 1.6, &"idle", 1.0])
	say("В зеркале маска. За маской — ничего. Не темнота, а просто пустое место.", 5.0)
	await get_tree().create_timer(4.0).timeout
	say("Руки есть. Руки настоящие. Всё остальное — догадка.", 4.0)
	await get_tree().create_timer(3.6).timeout
	player.can_move = true
	director.release_scripted()
	GameState.set_flag(&"mirror_seen", true)


func _restore_lights(interactable: Interactable) -> void:
	interactable.enabled = false
	AudioDirector.play(&"switch", -8.0, 0.9, AudioDirector.BUS_SFX)
	if _broken_lamp != null:
		_broken_lamp.light_energy = 1.5
		_broken_lamp.light_color = Color(0.95, 0.88, 0.72)
	if _broken_lamp_panel != null:
		_broken_lamp_panel.material_override = MaterialFactory.emissive(Color(0.95, 0.90, 0.78), 2.4)
	say("Дежурный свет загорелся. Стало светлее — и от этого только хуже.", 4.0)
	GameState.soothe(0.6, &"light")


func _check_screen(interactable: Interactable) -> void:
	interactable.enabled = false
	if _finale_started:
		return
	_finale_started = true
	_flatline = true
	# Финальный кадр: монитор уходит в асистолию, и кадр больше не склеивается.
	if _station_screen != null:
		_station_screen.material_override = MaterialFactory.crt(60.0, Color(1.0, 0.35, 0.32), 1.0)
	AudioDirector.stop_loop(&"ward_amb", 2.0)
	AudioDirector.start_loop(&"flatline", AudioDirector.BUS_BED, -18.0)
	AudioDirector.play(&"flatline_start", -6.0, 1.0, AudioDirector.BUS_BODY)
	director.lock(true)
	director.cut_to(&"flatline_frame", 0.0, &"scripted")
	player.can_move = false
	GameState.apply_stress(3.0, &"flatline")
	GameState.set_consciousness(0.35, &"flatline")
	effects.flash(0.8, 4.0)
	effects.push_pupil(0.8, 6.0)
	say("Монитор показывает асистолию. Датчик на груди — мой.", 5.0)
	await get_tree().create_timer(5.0).timeout
	# goto_menu — не корутина: запускаем переход и оставляем бит затухать в шторке.
	SceneRouter.goto_menu("СМЕНА ОКОНЧЕНА · 03:41")


func _move_storage_object() -> void:
	# На складе что-то тяжёлое падает в темноте. Источник — невидим.
	AudioDirector.play_at(&"metal_clang", Vector3(-5.0, 1.0, 5.0), -6.0, 0.85, AudioDirector.BUS_SFX)
	AudioDirector.play(&"whoosh", -14.0, 0.8, AudioDirector.BUS_BODY)
	effects.drift(0.6, 1.2)
	player.avatar.gesture([&"brace", 0.5, &"cover", 0.7, &"idle", 1.0])
	GameState.apply_stress(1.6, &"storage_noise")
	say("На складе что-то упало. Там никого нет — по журналу там никого нет.", 4.5)


# --- Кадровый цикл уровня -----------------------------------------------------

func _process(delta: float) -> void:
	# Риска направления головы в HUD: игрок должен понимать, куда смотрит герой.
	if hud != null and player != null:
		hud.set_look(clampf(player.head_yaw / PlayerController.HEAD_YAW_LIMIT, -1.0, 1.0))
	if _broken_lamp == null:
		return
	# Умирающая лампа: хаотичное мерцание, иногда с полным провалом в темноту.
	_flicker_time += delta
	var t := _flicker_time
	var flicker := sin(t * 17.0) * 0.5 + sin(t * 41.0) * 0.25 + sin(t * 3.1) * 0.25
	var alive := 0.55 + flicker * 0.35
	if fmod(t, 9.0) > 8.4:
		alive = 0.0
	_broken_lamp.light_energy = maxf(0.04, alive * 0.9)

	# Простыня дышит: единственное движение в палате 301.
	if _sheet_figure != null and is_instance_valid(_sheet_figure) and not _flatline:
		var breath := sin(t * 0.55) * 0.5 + 0.5
		_sheet_figure.scale.y = lerpf(1.0, 1.035, breath)
