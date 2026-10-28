extends RefCounted

# Pure static control-point probe for world identity verification. Both sides
# of a networked session sample the same five fixed surface directions through
# the Earth rule pipeline, round the resulting elevations to centimetres and
# hash the integer array, so any seed or rules divergence is detectable without
# exchanging raw terrain data.
const EarthRulePipelineScript = preload(
	"res://scripts/world/planetary/earth_rule_pipeline.gd"
)
const WorldDefinitionScript = preload(
	"res://scripts/world/earth/world_definition.gd"
)

# Five fixed directions: the +X/+Y/+Z axes plus two diagonal directions.
const CONTROL_POINT_DIRECTIONS: Array[Vector3] = [
	Vector3(1.0, 0.0, 0.0),
	Vector3(0.0, 1.0, 0.0),
	Vector3(0.0, 0.0, 1.0),
	Vector3(1.0, 1.0, 1.0),
	Vector3(-1.0, 2.0, -3.0),
]


static func compute(seed_value: int) -> Dictionary:
	var pipeline = EarthRulePipelineScript.new()
	if not pipeline.setup(EarthRulePipelineScript.CONFIG_PATH, seed_value):
		return {}
	var elevation_cm: Array = []
	var points: Array = []
	for direction in CONTROL_POINT_DIRECTIONS:
		var state: Dictionary = pipeline.sample(direction.normalized(), 0)
		var centimetres := _elevation_cm(state)
		elevation_cm.append(centimetres)
		points.append({
			"direction": [direction.x, direction.y, direction.z],
			"elevation_cm": centimetres,
		})
	return {
		"seed": seed_value,
		"point_count": points.size(),
		"elevation_cm": elevation_cm,
		"digest": digest_of(elevation_cm),
	}


static func compute_for_world(world_id: String = WorldDefinitionScript.DEFAULT_WORLD_ID) -> Dictionary:
	var definition := WorldDefinitionScript.load_definition(world_id)
	if definition.is_empty():
		return {}
	return compute(int(definition["seed"]))


static func digest_of(elevation_cm: Array) -> String:
	return WorldDefinitionScript.sha256_hex(WorldDefinitionScript.canonical_json({
		"control_points_elevation_cm": elevation_cm,
	}))


static func _elevation_cm(state: Dictionary) -> int:
	return roundi(float(state.get("elevation_m", 0.0)) * 100.0)
