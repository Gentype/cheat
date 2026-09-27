extends Node
## Карта ввода.
##
## Действия описаны кодом, а не в project.godot: так они версионируются вместе
## с геймплеем, не могут разойтись со скриптами и одинаковы на всех платформах.
## Регистрация идёт до первой сцены (автолоад), поэтому Input.is_action_* всегда
## находят действие.

const ACTIONS := {
	&"move_forward": [KEY_W, KEY_UP],
	&"move_back": [KEY_S, KEY_DOWN],
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"interact": [KEY_E, KEY_SPACE],
	&"hold_breath": [KEY_SHIFT],
	&"pause": [KEY_ESCAPE],
	&"debug_camera": [KEY_F1],
	&"camera_next": [KEY_F2],
	&"quality_cycle": [KEY_F10],
	&"sprint": [KEY_CTRL],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	register_all()


func register_all() -> void:
	for action in ACTIONS.keys():
		_ensure_action(action, ACTIONS[action])


func _ensure_action(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		if not _has_event(action, event):
			InputMap.action_add_event(action, event)


func _has_event(action: StringName, event: InputEvent) -> bool:
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and event is InputEventKey:
			if (existing as InputEventKey).physical_keycode == (event as InputEventKey).physical_keycode:
				return true
	return false
