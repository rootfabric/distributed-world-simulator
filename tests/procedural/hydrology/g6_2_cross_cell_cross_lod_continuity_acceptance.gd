extends SceneTree

const WorldFeature = preload("res://scripts/simulation/procedural/contracts/world_feature.gd")
const SurfaceCellKey = preload("res://scripts/simulation/procedural/contracts/surface_cell_key.gd")
const CubeSphereAddressing = preload("res://scripts/simulation/procedural/surface/cube_sphere_addressing.gd")
const CasualRiverProvider = preload("res://scripts/simulation/procedural/hydrology/casual_river_provider_v1.gd")
const Fixture = preload("res://tests/procedural/fixtures/g6_2_cross_cell_river_fixture.gd")

const LODS: Array[int] = [2, 4, 8, 12]

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_manifest()
	_test_cross_cell_cross_lod_continuity()
	_finish()


func _test_manifest() -> void:
	var path := "res://config/procedural/g6-2-cross-cell-cross-lod-continuity.v1.json"
	_check(FileAccess.file_exists(path), "G6.2 manifest exists")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary, "G6.2 manifest parses")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g6.2-cross-cell-cross-lod-continuity", "G6.2 checkpoint")
		_check(String(parsed.get("status", "")) == "IMPLEMENTED_CANDIDATE", "G6.2 candidate status")
		_check(String(parsed.get("global_program_revision", "")) == "GLOBAL-P0-2026-08-08-R1", "G6.2 P0 revision")
		var parsed_lods: Array[int] = []
		for lod_value in parsed.get("lod_levels", []):
			parsed_lods.append(int(lod_value))
		_check(parsed_lods == LODS, "G6.2 LOD proof levels pinned")
		var boundaries: Dictionary = parsed.get("architecture_boundaries", {})
		_check(not bool(boundaries.get("surface_cell_is_hydrology_identity", true)), "surface cell excluded from hydrology identity")
		_check(not bool(boundaries.get("lod_is_hydrology_identity", true)), "LOD excluded from hydrology identity")
		_check(not bool(boundaries.get("creates_river_chunk_identity", true)), "no RiverChunk identity")


func _test_cross_cell_cross_lod_continuity() -> void:
	var river: Dictionary = Fixture.river()
	_ok(WorldFeature.validate(river), "G6.2 seam river validates")
	var first: Dictionary = CasualRiverProvider.compile(river)
	_ok(first, "G6.2 provider compiles seam river")
	if not _success(first):
		return

	var first_details: Dictionary = first["details"]
	var canonical_feature_id := String(river["feature_id"])
	var canonical_region_id := String(first_details["fluid_region_id"])
	var canonical_spline_id := String(first_details["river_spline"]["spline_id"])
	var canonical_profile_id := String(first_details["channel_profile"]["profile_id"])
	var canonical_manifest := String(first_details["manifest_hash"])
	var canonical_spline_checksum := String(first_details["river_spline"]["checksum"])
	var canonical_surface_checksum := String(first_details["fluid_surface_descriptor"]["checksum"])
	var addressing = CubeSphereAddressing.new()
	var all_lod_cell_sets: Dictionary = {}

	_check(String(first_details["source_feature_id"]) == canonical_feature_id, "provider retains G5 river semantic owner")
	_check(not first_details.has("surface_cell"), "provider output has no surface-cell canonical field")
	_check(not first_details.has("lod"), "provider output has no LOD canonical field")

	for lod in LODS:
		var cell_tokens: Dictionary = {}
		var faces: Dictionary = {}
		for point_value in first_details["river_spline"]["points_m"]:
			var position: Array = point_value
			var addressed: Dictionary = addressing.direction_to_cell(Fixture.BODY_ID, position, lod)
			_ok(addressed, "river point addressed at LOD %d" % lod)
			if not _success(addressed):
				continue
			var cell: Dictionary = addressed["details"]["cell"]
			cell_tokens[SurfaceCellKey.identity_token(cell)] = true
			faces[String(cell["face"])] = true

		_check(cell_tokens.size() >= 2, "river spans multiple representation cells at LOD %d" % lod)
		_check(faces.has("PX") and faces.has("PZ"), "river crosses PX/PZ cube seam at LOD %d" % lod)
		var sorted_tokens: Array = cell_tokens.keys()
		sorted_tokens.sort()
		all_lod_cell_sets[lod] = sorted_tokens

		# Recompile after representation addressing. G2 cell/LOD work must not
		# perturb canonical G5/G6 geography or reroll any hydrology identity.
		var replay: Dictionary = CasualRiverProvider.compile(Fixture.river())
		_ok(replay, "provider replay after LOD %d addressing" % lod)
		if _success(replay):
			var replay_details: Dictionary = replay["details"]
			_check(String(replay_details["source_feature_id"]) == canonical_feature_id, "FeatureId stable at LOD %d" % lod)
			_check(String(replay_details["fluid_region_id"]) == canonical_region_id, "FluidRegionId stable at LOD %d" % lod)
			_check(String(replay_details["river_spline"]["spline_id"]) == canonical_spline_id, "RiverSpline id stable at LOD %d" % lod)
			_check(String(replay_details["channel_profile"]["profile_id"]) == canonical_profile_id, "channel profile id stable at LOD %d" % lod)
			_check(String(replay_details["manifest_hash"]) == canonical_manifest, "provider manifest stable at LOD %d" % lod)
			_check(String(replay_details["river_spline"]["checksum"]) == canonical_spline_checksum, "canonical spline unchanged at LOD %d" % lod)
			_check(String(replay_details["fluid_surface_descriptor"]["checksum"]) == canonical_surface_checksum, "canonical fluid surface unchanged at LOD %d" % lod)

	_check(all_lod_cell_sets[2] != all_lod_cell_sets[12], "representation cell set changes between LOD 2 and LOD 12")
	_check(String(Fixture.river()["feature_id"]) == canonical_feature_id, "regenerated river keeps FeatureId")
	var final_replay: Dictionary = CasualRiverProvider.compile(Fixture.river())
	_ok(final_replay, "final canonical replay")
	if _success(final_replay):
		_check(String(final_replay["details"]["manifest_hash"]) == canonical_manifest, "final provider result identity unchanged")


func _success(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _ok(result: Dictionary, label: String) -> void:
	_check(_success(result), "%s: %s %s" % [label, String(result.get("error_code", "")), result.get("details", {})])


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("G6.2 cross-cell/cross-LOD continuity: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G6.2 cross-cell/cross-LOD continuity: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
