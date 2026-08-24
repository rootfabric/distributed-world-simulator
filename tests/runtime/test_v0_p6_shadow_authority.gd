extends SceneTree

const ProjectionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const ShadowScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_shadow_authority.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6-r3-shadow][FAIL] %s" % message)


func _init() -> void:
	var projection = ProjectionScript.new()
	var configured: Dictionary = projection.configure_from_canonical_sources({
		"gameplay": {"revision": 1},
		"item_graph": {"revision": 2},
		"construction": {"revision": 3},
	})
	_assert(bool(configured.get("success", false)), "projection setup failed")

	var shadow = ShadowScript.new()
	var result: Dictionary = shadow.configure(projection)
	_assert(bool(result.get("success", false)), "shadow configure failed")
	_assert(shadow.get_checksum() == projection.compute_checksum(), "shadow checksum differs from projection")
	_assert(String(shadow.get_report()["persistence_owner"]) == "EXTERNAL", "shadow still claims persistence ownership")
	_assert(not bool(shadow.get_report()["private_canonical_truth"]), "shadow claims private truth")

	var defensive = shadow.get_projection()
	_assert(defensive != null, "shadow projection copy missing")
	_assert(not defensive.apply_delta({"op": "place_block"}), "defensive projection accepted canonical mutation")
	_assert(shadow.get_checksum() == projection.compute_checksum(), "defensive-copy mutation changed shadow")

	for result_value in [
		shadow.apply_delta({"op": "place_block"}),
		shadow.persist_state(),
		shadow.deserialize({}),
	]:
		var write_result: Dictionary = result_value
		_assert(not bool(write_result.get("success", false)) and String(write_result.get("error_code", "")) == ShadowScript.ERR_SHADOW_CANNOT_WRITE, "shadow write surface did not fail closed")

	var promotion: Dictionary = shadow.promote_to_active()
	_assert(not bool(promotion.get("success", false)), "P6 shadow promoted itself to active")
	_assert(String(promotion.get("error_code", "")) == ShadowScript.ERR_PROMOTION_REQUIRES_CANONICAL_TRANSFER, "promotion rejection code mismatch")

	if failures.is_empty():
		print("[p6-r3-shadow] all %d assertions passed" % assertions)
		print("[p6-r3-shadow][stage] SHADOW_READ_ONLY_CANONICAL_TRANSFER_REQUIRED_PASS")
		quit(0)
	else:
		print("[p6-r3-shadow] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)
