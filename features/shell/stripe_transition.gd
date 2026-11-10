class_name StripeTransition
extends Control
## Fixed diagonal bands and color keys recovered statically from Circuit Delay's
## exported trans.scn. See evidence/circuit_static_summary.txt for source tracks.
## The source script/callback order is unknown. Calling change at full coverage
## and immediately revealing is KuroBox's integration policy.

signal covered
signal finished

enum Phase { IDLE, COVER, COVERED, REVEAL }

const NATIVE_SIZE := Vector2(320.0, 180.0)
const PARENT_POSITION := Vector2(115.00000762939453, -82.0)
const PARENT_ROTATION := 0.7853981852531433
const BAND_EDGES := [-24.0, 8.0, 24.0, 48.0, 80.0, 128.0, 192.0, 240.0, 272.0, 296.0, 312.0, 344.0]
const BAND_TOP := -90.0
const BAND_BOTTOM := 270.0
const COVER_DURATION := 0.46
const REVEAL_DURATION := 0.46
const BAND_DELAY := 0.04
const COVER_FADE := 0.06
const TRANSPARENT_WHITE := Color(1.0, 1.0, 1.0, 0.0)
const OPAQUE_BLACK := Color(0.0, 0.0, 0.0, 1.0)

var busy: bool = false
var phase: Phase = Phase.IDLE
var _phase_elapsed: float = 0.0
var _change: Callable
var _generation: int = 0


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 4095
	clip_contents = true
	resized.connect(queue_redraw)


func play(change: Callable) -> void:
	# A second navigation click cannot replace the pending destination.
	if busy or not is_inside_tree() or not change.is_valid():
		return
	_generation += 1
	_change = change
	_phase_elapsed = 0.0
	phase = Phase.COVER
	busy = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	queue_redraw()
	await finished


func cancel() -> void:
	var was_busy := busy
	_generation += 1
	_change = Callable()
	busy = false
	phase = Phase.IDLE
	_phase_elapsed = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)
	queue_redraw()
	# Resolve callers awaiting play(), including cancellation during a callback.
	if was_busy:
		finished.emit()


func _process(delta: float) -> void:
	if not busy:
		return
	_phase_elapsed += maxf(delta, 0.0)
	if phase == Phase.COVER:
		_phase_elapsed = minf(_phase_elapsed, COVER_DURATION)
		queue_redraw()
		if _phase_elapsed >= COVER_DURATION:
			_cover_complete()
	elif phase == Phase.REVEAL:
		_phase_elapsed = minf(_phase_elapsed, REVEAL_DURATION)
		queue_redraw()
		if _phase_elapsed >= REVEAL_DURATION:
			_finish()


func _cover_complete() -> void:
	var session := _generation
	phase = Phase.COVERED
	_phase_elapsed = 0.0
	queue_redraw()
	covered.emit()
	if not busy or session != _generation:
		return
	var change := _change
	_change = Callable()
	if change.is_valid():
		change.call()
	if not busy or session != _generation:
		return
	phase = Phase.REVEAL
	_phase_elapsed = 0.0
	# Discard excess frame time at this boundary. The new screen receives a fully
	# covered frame rather than a partially revealed frame after a long stall.
	queue_redraw()


func _finish() -> void:
	busy = false
	phase = Phase.IDLE
	_change = Callable()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	queue_redraw()
	finished.emit()


func _input(_event: InputEvent) -> void:
	if busy:
		get_viewport().set_input_as_handled()


func _gui_input(_event: InputEvent) -> void:
	if busy:
		accept_event()


func _draw() -> void:
	if not busy:
		return
	for index: int in range(BAND_EDGES.size() - 1):
		var color := get_band_color(index)
		if color.a > 0.0:
			draw_colored_polygon(get_band_polygon(index), color)


func get_band_color(index: int) -> Color:
	if index < 0 or index >= BAND_EDGES.size() - 1 or not busy:
		return TRANSPARENT_WHITE
	if phase == Phase.COVERED:
		return OPAQUE_BLACK
	if phase == Phase.COVER:
		var start := index * BAND_DELAY
		var weight := clampf((_phase_elapsed - start) / COVER_FADE, 0.0, 1.0)
		return TRANSPARENT_WHITE.lerp(OPAQUE_BLACK, weight)
	if phase == Phase.REVEAL:
		var start := 0.0 if index == 0 else index * BAND_DELAY - 0.02
		var end := 0.06 if index == 0 else index * BAND_DELAY + 0.06
		var weight := clampf((_phase_elapsed - start) / (end - start), 0.0, 1.0)
		return OPAQUE_BLACK.lerp(TRANSPARENT_WHITE, weight)
	return TRANSPARENT_WHITE


func get_band_polygon(index: int) -> PackedVector2Array:
	if index < 0 or index >= BAND_EDGES.size() - 1:
		return PackedVector2Array()
	var native_transform := Transform2D(PARENT_ROTATION, PARENT_POSITION)
	var scale_factor := maxf(size.x / NATIVE_SIZE.x, size.y / NATIVE_SIZE.y)
	var origin := (size - NATIVE_SIZE * scale_factor) * 0.5
	var result := PackedVector2Array()
	for point: Vector2 in [Vector2(BAND_EDGES[index], BAND_TOP), Vector2(BAND_EDGES[index + 1], BAND_TOP), Vector2(BAND_EDGES[index + 1], BAND_BOTTOM), Vector2(BAND_EDGES[index], BAND_BOTTOM)]:
		result.append(origin + (native_transform * point) * scale_factor)
	return result


func coverage_at(point: Vector2) -> float:
	# Geometry/color inspection for deterministic resize and keyframe tests.
	var alpha := 0.0
	for index: int in range(BAND_EDGES.size() - 1):
		if Geometry2D.is_point_in_polygon(point, get_band_polygon(index)):
			alpha = maxf(alpha, get_band_color(index).a)
	return alpha


func _exit_tree() -> void:
	cancel()
