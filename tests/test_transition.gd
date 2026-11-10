extends SceneTree
## Uses the recovered key times and transformed band geometry without running
## the original game. Exercises actual Godot input and process dispatch too.

const Transition = preload("res://features/shell/stripe_transition.gd")
var failures: Array[String] = []
var checks: int = 0
var callback_count: int = 0
var covered_count: int = 0
var finished_count: int = 0
var covered_was_opaque: bool = false

class InputProbe:
	extends Node
	var key_count: int = 0
	var mouse_count: int = 0
	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed:
			key_count += 1
		if event is InputEventMouseButton and event.pressed:
			mouse_count += 1


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: " + label)


func _run() -> void:
	var probe := InputProbe.new()
	root.add_child(probe)
	var transition := Transition.new()
	root.add_child(transition)
	transition.covered.connect(func() -> void:
		covered_count += 1
		covered_was_opaque = transition.coverage_at(transition.size * 0.5) >= 0.9999)
	transition.finished.connect(func() -> void: finished_count += 1)
	await process_frame
	_check(not transition.busy and not transition.visible, "initial RESET hides overlay")
	_check(transition.mouse_filter == Control.MOUSE_FILTER_IGNORE, "idle does not intercept mouse input")
	transition.play(Callable())
	_check(not transition.busy, "invalid callback is ignored")
	transition.play(_change)
	transition.set_process(false)
	_check(transition.busy and transition.visible, "play starts cover")
	transition.play(_change)
	transition._process(0.02)
	_check(is_equal_approx(transition.get_band_color(0).a, 1.0 / 3.0), "first band follows 0.00-0.06 cover keys")
	_check(is_equal_approx(transition.get_band_color(0).r, 2.0 / 3.0), "color interpolation preserves transparent-white source key")
	_check(is_zero_approx(transition.get_band_color(1).a), "second band stays clear before 0.04")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_RIGHT
	key.keycode = KEY_RIGHT
	key.pressed = true
	Input.parse_input_event(key)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = Vector2(20, 20)
	Input.parse_input_event(mouse)
	await process_frame
	_check(probe.key_count == 0 and probe.mouse_count == 0, "transition swallows keyboard and mouse before underlying handlers")
	transition.cancel()
	_check(not transition.busy and not transition.visible and transition.mouse_filter == Control.MOUSE_FILTER_IGNORE, "cancel restores non-blocking idle")
	_check(callback_count == 0 and covered_count == 0 and finished_count == 1, "cancel before coverage never changes the screen and resolves play")
	key = InputEventKey.new()
	key.physical_keycode = KEY_RIGHT
	key.keycode = KEY_RIGHT
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	_check(probe.key_count == 1, "input returns to underlying handlers after cancel")
	transition.play(_change)
	transition.set_process(false)
	transition._process(0.459)
	_check(callback_count == 0 and covered_count == 0, "destination is unchanged before final 0.46 cover key")
	_check(transition.get_band_color(10).a < 1.0, "last band is not yet fully opaque before 0.46")
	transition._process(0.002)
	_check(callback_count == 1 and covered_count == 1 and covered_was_opaque, "coverage emits and changes screen exactly once at full black")
	_check(transition.busy and transition.phase == Transition.Phase.REVEAL, "callback is followed by reveal")
	_check(transition.get_band_color(0) == Color.BLACK and transition.get_band_color(10) == Color.BLACK, "reveal begins fully covered")
	for viewport_size: Vector2i in [Vector2i(1280, 800), Vector2i(960, 640), Vector2i(1600, 900), Vector2i(800, 1000)]:
		# Vary the logical canvas too: the project's canvas_items stretch normally
		# keeps its 1280x800 canvas when only the physical OS window is resized.
		root.content_scale_size = viewport_size
		root.size = viewport_size
		await process_frame
		await process_frame
		_check(transition.size.is_equal_approx(Vector2(viewport_size)), "overlay follows viewport resize %s" % viewport_size)
		var all_covered := true
		for row: int in range(7):
			for column: int in range(9):
				var point := Vector2(float(column) / 8.0, float(row) / 6.0) * transition.size
				all_covered = all_covered and transition.coverage_at(point) >= 0.9999
		_check(all_covered, "opaque midpoint covers viewport corners and interior %s" % viewport_size)
	transition._process(0.03)
	_check(is_equal_approx(transition.get_band_color(0).a, 0.5), "first reveal band uses 0.00-0.06 keys")
	_check(is_equal_approx(transition.get_band_color(1).a, 0.875), "second reveal band uses asymmetric 0.02-0.10 keys")
	transition._process(0.431)
	_check(not transition.busy and not transition.visible and finished_count == 2, "0.46 reveal hides every band and finishes")
	_check(callback_count == 1, "ignored duplicate play did not enqueue a callback")
	transition.cancel()
	_check(finished_count == 2, "cancel while idle emits no spurious finish")
	transition.play(_change_and_cancel.bind(transition))
	transition.set_process(false)
	transition._process(0.46)
	_check(not transition.busy and callback_count == 2 and finished_count == 3, "callback cancellation cannot revive the reveal or block input")
	var started := Time.get_ticks_msec()
	transition.play(_change)
	await transition.finished
	var duration := float(Time.get_ticks_msec() - started) / 1000.0
	_check(duration >= 0.89 and duration < 1.2, "real process playback lasts approximately 0.92 seconds: %.3f" % duration)
	_check(callback_count == 3 and covered_count == 3 and finished_count == 4, "real process dispatch preserves signal and callback counts")
	transition.queue_free()
	probe.queue_free()
	await process_frame
	print("TRANSITION_RESULT ", JSON.stringify({"engine": Engine.get_version_info().string, "checks": checks, "failures": failures, "actual_duration_seconds": duration}))
	quit(0 if failures.is_empty() else 1)


func _change() -> void:
	callback_count += 1


func _change_and_cancel(transition: Transition) -> void:
	callback_count += 1
	transition.cancel()
