extends "res://tests/research/fabric_bake0/adaptive_fidelity_test_support_v1.gd"

const Controller = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_controller_v1.gd")
const Recovery = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_recovery_v1.gd")

func recover(src: Dictionary, rows: Array, capsule: Dictionary = {}, tick: int = 3) -> Dictionary:
	var result := Recovery.recover(src, rows, "CHEAPEST_SAFE", Controller.DEFAULT_CONFIG, tick, capsule)
	check(result.get("success", false), "recover succeeds: " + str(result.get("error_code")))
	return result.get("details", {})

func pending_state() -> Dictionary:
	var state := unpack(Controller.create(source()), "state")
	for tick in [1, 2]:
		var env := envelope(state["current_fidelity"], candidates())
		state = unpack(Controller.evaluate(state, env, decision(env), tick), "state")
	return state

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		disk_process(args)
		return
	var src := source()
	var original := src.duplicate(true)
	var cold := recover(src, candidates())
	check(cold["state"]["current_fidelity"] == "FULL_FABRIC", "cold safe FULL until stability proven")
	check(cold["capsule_status"] == "COLD_REBUILT", "cold rebuild qualification")
	check(cold == recover(src, candidates()), "cold recovery deterministic")
	var pending := pending_state()
	var capsule := unpack(Recovery.capture(pending), "capsule")
	var warm := recover(src, candidates(), capsule)
	check(warm["capsule_status"] == "WARM_VALIDATED", "warm validated")
	check(warm["state"]["current_fidelity"] == "STRUCTURAL_BAKE", "pending proof resumes")
	check(warm["state"]["transition_count"] == 1, "single recovered transition")
	check(warm == recover(src, candidates(), capsule), "double recovery input identical result")
	# Crash after pure preparation, before atomic slot publication: use the old
	# committed capsule. Recovery produces the same logical receipt, not two.
	var env := envelope("FULL_FABRIC", candidates())
	var prepared := Controller.evaluate(pending, env, decision(env), 3)
	check(prepared["details"]["transition"] == warm["transition"], "crash during transition idempotent receipt")
	var replay := Controller.evaluate(warm["state"], warm["envelope"], warm["decision"], 3)
	check(replay.get("success", false) and not replay["details"]["applied"], "recovered receipt cannot apply twice")
	for changed in [source(0, 2), source(0, 1, "new-dependency"), source(0, 1, "stable", 2)]:
		var rejected := recover(changed, candidates(), capsule)
		check(rejected["capsule_status"] == "CAPSULE_DISCARDED_REBUILT", "revision/dependency/authority change rejects cache")
		check(rejected["state"]["source_revision"] == changed, "no lost or forged source revision")
		check(rejected["state"]["current_fidelity"] == "FULL_FABRIC", "stale physical representation not restored")
	var dormant := unpack(Controller.create(src, "DORMANT"), "state")
	var dormant_capsule := unpack(Recovery.capture(dormant), "capsule")
	var causal := candidates()
	causal[4]["causal_dependencies"] = ["dependency/live-load"]
	var woken := recover(src, causal, dormant_capsule)
	check(woken["state"]["current_fidelity"] == "FULL_FABRIC", "causal dependency prevents dormant restoration")
	check(woken["discard_reason"] == "SAVED_FIDELITY_NO_LONGER_SAFE", "wake discard reason")
	var rom := unpack(Controller.create(src, "DYNAMIC_ROM"), "state")
	var unsafe := recover(src, candidates(1), unpack(Recovery.capture(rom), "capsule"))
	check(unsafe["state"]["current_fidelity"] == "FULL_FABRIC", "required promotion cannot restore unsafe ROM")
	for field in capsule:
		var corrupt := capsule.duplicate(true)
		corrupt[field] = "corrupt"
		var rebuilt := recover(src, candidates(), corrupt)
		check(rebuilt["capsule_status"] == "CAPSULE_DISCARDED_REBUILT", "corrupt cache discarded " + field)
	var partial := capsule.duplicate(true)
	partial["phase"] = "PREPARED"
	partial["checksum"] = Utils.compute_checksum(partial)
	check(recover(src, candidates(), partial)["capsule_status"] == "CAPSULE_DISCARDED_REBUILT", "uncommitted capsule rejected")
	for text in ["{", "[]", "null", "123"]:
		var rebuilt := Recovery.recover_json(src, candidates(), "CHEAPEST_SAFE", Controller.DEFAULT_CONFIG, 3, text)
		check(rebuilt.get("success", false) and rebuilt["details"]["capsule_status"] == "CAPSULE_DISCARDED_REBUILT", "malformed serialized capsule discarded")
	var encoded := Utils.NetworkUtils.canonical_json(capsule)
	var roundtrip := Recovery.recover_json(src, candidates(), "CHEAPEST_SAFE", Controller.DEFAULT_CONFIG, 3, encoded)
	check(roundtrip.get("success", false) and roundtrip["details"] == warm, "JSON numeric normalization preserves recovery")
	check(src == original, "canonical source not mutated by persistence")
	var no_safe := candidates()
	no_safe[0]["available"] = false
	check(not Recovery.recover(src, no_safe, "CHEAPEST_SAFE", Controller.DEFAULT_CONFIG, 3, capsule).get("success", false), "no safe FULL fails closed")
	print("B06D_RECOVERY_HASH=" + Utils.canonical_hash({"cold": cold["recovery_hash"], "warm": warm["recovery_hash"], "wake": woken["recovery_hash"]}))
	finish("FABRIC B0.6-D Persistence Restart")

func disk_process(args: PackedStringArray) -> void:
	check(args.size() == 2, "disk process arguments")
	if args.size() != 2:
		finish("FABRIC B0.6-D Disk Process")
		return
	if args[0] == "--write-capsule":
		var capsule := unpack(Recovery.capture(pending_state()), "capsule")
		var file := FileAccess.open(args[1], FileAccess.WRITE)
		check(file != null, "capsule file opened")
		if file != null:
			file.store_string(Utils.NetworkUtils.canonical_json(capsule))
			file.flush()
			file.close()
	elif args[0] == "--read-capsule":
		var file := FileAccess.open(args[1], FileAccess.READ)
		check(file != null, "fresh process capsule read")
		if file != null:
			var encoded := file.get_as_text()
			file.close()
			var restored := Recovery.recover_json(source(), candidates(), "CHEAPEST_SAFE", Controller.DEFAULT_CONFIG, 3, encoded)
			check(restored.get("success", false), "fresh process recover")
			if restored.get("success", false):
				check(restored["details"]["state"]["current_fidelity"] == "STRUCTURAL_BAKE", "cross-process hysteresis continuity")
				check(restored["details"]["state"]["transition_count"] == 1, "cross-process exactly once transition")
				print("B06D_DISK_RECOVERY_HASH=" + restored["details"]["recovery_hash"])
	else:
		check(false, "unknown disk process mode")
	finish("FABRIC B0.6-D Disk Process")
