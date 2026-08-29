extends SceneTree

const Contract = preload("res://scripts/runtime/seamless/sm0/sm0_p10_view_contract.gd")
const Composer = preload("res://scripts/runtime/seamless/sm0/sm0_p10_multi_authority_view_composer.gd")

const A := "authority/sm0/a"
const B := "authority/sm0/b"
const C := "authority/sm0/c"
const EXPECTED_ASSERTIONS := 91

var _assertions := 0
var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var composer = Composer.new()
	_check_error(composer.setup("authority/unknown", 4096), "SM0_P10_COMPOSER_AUTHORITY_INVALID", "invalid composer authority rejected")
	_check_error(composer.setup(B, 32), "SM0_P10_COMPOSER_BUDGET_INVALID", "undersized default budget rejected")
	_check_success(composer.setup(B, 5000), "composer setup")

	var a1 := _snapshot_a(1, 1, false, "FOREIGN")
	var b1 := _snapshot_b(1, 1, "LOCAL")
	var c1 := _snapshot_c(1, 1, "FOREIGN")
	_check_success(Contract.validate(a1), "A snapshot validates")
	_check_success(Contract.validate(b1), "B snapshot validates")
	_check_success(Contract.validate(c1), "C snapshot validates")
	var checksum_bad := a1.duplicate(true)
	checksum_bad["checksum"] = "bad"
	_check_error(Contract.validate(checksum_bad), "SM0_P10_CHECKSUM_MISMATCH", "checksum mutation rejected")
	var duplicate_entities := [Contract.entity("player/a", "PLAYER", _v(-12,0,0), 90, 1), Contract.entity("player/a", "PLAYER", _v(-11,0,0), 80, 2)]
	var duplicate_snapshot := Contract.create_snapshot(A, 1, "FOREIGN", 1, 1, duplicate_entities, [])
	_check_error(Contract.validate(duplicate_snapshot), "SM0_P10_ENTITY_DUPLICATE", "duplicate entity rejected")

	var wrong_role := _snapshot_a(1, 1, false, "LOCAL")
	_check_error(composer.accept_projection(wrong_role), "SM0_P10_SOURCE_ROLE_MISMATCH", "foreign source cannot claim local role")
	_check_success(composer.accept_projection(a1), "accept A")
	_check_success(composer.accept_projection(b1), "accept B")
	_check_success(composer.accept_projection(c1), "accept C")
	_check(composer.source_count() == 3, "three sources stored")
	_check(composer.source_available(A) and composer.source_available(B) and composer.source_available(C), "three sources available")

	var replay := composer.accept_projection(a1)
	_check_success(replay, "exact source replay accepted")
	_check(bool(Dictionary(replay.get("details", {})).get("replay", false)), "exact replay marked")
	var same_sequence_mutation := _snapshot_a(1, 1, true, "FOREIGN")
	_check_error(composer.accept_projection(same_sequence_mutation), "SM0_P10_SOURCE_SAME_SEQUENCE_MUTATION", "same-sequence mutation rejected")

	var initial := composer.compose_view(_v(0,0,0), 100.0, 5000)
	_check_success(initial, "initial composition")
	var initial_details: Dictionary = Dictionary(initial.get("details", {}))
	_check(Array(initial_details.get("sources_used", [])).size() == 3, "three projection sources composed")
	_check(Array(initial_details.get("entities", [])).size() == 3, "three dynamic entities composed")
	_check(Array(initial_details.get("representations", [])).size() == 3, "one representation per subject composed")
	_check(bool(initial_details.get("presentation_only", false)), "composed view is presentation only")
	_check(not bool(initial_details.get("canonical_state_generated", true)), "composition creates no canonical state")
	_check(_has_entity(initial_details, "player/a"), "A entity visible")
	_check(_has_entity(initial_details, "ship/01"), "B local entity visible")
	_check(_has_entity(initial_details, "player/c"), "C entity visible")
	_check(_entity_role(initial_details, "ship/01") == "LOCAL", "active authority projection marked local")
	_check(_entity_role(initial_details, "player/a") == "FOREIGN", "A projection marked foreign")
	_check(_entity_role(initial_details, "player/c") == "FOREIGN", "C projection marked foreign")
	_check(_all_entities_read_only_presentation(initial_details), "all client entities fail closed as presentation")
	_check(_has_rep(initial_details, "rep/a/terrain/coarse", false), "A coarse used while fine unavailable")
	_check(_has_rep(initial_details, "rep/b/construction/fine", false), "near B fine representation used")
	_check(_has_rep(initial_details, "rep/c/terrain/coarse", false), "far C coarse representation used")
	_check(composer.cache_size() == 3, "three artifacts cached after first composition")

	var cached := composer.compose_view(_v(0,0,0), 100.0, 5000)
	_check_success(cached, "cached composition")
	var cached_details: Dictionary = Dictionary(cached.get("details", {}))
	_check(int(cached_details.get("cache_hits", 0)) == 3, "all representation artifacts reused from cache")
	_check(int(cached_details.get("bandwidth_used_bytes", -1)) == 3 * Composer.ENTITY_COST_BYTES, "cached artifacts consume zero representation bandwidth")

	var a2 := _snapshot_a(1, 2, true, "FOREIGN")
	_check_success(composer.accept_projection(a2), "A progressive fine update accepted")
	var progressive := composer.compose_view(_v(0,0,0), 100.0, 5000)
	_check_success(progressive, "progressive composition")
	var progressive_details: Dictionary = Dictionary(progressive.get("details", {}))
	_check(_has_rep(progressive_details, "rep/a/terrain/fine", false), "A fine replaces coarse when ready")
	_check(composer.cache_size() == 4, "fine artifact added without losing coarse cache")

	var tiny = Composer.new()
	_check_success(tiny.setup(B, 5000), "tiny composer setup")
	_check_success(tiny.accept_projection(a1), "tiny accepts A")
	_check_success(tiny.accept_projection(b1), "tiny accepts B")
	_check_success(tiny.accept_projection(c1), "tiny accepts C")
	var tiered := tiny.compose_view(_v(0,0,0), 100.0, 2 * Composer.ENTITY_COST_BYTES)
	_check_success(tiered, "priority budget composition")
	var tiered_details: Dictionary = Dictionary(tiered.get("details", {}))
	_check(Array(tiered_details.get("entities", [])).size() == 2, "budget admits only two entity tiers")
	_check(_has_entity(tiered_details, "ship/01"), "highest priority local ship retained")
	_check(_has_entity(tiered_details, "player/a"), "second priority A entity retained")
	_check(not _has_entity(tiered_details, "player/c"), "lower priority C entity dropped by budget")
	_check(int(tiered_details.get("budget_drops", 0)) >= 1, "budget pressure reported")

	var fallback = Composer.new()
	_check_success(fallback.setup(B, 5000), "fallback composer setup")
	_check_success(fallback.accept_projection(b1), "fallback accepts B")
	var fallback_view := fallback.compose_view(_v(0,0,0), 100.0, Composer.ENTITY_COST_BYTES + 300)
	_check_success(fallback_view, "fallback composition")
	var fallback_details: Dictionary = Dictionary(fallback_view.get("details", {}))
	_check(_has_rep(fallback_details, "rep/b/construction/coarse", false), "fine representation falls back to coarse under bandwidth budget")
	_check(not _has_rep(fallback_details, "rep/b/construction/fine", false), "oversized fine representation not admitted")

	_check_error(composer.mark_source_unavailable(A, 9), "SM0_P10_SOURCE_DROPOUT_EPOCH_MISMATCH", "wrong dropout epoch rejected")
	_check_success(composer.mark_source_unavailable(A, 1), "A dropout accepted")
	_check(not composer.source_available(A), "A marked unavailable")
	var degraded := composer.compose_view(_v(0,0,0), 100.0, 5000)
	_check_success(degraded, "degraded composition")
	var degraded_details: Dictionary = Dictionary(degraded.get("details", {}))
	_check(Array(degraded_details.get("degraded_sources", [])).has(A), "only A source reported degraded")
	_check(not Array(degraded_details.get("degraded_sources", [])).has(B), "B remains healthy")
	_check(not Array(degraded_details.get("degraded_sources", [])).has(C), "C remains healthy")
	_check(not _has_entity(degraded_details, "player/a"), "dropped source dynamic entity removed")
	_check(_has_entity(degraded_details, "ship/01"), "local B entity survives A dropout")
	_check(_has_entity(degraded_details, "player/c"), "C foreign entity survives A dropout")
	_check(_has_rep(degraded_details, "rep/a/terrain/coarse", true), "cached coarse A representation degrades read-only")
	_check(_all_representations_noncanonical(degraded_details), "degraded cache cannot become canonical state")

	var recovered := composer.accept_projection(a2)
	_check_success(recovered, "exact replay can recover source availability")
	_check(bool(Dictionary(recovered.get("details", {})).get("replay", false)), "recovery uses exact replay")
	_check(composer.source_available(A), "A source available after exact replay recovery")
	var recovered_view := composer.compose_view(_v(0,0,0), 100.0, 5000)
	_check_success(recovered_view, "recovered composition")
	_check(_has_entity(Dictionary(recovered_view.get("details", {})), "player/a"), "A dynamic entity restored after source recovery")

	_check_error(composer.reject_presentation_mutation("player/a", "move"), "SM0_P10_PRESENTATION_READ_ONLY", "composed entity mutation forbidden")
	_check_error(composer.reject_presentation_mutation("region/a", "materialize-canonical"), "SM0_P10_PRESENTATION_READ_ONLY", "representation cannot materialize canonical state")

	var fence = Composer.new()
	_check_success(fence.setup(B, 5000), "fence composer setup")
	_check_success(fence.accept_projection(_snapshot_a(2, 1, false, "FOREIGN")), "higher source epoch accepted")
	_check_error(fence.accept_projection(_snapshot_a(1, 99, true, "FOREIGN")), "SM0_P10_SOURCE_EPOCH_ROLLBACK", "source epoch rollback rejected")
	_check_success(fence.accept_projection(_snapshot_a(2, 2, true, "FOREIGN")), "same epoch higher sequence accepted")
	_check_error(fence.accept_projection(_snapshot_a(2, 1, false, "FOREIGN")), "SM0_P10_SOURCE_SEQUENCE_STALE", "stale sequence rejected")

	_finish()

func _snapshot_a(epoch: int, sequence: int, fine_ready: bool, role: String) -> Dictionary:
	return Contract.create_snapshot(A, epoch, role, sequence, 100 + sequence, [
		Contract.entity("player/a", "PLAYER", _v(-12.0 + float(sequence - 1),0,0), 92, sequence),
	], [
		Contract.representation("rep/a/terrain/coarse", "region/a", "COARSE", _v(-20,0,5), 70, 220, "artifact-a-coarse-0001", true),
		Contract.representation("rep/a/terrain/fine", "region/a", "FINE", _v(-20,0,5), 70, 900, "artifact-a-fine-0001", fine_ready),
	])

func _snapshot_b(epoch: int, sequence: int, role: String) -> Dictionary:
	return Contract.create_snapshot(B, epoch, role, sequence, 200 + sequence, [
		Contract.entity("ship/01", "VEHICLE", _v(0,0,0), 100, sequence),
	], [
		Contract.representation("rep/b/construction/coarse", "structure/b", "COARSE", _v(8,0,0), 95, 260, "artifact-b-coarse-0001", true),
		Contract.representation("rep/b/construction/fine", "structure/b", "FINE", _v(8,0,0), 95, 1100, "artifact-b-fine-0001", true),
	])

func _snapshot_c(epoch: int, sequence: int, role: String) -> Dictionary:
	return Contract.create_snapshot(C, epoch, role, sequence, 300 + sequence, [
		Contract.entity("player/c", "PLAYER", _v(18,0,0), 84, sequence),
	], [
		Contract.representation("rep/c/terrain/coarse", "region/c", "COARSE", _v(35,0,0), 60, 180, "artifact-c-coarse-0001", true),
		Contract.representation("rep/c/terrain/fine", "region/c", "FINE", _v(35,0,0), 60, 780, "artifact-c-fine-0001", true),
	])

func _v(x: float, y: float, z: float) -> Dictionary:
	return {"x":x,"y":y,"z":z}

func _has_entity(details: Dictionary, entity_id: String) -> bool:
	for raw in Array(details.get("entities", [])):
		if String(Dictionary(raw).get("entity_id", "")) == entity_id:
			return true
	return false

func _entity_role(details: Dictionary, entity_id: String) -> String:
	for raw in Array(details.get("entities", [])):
		var value: Dictionary = Dictionary(raw)
		if String(value.get("entity_id", "")) == entity_id:
			return String(value.get("source_role", ""))
	return ""

func _has_rep(details: Dictionary, representation_id: String, stale_cached: bool) -> bool:
	for raw in Array(details.get("representations", [])):
		var value: Dictionary = Dictionary(raw)
		if String(value.get("representation_id", "")) == representation_id and bool(value.get("stale_cached", false)) == stale_cached:
			return true
	return false

func _all_entities_read_only_presentation(details: Dictionary) -> bool:
	for raw in Array(details.get("entities", [])):
		var value: Dictionary = Dictionary(raw)
		if value.get("read_only") != true or value.get("presentation_only") != true or value.get("canonical_write_allowed") != false:
			return false
	return true

func _all_representations_noncanonical(details: Dictionary) -> bool:
	for raw in Array(details.get("representations", [])):
		var value: Dictionary = Dictionary(raw)
		if value.get("presentation_only") != true or value.get("canonical_write_allowed") != false:
			return false
	return true

func _check_success(result: Dictionary, label: String) -> void:
	_check(bool(result.get("success", false)), label + " success")

func _check_error(result: Dictionary, error_code: String, label: String) -> void:
	_check(not bool(result.get("success", false)), label + " fails")
	_check(String(result.get("error_code", "")) == error_code, label + " error code")

func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failed = true
		push_error("P10 assertion failed: %s" % label)

func _finish() -> void:
	if EXPECTED_ASSERTIONS > 0 and _assertions != EXPECTED_ASSERTIONS:
		_failed = true
		push_error("P10 assertion count mismatch: expected %d got %d" % [EXPECTED_ASSERTIONS, _assertions])
	if _failed:
		print("SM0 P10 multi-authority view + LOD: FAIL (%d assertions)" % _assertions)
		quit(1)
	else:
		print("SM0 P10 multi-authority view + LOD: PASS (%d assertions)" % _assertions)
		quit(0)