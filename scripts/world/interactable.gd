class_name Interactable
extends Area3D
## Всё, к чему герой может прикоснуться: дверь, кран, манжета, карман халата.
## Событие уходит наверх как сигнал — уровень решает, что это значит.

signal interacted(interactable: Interactable, player: PlayerController)
signal focus_changed(interactable: Interactable, focused: bool)

## Текст подсказки. Пусто — подсказка не показывается (осмотр без слов).
@export var prompt := "ОСМОТРЕТЬ"
## Имя события для уровня.
@export var event_name: StringName = &""
@export var enabled := true
@export var one_shot := false
## Сколько секунд герой занят действием (для сценарных пауз).
@export var action_time := 0.0
## Громкость действия: шум привлекает внимание.
@export var noise := 0.2

var used := false


func _ready() -> void:
	add_to_group(&"interactable")
	monitoring = false
	monitorable = true
	collision_layer = 4
	if get_child_count() == 0:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.3, 0.3, 0.3)
		shape.shape = box
		add_child(shape)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)


func interact(player: PlayerController) -> void:
	if not enabled:
		return
	if one_shot and used:
		return
	used = true
	interacted.emit(self, player)


func set_enabled(value: bool) -> void:
	enabled = value
	if not value and one_shot:
		monitorable = false


func _on_focus_entered() -> void:
	focus_changed.emit(self, true)


func _on_focus_exited() -> void:
	focus_changed.emit(self, false)
