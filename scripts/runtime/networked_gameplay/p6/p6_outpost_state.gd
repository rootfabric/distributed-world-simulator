extends RefCounted

## P6.7 canonical shared outpost state container.
##
## Holds the canonical outpost-world-state domain declared in
## p6_ownership_map.gd ("p6-domain/outpost-world-state"). This class is a PURE
## state container: it never touches files, the gateway, or identity —
## persistence is delegated exclusively to p6_persistence_owner.gd (the single
## persistence owner "p6-owner/directory-one-writer").
##
## Determinism contract:
## - serialize() emits a canonically ordered Dictionary (recursive key-sorted)
##   so canonical JSON — and therefore compute_checksum() — is byte-stable
##   across construction orders and processes;
## - deserialize() is fail-closed: any schema/type violation rejects the whole
##   payload and leaves the current state untouched;
## - apply_delta() validates before mutating, so a rejected delta never
##   partially applies.

const SCHEMA := "planet_simulator.p6_outpost_state.v1"
const STATE_VERSION := 1

const OP_PLACE_BLOCK := "place_block"
const OP_BREAK_BLOCK := "break_block"
const OP_CONTAINER_CREATE := "container_create"
const OP_CONTAINER_REMOVE := "container_remove"
const OP_CONTAINER_ADD_ITEM := "container_add_item"
const OP_CONTAINER_REMOVE_ITEM := "container_remove_item"
const OP_PLAYER_MOVE := "player_move"
const OP_SET_TICK := "set_tick"

const ALLOWED_FIELDS: Array = [
	"schema",
	"version",
	"world_seed",
	"tick",
	"blocks",
	"containers",
	"player_positions",
]

var blocks: Dictionary = {}            # pos_key ("x,y,z") -> block_type (String)
var containers: Dictionary = {}        # container_id -> {"items": Array[String]}
var player_positions: Dictionary = {}  # logical player id -> {"pos": [x,y,z], "rot": float}
var world_seed: int = 0
var tick: int = 0

var _deltas_applied: int = 0
var _deltas_rejected: int = 0
var _last_error_code: String = ""


## --- Typed field mutators (non-delta conveniences for sim-side setup) -------

func set_world_seed(seed_value: int) -> void:
	world_seed = int(seed_value)


func advance_tick(steps: int = 1) -> void:
	tick = int(tick) + int(steps)


## --- Serialization ----------------------------------------------------------

## Canonical, deterministic serialization: every Dictionary is rebuilt with
## sorted keys (recursively) so canonical JSON is byte-stable.
func serialize() -> Dictionary:
	var blocks_out: Dictionary = {}
	var block_keys: Array = blocks.keys()
	block_keys.sort()
	for key_value in block_keys:
		var pos_key := String(key_value)
		blocks_out[pos_key] = String(blocks[pos_key])
	var containers_out: Dictionary = {}
	var container_keys: Array = containers.keys()
	container_keys.sort()
	for key_value in container_keys:
		var container_id := String(key_value)
		var row: Dictionary = Dictionary(containers[container_id])
		var items: Array = (row.get("items", []) as Array).duplicate(true)
		items.sort()
		containers_out[container_id] = {"items": items}
	var positions_out: Dictionary = {}
	var player_keys: Array = player_positions.keys()
	player_keys.sort()
	for key_value in player_keys:
		var player_id := String(key_value)
		var row: Dictionary = Dictionary(player_positions[player_id])
		positions_out[player_id] = {
			"pos": _pos_array(row.get("pos", [])),
			"rot": float(row.get("rot", 0.0)),
		}
	return canonical_copy({
		"schema": SCHEMA,
		"version": STATE_VERSION,
		"world_seed": int(world_seed),
		"tick": int(tick),
		"blocks": blocks_out,
		"containers": containers_out,
		"player_positions": positions_out,
	})


## Fail-closed schema check + commit. On ANY violation returns false, records
## the error code, and leaves the current state completely untouched.
func deserialize(data: Dictionary) -> bool:
	if not _reject_unless(data != null and not data.is_empty(), "EMPTY_PAYLOAD"):
		return false
	for field in data.keys():
		if not ALLOWED_FIELDS.has(String(field)):
			return _reject("UNKNOWN_FIELD")
	if String(data.get("schema", "")) != SCHEMA:
		return _reject("SCHEMA_MISMATCH")
	if not _is_intlike(data.get("version", null)) or _as_int(data["version"]) != STATE_VERSION:
		return _reject("VERSION_MISMATCH")
	if not _is_intlike(data.get("world_seed", null)):
		return _reject("BAD_WORLD_SEED")
	if not _is_intlike(data.get("tick", null)):
		return _reject("BAD_TICK")
	var blocks_in: Variant = data.get("blocks", null)
	if typeof(blocks_in) != TYPE_DICTIONARY:
		return _reject("BAD_BLOCKS")
	var blocks_parsed := _parse_blocks(Dictionary(blocks_in))
	if blocks_parsed.is_empty() and not Dictionary(blocks_in).is_empty():
		return _reject(_last_error_code)
	var containers_in: Variant = data.get("containers", null)
	if typeof(containers_in) != TYPE_DICTIONARY:
		return _reject("BAD_CONTAINERS")
	var containers_parsed := _parse_containers(Dictionary(containers_in))
	if containers_parsed.is_empty() and not Dictionary(containers_in).is_empty():
		return _reject(_last_error_code)
	var positions_in: Variant = data.get("player_positions", null)
	if typeof(positions_in) != TYPE_DICTIONARY:
		return _reject("BAD_PLAYER_POSITIONS")
	var positions_parsed := _parse_positions(Dictionary(positions_in))
	if positions_parsed.is_empty() and not Dictionary(positions_in).is_empty():
		return _reject(_last_error_code)
	# Commit only after every field validated.
	blocks = blocks_parsed
	containers = containers_parsed
	player_positions = positions_parsed
	world_seed = _as_int(data["world_seed"])
	tick = _as_int(data["tick"])
	return true


## SHA-256 of the canonical JSON form of serialize().
func compute_checksum() -> String:
	return checksum_of_data(serialize())


## --- Deltas -----------------------------------------------------------------

## Apply one validated mutation delta. Supported ops:
##   place_block {pos:[x,y,z], block_type:String}
##   break_block {pos:[x,y,z]}
##   container_create {container_id:String}
##   container_remove {container_id:String}
##   container_add_item {container_id:String, item:String}
##   container_remove_item {container_id:String, item:String}
##   player_move {player_id:String, pos:[x,y,z], rot:float}
##   set_tick {value:int}
## Fail-closed: validation happens before any mutation.
func apply_delta(delta: Dictionary) -> bool:
	if typeof(delta) != TYPE_DICTIONARY or delta.is_empty():
		return _reject("EMPTY_DELTA")
	var op := String(delta.get("op", ""))
	match op:
		OP_PLACE_BLOCK:
			return _apply_place_block(delta)
		OP_BREAK_BLOCK:
			return _apply_break_block(delta)
		OP_CONTAINER_CREATE:
			return _apply_container_create(delta)
		OP_CONTAINER_REMOVE:
			return _apply_container_remove(delta)
		OP_CONTAINER_ADD_ITEM:
			return _apply_container_add_item(delta)
		OP_CONTAINER_REMOVE_ITEM:
			return _apply_container_remove_item(delta)
		OP_PLAYER_MOVE:
			return _apply_player_move(delta)
		OP_SET_TICK:
			return _apply_set_tick(delta)
	return _reject("UNKNOWN_OP")


## --- Accessors --------------------------------------------------------------

func has_block(pos_key: String) -> bool:
	return blocks.has(pos_key)


func block_type_at(pos_key: String) -> String:
	return String(blocks.get(pos_key, ""))


func block_count() -> int:
	return blocks.size()


func container_exists(container_id: String) -> bool:
	return containers.has(container_id)


func container_items(container_id: String) -> Array:
	if not containers.has(container_id):
		return []
	return (Dictionary(containers[container_id]).get("items", []) as Array).duplicate(true)


func has_player(player_id: String) -> bool:
	return player_positions.has(player_id)


func player_position(player_id: String) -> Dictionary:
	if not player_positions.has(player_id):
		return {}
	return Dictionary(player_positions[player_id]).duplicate(true)


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"block_count": blocks.size(),
		"container_count": containers.size(),
		"player_count": player_positions.size(),
		"tick": int(tick),
		"world_seed": int(world_seed),
		"deltas_applied": _deltas_applied,
		"deltas_rejected": _deltas_rejected,
		"last_error_code": _last_error_code,
	}


## --- Canonical helpers (shared with the persistence owner) ------------------

## Recursive key-sorted copy: insertion order of the source is irrelevant.
static func canonical_copy(value: Variant) -> Variant:
	if value is Dictionary:
		var source: Dictionary = value
		var keys: Array = source.keys()
		keys.sort()
		var ordered: Dictionary = {}
		for key in keys:
			ordered[key] = canonical_copy(source[key])
		return ordered
	if value is Array:
		var items: Array = []
		for element in (value as Array):
			items.append(canonical_copy(element))
		return items
	return value


## Canonical JSON: no whitespace, keys in sorted order.
static func canonical_json(data: Dictionary) -> String:
	return JSON.stringify(canonical_copy(data), "", false)


## SHA-256 (hex) of the canonical JSON of a serialized state dictionary.
static func checksum_of_data(data: Dictionary) -> String:
	return _sha256_hex(canonical_json(data).to_utf8_buffer())


static func position_key(x: int, y: int, z: int) -> String:
	return "%d,%d,%d" % [int(x), int(y), int(z)]


## --- Delta internals --------------------------------------------------------

func _apply_place_block(delta: Dictionary) -> bool:
	var pos_result := _validated_pos(delta)
	if pos_result.is_empty():
		return false
	var block_type := String(delta.get("block_type", ""))
	if block_type.is_empty():
		return _reject("BAD_BLOCK_TYPE")
	var pos_key: String = pos_result["pos_key"]
	if blocks.has(pos_key):
		return _reject("POSITION_OCCUPIED")
	blocks[pos_key] = block_type
	return _accept()


func _apply_break_block(delta: Dictionary) -> bool:
	var pos_result := _validated_pos(delta)
	if pos_result.is_empty():
		return false
	var pos_key: String = pos_result["pos_key"]
	if not blocks.has(pos_key):
		return _reject("UNKNOWN_BLOCK")
	blocks.erase(pos_key)
	return _accept()


func _apply_container_create(delta: Dictionary) -> bool:
	var container_id := String(delta.get("container_id", ""))
	if container_id.is_empty():
		return _reject("BAD_CONTAINER_ID")
	if containers.has(container_id):
		return _reject("CONTAINER_ALREADY_EXISTS")
	containers[container_id] = {"items": []}
	return _accept()


func _apply_container_remove(delta: Dictionary) -> bool:
	var container_id := String(delta.get("container_id", ""))
	if not containers.has(container_id):
		return _reject("UNKNOWN_CONTAINER")
	containers.erase(container_id)
	return _accept()


func _apply_container_add_item(delta: Dictionary) -> bool:
	var container_id := String(delta.get("container_id", ""))
	if not containers.has(container_id):
		return _reject("UNKNOWN_CONTAINER")
	var item := String(delta.get("item", ""))
	if item.is_empty():
		return _reject("BAD_ITEM")
	var row: Dictionary = Dictionary(containers[container_id])
	var items: Array = (row.get("items", []) as Array).duplicate(true)
	items.append(item)
	containers[container_id] = {"items": items}
	return _accept()


func _apply_container_remove_item(delta: Dictionary) -> bool:
	var container_id := String(delta.get("container_id", ""))
	if not containers.has(container_id):
		return _reject("UNKNOWN_CONTAINER")
	var item := String(delta.get("item", ""))
	var row: Dictionary = Dictionary(containers[container_id])
	var items: Array = (row.get("items", []) as Array).duplicate(true)
	var index := items.find(item)
	if index == -1:
		return _reject("UNKNOWN_ITEM")
	items.remove_at(index)
	containers[container_id] = {"items": items}
	return _accept()


func _apply_player_move(delta: Dictionary) -> bool:
	var player_id := String(delta.get("player_id", ""))
	if player_id.is_empty():
		return _reject("BAD_PLAYER_ID")
	var pos_result := _validated_pos(delta)
	if pos_result.is_empty():
		return false
	var rot_value: Variant = delta.get("rot", 0.0)
	if typeof(rot_value) != TYPE_FLOAT and typeof(rot_value) != TYPE_INT:
		return _reject("BAD_ROT")
	player_positions[player_id] = {
		"pos": (pos_result["pos"] as Array).duplicate(true),
		"rot": float(rot_value),
	}
	return _accept()


func _apply_set_tick(delta: Dictionary) -> bool:
	var value: Variant = delta.get("value", null)
	if not _is_intlike(value) or _as_int(value) < 0:
		return _reject("BAD_TICK_VALUE")
	tick = _as_int(value)
	return _accept()


## --- Validation internals ---------------------------------------------------

## Validates delta["pos"]; returns {} on failure (error already recorded) or
## {"pos": [int, int, int], "pos_key": "x,y,z"} on success.
func _validated_pos(delta: Dictionary) -> Dictionary:
	var pos_value: Variant = delta.get("pos", null)
	if typeof(pos_value) != TYPE_ARRAY:
		_reject("BAD_POS")
		return {}
	var pos_array: Array = pos_value
	if pos_array.size() != 3:
		_reject("BAD_POS")
		return {}
	var coords: Array = []
	for coord_value in pos_array:
		if not _is_intlike(coord_value):
			_reject("BAD_POS")
			return {}
		coords.append(_as_int(coord_value))
	return {"pos": coords, "pos_key": position_key(int(coords[0]), int(coords[1]), int(coords[2]))}


func _parse_blocks(source: Dictionary) -> Dictionary:
	var parsed: Dictionary = {}
	for key_value in source.keys():
		var pos_key := String(key_value)
		if not _is_pos_key(pos_key):
			_reject("BAD_POS_KEY")
			return {}
		var block_type := String(source[key_value])
		if block_type.is_empty():
			_reject("BAD_BLOCK_TYPE")
			return {}
		parsed[pos_key] = block_type
	return parsed


func _parse_containers(source: Dictionary) -> Dictionary:
	var parsed: Dictionary = {}
	for key_value in source.keys():
		var container_id := String(key_value)
		if container_id.is_empty():
			_reject("BAD_CONTAINER_ID")
			return {}
		var row_value: Variant = source[key_value]
		if typeof(row_value) != TYPE_DICTIONARY:
			_reject("BAD_CONTAINER_ROW")
			return {}
		var row: Dictionary = row_value
		for row_field in row.keys():
			if String(row_field) != "items":
				_reject("UNKNOWN_CONTAINER_FIELD")
				return {}
		var items_value: Variant = row.get("items", null)
		if typeof(items_value) != TYPE_ARRAY:
			_reject("BAD_ITEMS")
			return {}
		var items: Array = []
		for item_value in (items_value as Array):
			if typeof(item_value) != TYPE_STRING or String(item_value).is_empty():
				_reject("BAD_ITEM")
				return {}
			items.append(String(item_value))
		parsed[container_id] = {"items": items}
	return parsed


func _parse_positions(source: Dictionary) -> Dictionary:
	var parsed: Dictionary = {}
	for key_value in source.keys():
		var player_id := String(key_value)
		if player_id.is_empty():
			_reject("BAD_PLAYER_ID")
			return {}
		var row_value: Variant = source[key_value]
		if typeof(row_value) != TYPE_DICTIONARY:
			_reject("BAD_POSITION_ROW")
			return {}
		var row: Dictionary = row_value
		for row_field in row.keys():
			var field_name := String(row_field)
			if field_name != "pos" and field_name != "rot":
				_reject("UNKNOWN_POSITION_FIELD")
				return {}
		var pos_value: Variant = row.get("pos", null)
		if typeof(pos_value) != TYPE_ARRAY or (pos_value as Array).size() != 3:
			_reject("BAD_POS")
			return {}
		var coords: Array = []
		for coord_value in (pos_value as Array):
			if not _is_intlike(coord_value):
				_reject("BAD_POS")
				return {}
			coords.append(_as_int(coord_value))
		var rot_value: Variant = row.get("rot", 0.0)
		if typeof(rot_value) != TYPE_FLOAT and typeof(rot_value) != TYPE_INT:
			_reject("BAD_ROT")
			return {}
		parsed[player_id] = {"pos": coords, "rot": float(rot_value)}
	return parsed


func _is_pos_key(pos_key: String) -> bool:
	var parts := pos_key.split(",")
	if parts.size() != 3:
		return false
	for part in parts:
		if not _is_intlike(part):
			return false
	return true


## Accepts GDScript ints, integral JSON floats (1.0), and numeric strings.
static func _is_intlike(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		var f := float(value)
		return is_equal_approx(f, float(int(f)))
	if typeof(value) == TYPE_STRING:
		return value.is_valid_int()
	return false


static func _as_int(value: Variant) -> int:
	if typeof(value) == TYPE_STRING:
		return int(String(value).to_int())
	return int(value)


static func _pos_array(value: Variant) -> Array:
	var out: Array = [0, 0, 0]
	if typeof(value) == TYPE_ARRAY and (value as Array).size() == 3:
		for i in range(3):
			var coord: Variant = (value as Array)[i]
			out[i] = _as_int(coord) if _is_intlike(coord) else 0
	return out


static func _sha256_hex(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()


## --- Result bookkeeping -----------------------------------------------------

func _accept() -> bool:
	_deltas_applied = int(_deltas_applied) + 1
	_last_error_code = ""
	return true


func _reject(error_code: String) -> bool:
	_deltas_rejected = int(_deltas_rejected) + 1
	_last_error_code = error_code
	return false


func _reject_unless(condition: bool, error_code: String) -> bool:
	if condition:
		return true
	return _reject(error_code)
