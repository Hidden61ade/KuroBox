@tool
extends RefCounted
## Builds a cached border around the union of floor cells.

const ATLAS := preload("res://assets/ui/circuit_all.png")
const TILE_PIXELS := 16
const PADDING_LEFT := 11.0 / TILE_PIXELS
const PADDING_TOP := 11.0 / TILE_PIXELS
const PADDING_RIGHT := 11.0 / TILE_PIXELS
const PADDING_BOTTOM := 13.0 / TILE_PIXELS
const PADDING_TILES := PADDING_BOTTOM

# Each direction points from an empty border cell toward an adjacent floor cell.
const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const STRAIGHT_ATLAS := {
	1: Vector2i(5, 6),
	2: Vector2i(4, 5),
	4: Vector2i(5, 4),
	8: Vector2i(6, 5),
}
const CORNERS := [
	{"floor_offset": Vector2i(1, 1), "side_mask": 6, "atlas": Vector2i(4, 4)},
	{"floor_offset": Vector2i(-1, 1), "side_mask": 12, "atlas": Vector2i(6, 4)},
	{"floor_offset": Vector2i(1, -1), "side_mask": 3, "atlas": Vector2i(4, 6)},
	{"floor_offset": Vector2i(-1, -1), "side_mask": 9, "atlas": Vector2i(6, 6)},
]

# Inner-to-outer pixel profiles sampled from the four straight atlas tiles.
# They supply the joins for concave contours that the original atlas lacks.
const FACE := Color("6d758d")
const EDGE := Color("333941")
const LIGHT := Color("8b93af")
const SHADE := Color("4a5462")
const PROFILES := [
	[FACE, FACE, FACE, FACE, FACE, EDGE, LIGHT, LIGHT, LIGHT, LIGHT, SHADE, SHADE, EDGE],
	[FACE, FACE, FACE, FACE, FACE, EDGE, LIGHT, LIGHT, LIGHT, LIGHT, EDGE],
	[FACE, FACE, FACE, EDGE, SHADE, SHADE, LIGHT, LIGHT, LIGHT, LIGHT, EDGE],
	[FACE, FACE, FACE, FACE, FACE, EDGE, LIGHT, LIGHT, LIGHT, LIGHT, EDGE],
]
const NARROW_RAIL_PIXELS := 6

static var _join_textures: Dictionary[int, Texture2D] = {}
var _atlas_tiles: Array[Dictionary] = []
var _joined_tiles: Array[Dictionary] = []


func setup(floors: Array) -> void:
	_atlas_tiles.clear()
	_joined_tiles.clear()
	var floor_cells: Dictionary[Vector2i, bool] = {}
	for value: Variant in floors:
		if value is Vector2i:
			floor_cells[value] = true
		elif value is Array and value.size() == 2:
			if (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float):
				floor_cells[Vector2i(int(value[0]), int(value[1]))] = true

	var exterior: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in floor_cells:
		for direction: Vector2i in DIRECTIONS:
			if not floor_cells.has(cell + direction):
				exterior[cell + direction] = true
		for corner: Dictionary in CORNERS:
			var neighbor: Vector2i = cell - corner.floor_offset
			if not floor_cells.has(neighbor):
				exterior[neighbor] = true

	for cell: Vector2i in exterior:
		var side_mask := 0
		for side: int in range(DIRECTIONS.size()):
			if floor_cells.has(cell + DIRECTIONS[side]):
				side_mask |= 1 << side
		for corner: Dictionary in CORNERS:
			if (side_mask & int(corner.side_mask)) == 0 and floor_cells.has(cell + corner.floor_offset):
				_add_atlas_tile(cell, corner.atlas)
		if STRAIGHT_ATLAS.has(side_mask):
			_add_atlas_tile(cell, STRAIGHT_ATLAS[side_mask])
		elif side_mask != 0:
			_joined_tiles.append({"cell": cell, "texture": _join_texture(side_mask)})


func draw_rim(canvas: CanvasItem, origin: Vector2, cell_size: float) -> void:
	var size := Vector2.ONE * cell_size
	for tile: Dictionary in _atlas_tiles:
		canvas.draw_texture_rect_region(ATLAS, Rect2(origin + Vector2(tile.cell) * cell_size, size), tile.region)
	for tile: Dictionary in _joined_tiles:
		canvas.draw_texture_rect(tile.texture, Rect2(origin + Vector2(tile.cell) * cell_size, size), false)


func _add_atlas_tile(cell: Vector2i, atlas_cell: Vector2i) -> void:
	var region := Rect2(Vector2(atlas_cell) * TILE_PIXELS, Vector2.ONE * TILE_PIXELS)
	_atlas_tiles.append({"cell": cell, "region": region})


static func _join_texture(side_mask: int) -> Texture2D:
	if _join_textures.has(side_mask):
		return _join_textures[side_mask]

	var rail_widths := PackedInt32Array()
	for side: int in range(DIRECTIONS.size()):
		var width := 0
		if (side_mask & (1 << side)) != 0:
			width = PROFILES[side].size()
			# Keep four native pixels clear in an opposing pair of rails.
			if (side_mask & (1 << ((side + 2) % 4))) != 0:
				width = NARROW_RAIL_PIXELS
		rail_widths.append(width)

	var image := Image.create_empty(TILE_PIXELS, TILE_PIXELS, false, Image.FORMAT_RGBA8)
	for y: int in range(TILE_PIXELS):
		for x: int in range(TILE_PIXELS):
			var distances := PackedInt32Array([y, TILE_PIXELS - 1 - x, TILE_PIXELS - 1 - y, x])
			var deepest_side := -1
			var depth := 0
			for side: int in range(DIRECTIONS.size()):
				var remaining := rail_widths[side] - distances[side]
				if remaining > depth:
					depth = remaining
					deepest_side = side
			if deepest_side >= 0:
				var profile: Array = PROFILES[deepest_side]
				var sample := roundi(float(distances[deepest_side]) * float(profile.size() - 1) / float(rail_widths[deepest_side] - 1))
				image.set_pixel(x, y, profile[sample])
	var texture := ImageTexture.create_from_image(image)
	_join_textures[side_mask] = texture
	return texture
