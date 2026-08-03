extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")

const SCHEMA := "planet_simulator.construction_multiplayer_state_bundle.v1"
const FIELDS: Array[String] = ["schema", "server_generation", "items", "constructs", "checksum"]

static func create(server_generation: int, items: Array, constructs: Array) -> Dictionary:
	var sorted_items := items.duplicate(true); sorted_items.sort_custom(func(a,b): return String(a.get("item_instance_id", "")) < String(b.get("item_instance_id", "")))
	var sorted_constructs := constructs.duplicate(true); sorted_constructs.sort_custom(func(a,b): return String(a.get("construct_id", "")) < String(b.get("construct_id", "")))
	var bundle := {"schema": SCHEMA, "server_generation": server_generation, "items": sorted_items, "constructs": sorted_constructs, "checksum": ""}; bundle["checksum"] = compute_checksum(bundle); return bundle

static func validate(bundle: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(bundle, FIELDS); if not bool(exact.get("success", false)): return exact
	if bundle.get("schema") != SCHEMA or not UtilsScript.is_json_integer(bundle.get("server_generation")) or int(bundle["server_generation"]) < 0: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_STATE_BUNDLE")
	if typeof(bundle.get("items")) != TYPE_ARRAY or typeof(bundle.get("constructs")) != TYPE_ARRAY: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_STATE_COLLECTION")
	var previous := ""
	for item in bundle["items"]:
		if typeof(item) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_STATE_ITEM")
		var checked := ProjectionScript.validate(item); if not bool(checked.get("success", false)): return checked
		var id := String(item["item_instance_id"]); if not previous.is_empty() and id <= previous: return ParametricUtils.failure("NON_CANONICAL_CONSTRUCTION_MULTIPLAYER_STATE_ITEMS")
		previous = id
	previous = ""
	for snapshot in bundle["constructs"]:
		if typeof(snapshot) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_STATE_CONSTRUCT")
		var checked := SnapshotScript.validate(snapshot); if not bool(checked.get("success", false)): return checked
		var id := String(snapshot["construct_id"]); if not previous.is_empty() and id <= previous: return ParametricUtils.failure("NON_CANONICAL_CONSTRUCTION_MULTIPLAYER_STATE_CONSTRUCTS")
		previous = id
	if String(bundle.get("checksum", "")) != compute_checksum(bundle): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_STATE_BUNDLE_CHECKSUM_MISMATCH")
	return ParametricUtils.success()

static func compute_checksum(bundle: Dictionary) -> String:
	var payload := bundle.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
