extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp4_gateway_process.gd"

# Disposable observation barriers only. All values below came from the real
# owner over the authenticated backend; clients cannot submit inventory data.
var _baseline5: Dictionary = {}
var _observed5: Dictionary = {}

func _complete5() -> bool:
	if _observed5.size() != 2 or not _complete4(): return false
	var canonical: Dictionary = _source4.get("material_projection", {}).get("details", {})
	if canonical.is_empty(): return false
	for actor in ["a", "b"]:
		if _observed5[actor] != canonical: return false
	return true

func world_snapshot() -> Dictionary:
	var value: Dictionary = super.world_snapshot()
	value["mvp5"] = {"both_material_baselines_ready": _baseline5.size() == 2, "both_material_observed": _complete5()}
	return value

func handle_client(actor: String, body: Dictionary) -> Dictionary:
	var kind := String(body.get("kind", ""))
	if kind in ["MVP4_PREPARE", "MVP4_EXECUTE"] and _baseline5.size() != 2:
		return Protocol.failure("MVP5_MATERIAL_BASELINES_REQUIRED")
	if not kind.begins_with("MVP5_"): return super.handle_client(actor, body)
	if not bool(client_hello.get(actor, false)): return Protocol.failure("MVP5_HELLO_REQUIRED")
	if kind not in ["MVP5_BASELINE", "MVP5_MATERIAL"]:
		return Protocol.failure("MVP5_UNKNOWN_CLIENT_COMMAND")
	if kind == "MVP5_BASELINE" and (_baseline5.has(actor) or _baseline4.size() != 2):
		return Protocol.failure("MVP5_BASELINE_PHASE_INVALID")
	if kind == "MVP5_MATERIAL" and (_baseline5.size() != 2 or not _complete4()):
		return Protocol.failure("MVP5_TERRAIN_CONVERGENCE_REQUIRED")
	# _owner4 overwrites actor/session with the authenticated peer binding.
	var result: Dictionary = _owner4(actor, {"kind": "MVP5_MATERIAL"})
	if not bool(result.get("success", false)): return result
	var projection: Dictionary = result.get("details", {})
	if kind == "MVP5_BASELINE":
		if int(projection.get("matter_stream_sequence", -1)) != 0:
			return Protocol.failure("MVP5_BASELINE_AFTER_MUTATION")
		_baseline5[actor] = projection.duplicate(true)
	else:
		_observed5[actor] = projection.duplicate(true)
		var refreshed: Dictionary = _refresh_source4(actor)
		if not bool(refreshed.get("success", false)): return refreshed
	return Protocol.success({"kind": kind, "actor": actor, "matter": projection, "snapshot": world_snapshot()})

func base_report(schema: String, passed: bool, graphical: bool) -> Dictionary:
	var value: Dictionary = super.base_report(schema, passed, graphical)
	value["mvp5"] = {"baselines": _baseline5.duplicate(true), "observed": _observed5.duplicate(true), "both_material_observed": _complete5(), "canonical_state_owned": false, "predicate_verified": false}
	return value

func finish_interactive(seam_criterion: bool, error_code: String = "") -> void:
	if error_code.is_empty() and not _complete5(): error_code = "MVP5_MATERIAL_CONVERGENCE_FAILED"
	super.finish_interactive(seam_criterion, error_code)
