class_name CameraTrigger
extends Area3D
## Триггер камеры: зона, в которой режиссёр обязан встать на заданный ракурс.
## Так ставятся «сильные» кадры — вход в палату, взгляд на каталку, момент,
## когда герой понимает, что в коридоре он не один.

signal triggered(trigger: CameraTrigger, body: Node3D)
signal left(trigger: CameraTrigger, body: Node3D)

@export var frame_id: StringName = &""
## Через сколько секунд после входа в зону склеить кадр.
@export var delay := 0.0
## Сколько секунд держать ракурс насильно (0 — вернуть режиссёру).
@export var hold := 3.0
## Теги интереса, которые зона объявляет на время действия.
@export var interest_tags: Array[StringName] = []
## Сработать и забыть.
@export var once := true
## Событие, которое зона поднимает при срабатывании (ловится уровнем).
@export var event_name: StringName = &""

var _fired := false
var _body_inside: Node3D
var _timer := 0.0
var _waiting := false


func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	collision_layer = 0
	collision_mask = 1
	if get_child_count() == 0:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.0, 2.5, 2.0)
		shape.shape = box
		add_child(shape)


func _process(delta: float) -> void:
	if not _waiting:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_waiting = false
	_fire()


func _on_body_entered(body: Node3D) -> void:
	if _fired or _waiting:
		return
	if not body.is_in_group(&"player"):
		return
	_body_inside = body
	if delay <= 0.0:
		_fire()
	else:
		_timer = delay
		_waiting = true


func _on_body_exited(body: Node3D) -> void:
	if body != _body_inside:
		return
	_body_inside = null
	if not _fired:
		return
	left.emit(self, body)


func _fire() -> void:
	if _fired and once:
		return
	_fired = true
	triggered.emit(self, _body_inside)
