# KuroBox interfaces and level format

Target: Godot 4.6, desktop keyboard/mouse. These interfaces separate authoring, deterministic simulation and presentation.

## Ownership

- core/object_catalog.gd: ObjectCatalog, static all_types() -> Array[Dictionary], get_type(type_id: String) -> Dictionary. Reads content/definitions/objects.json. Definitions carry id, label, behavior (wood/bag/plate/door), sprite, color, pushable, punchable, punch_distance. Rendering and editor use this same catalog.
- core/level_codec.gd: LevelCodec, static normalize(data: Dictionary) -> Dictionary, validate(data: Dictionary) -> Array[String], load_file(path: String) -> Dictionary, save_file(path: String, data: Dictionary) -> Error, cells(raw: Array) -> Array[Vector2i]. JSON format v1 below. Invalid files produce explicit errors, not silently repaired playable levels.
- core/board_state.gd: BoardState extends RefCounted. setup(level: Dictionary), level: Dictionary, player: Vector2i, facing: Vector2i, objects: Dictionary (id -> runtime Dictionary), floor_cells/walls/goals: Dictionary[Vector2i, bool], moves: int, punches: int. step(direction: Vector2i) -> Dictionary, punch() -> Dictionary, undo() -> bool, restart(), snapshot() -> Dictionary, is_won() -> bool, preview_punch() -> Vector2i, object_at(cell: Vector2i, include_devices: bool = false) -> String, can_enter(cell: Vector2i) -> bool.
- Commands return changed(bool), event(String walk/push/punch/blocked), object_id(String), from/to(Vector2i), won(bool). Facing changes on attempted movement; invalid moves do not increment steps. Undo restores full state including facing/devices. Punch bags move up to two clear cells; player stays; no chain impulses; goals never stop motion. End-of-command pressure plates recompute doors; occupied doors stay open until empty.
- features/play/board_view.gd: BoardView extends Control; set_board(state: BoardState), set_level_preview(level: Dictionary), animate_result(result: Dictionary, before: Dictionary), screen_to_cell(local_position: Vector2) -> Vector2i. signal cell_pressed(cell: Vector2i, button: int), cell_dragged(cell: Vector2i, button: int). Editable display owns no rules.
- features/editor/level_editor.gd: LevelEditor extends Control; signal test_requested(level: Dictionary), exit_requested, sound_requested(event: String); setup(level: Dictionary = {}), resume_after_test(), get_level() -> Dictionary. Independent editor.tscn supports F6. Shell preserves the editor instance and document while testing a separate BoardState.
- features/shell/main.gd: menus, campaign, pause/completion stack, editor/play mediation, save/settings and audio. No puzzle rules here.

## Level JSON v1

{"schema_version":1,"id":"round_01","title":"FIRST STEP","width":8,"height":6,"floor":[[1,1]],"walls":[],"goals":[[5,2]],"player":[2,2],"facing":[1,0],"objects":[{"id":"box_01","type":"wood","cell":[3,2],"targets":[]}],"metadata":{"chapter":1,"hint":"","solution":[]}}

Solutions use commands U,D,L,R (step), P (punch). Runtime references use stable instance IDs, never node names. Each authored level has a recorded valid solution verified in the actual Godot simulation.

## Scope

8 authored campaign levels, start/select/play/pause/settings/completion, infinite undo/restart, persistent progress. Editor supports irregular floor painting, object palette generated from definitions, brush/erase/rectangle/fill/select-copy-move, width/height, birth/facing, plate-door links, undo/redo, clear validation, JSON import/export, immediate test with document preserved. Save validation is structural, not a solvability proof. Art and sound are replaceable presentation mappings. Repository excludes runtime/cache data.
