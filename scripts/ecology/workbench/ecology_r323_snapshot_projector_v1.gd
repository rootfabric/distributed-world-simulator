extends RefCounted
## ECO ARCH2 A14.6 R3.2.3: pure CPU-only snapshot projection.
## Called ONLY after the worker fully validates the finished canonical
## Runtime. No Node/SceneTree/RenderServer APIs, no canonical writes.
## This is an exact read-only projection of ExperimentController.get_snapshot
## (including per-individual hashes), performed OFF the main thread.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const LifeState = preload("res://scripts/research/ecology/v2/organism_life_state_v1.gd")
const OrganismState = preload("res://scripts/research/ecology/v2/organism_state_v1.gd")

const SCHEMA := "dws.ecology.a14-6-r323-snapshot-projection.v1"

static func project_validated(state: Dictionary, manifest: Dictionary) -> Dictionary:
	# The caller already executed Runtime.validate(state) and must NOT
	# publish this DTO except together with its admitted canonical state.
	if String(manifest.get("mode", "")) != "LAB" or state.is_empty() \
			or not state.has("population") or not state.population is Array \
			or not state.has("field") or not state.field is Dictionary \
			or not state.has("integrity_hash") or not state.has("tick") \
			or not manifest.has("environment") or not manifest.environment is Dictionary:
		return {}
	var environment: Dictionary = manifest.environment
	if not environment.has("spatial") or not environment.spatial is Dictionary \
			or not environment.has("zones") or not environment.zones is Array \
			or environment.zones.is_empty():
		return {}
	var spatial: Dictionary = environment.spatial
	var total: int = int(spatial.get("width", 0)) * int(spatial.get("depth", 0))
	if total <= 0:
		return {}
	var hashes: Array = []
	var by_id := {}
	for entry in state.population:
		var entity: Dictionary = entry.state
		hashes.append({
			"individual_id": entity.individual_id,
			"life_state_hash": LifeState.state_hash(entity, entry.blueprint),
			"development_biological_hash": OrganismState.biological_hash(entity.development),
		})
		by_id[entity.individual_id] = entry
	var views: Array = []
	var depths := {}
	for entry in state.population:
		var entity: Dictionary = entry.state
		var individual_id: String = String(entity.individual_id)
		var parent_id := ""
		if entity.origin_kind == "PARENT_TRANSFER" and not entity.origin_receipt.is_empty():
			parent_id = String(entity.origin_receipt.parent_id)
		var cell_index: int = _cell_index(state.field, entity.position_mm)
		if cell_index < 0:
			return {}
		var zone_index: int = mini(environment.zones.size() - 1,
			int(cell_index * environment.zones.size() / total))
		views.append({
			"individual_id": individual_id,
			"position_mm": [int(entity.position_mm[0]), int(entity.position_mm[1]),
				int(entity.position_mm[2])],
			"alive": bool(entity.alive),
			"zone_id": String(environment.zones[zone_index].id),
			"development_summary": {
				"module_count": int(entity.development.modules.size()),
				"age_ticks": int(entity.age_ticks),
			},
			"parent_id": parent_id,
			"origin_kind": String(entity.origin_kind),
			"lineage_depth": _depth(individual_id, by_id, depths),
		})
	var feedback: Dictionary = Runtime.feedback_view(state)
	var field_hash: String = Field.state_hash(state.field)
	var feedback_hash: String = C.digest(feedback)
	if field_hash.is_empty() or feedback_hash.is_empty():
		return {}
	# Exact shape of Controller.get_snapshot(), excluding transient worker
	# metadata. The authoritative integrity_hash was fully validated before
	# this method; no second full Runtime.validate is required on GUI.
	return {
		"success": true,
		"status": "RUNNING",
		"tick": int(state.tick),
		"field_hash": field_hash,
		"population": hashes,
		"feedback_hash": feedback_hash,
		"canonical_state_hash": String(state.integrity_hash),
		"presentation": views,
	}

static func _depth(individual_id: String, by_id: Dictionary, memo: Dictionary) -> int:
	if memo.has(individual_id):
		return int(memo[individual_id])
	var depth := 0
	var entry: Dictionary = by_id.get(individual_id, {})
	if not entry.is_empty() \
			and entry.state.origin_kind == "PARENT_TRANSFER" \
			and not entry.state.origin_receipt.is_empty():
		var parent_id := String(entry.state.origin_receipt.parent_id)
		if by_id.has(parent_id):
			depth = 1 + _depth(parent_id, by_id, memo)
		else:
			depth = 1
	memo[individual_id] = depth
	return depth

static func _cell_index(field: Dictionary, position: Array) -> int:
	var x: int = int(position[0]) - int(field.origin_mm[0])
	var z: int = int(position[2]) - int(field.origin_mm[2])
	var size: int = int(field.cell_size_mm)
	var width: int = int(field.width)
	var depth: int = int(field.depth)
	if size <= 0 or x < 0 or z < 0 or x >= width * size or z >= depth * size:
		return -1
	return int(z / size) * width + int(x / size)
