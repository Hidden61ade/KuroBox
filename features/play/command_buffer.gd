class_name KuroCommandBuffer
extends RefCounted
## Keep deliberate taps in order. OS key repeat gets one replaceable waiting slot.

const CAPACITY := 4
var _pending: Array[Dictionary] = []

func push(command: Dictionary) -> bool:
	if command.get("kind", "") not in ["move", "punch"]:
		return false
	if command.kind == "move":
		var direction: Variant = command.get("direction")
		if not direction is Vector2i or absi(direction.x) + absi(direction.y) != 1:
			return false
	if command.get("repeat", false):
		for waiting: Dictionary in _pending:
			if waiting.get("repeat", false):
				return false
	else:
		remove_repeats()
	# Overload rejects the newest tap; accepted commands are never reordered.
	if _pending.size() >= CAPACITY:
		return false
	_pending.append(command.duplicate())
	return true

func take_next() -> Dictionary:
	return {} if _pending.is_empty() else _pending.pop_front()

func remove_repeats(key: int = 0) -> void:
	for index in range(_pending.size() - 1, -1, -1):
		if _pending[index].get("repeat", false) and (key == 0 or int(_pending[index].get("key", 0)) == key):
			_pending.remove_at(index)

func clear() -> void:
	_pending.clear()

func size() -> int:
	return _pending.size()
