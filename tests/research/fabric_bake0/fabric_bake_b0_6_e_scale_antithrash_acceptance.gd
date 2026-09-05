extends "res://tests/research/fabric_bake0/adaptive_fidelity_test_support_v1.gd"

const Runtime = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_runtime_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Recovery = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_recovery_v1.gd")

func key_for(index: int) -> String:
	return Utils.source_key("CONSTRUCTION", "source/object-%05d" % index)

func authority_for(src: Dictionary) -> Dictionary:
	return Authority.create("owner/research", [{"source_domain": src["source_domain"], "source_id": src["source_id"],
		"authority_epoch": src["authority_epoch"], "owner_id": "owner/research"}],
		[Utils.source_key(src["source_domain"], src["source_id"])])

func spec_for(index: int) -> Dictionary:
	return {"state_id": "state/b0-6-%05d" % index, "storage": 2.0, "damping": 0.25,
		"initial_value": 2.0, "backend_contract_hash": Utils.canonical_hash({"backend": "BRIDGE2_GENERIC_SCALAR", "storage": 2.0, "damping": 0.25})}

func evaluate(runtime, index: int, rows: Array, tick: int, policy: String = "CHEAPEST_SAFE", revision: int = 1) -> Dictionary:
	var result: Dictionary = runtime.evaluate(key_for(index), source(index, revision), rows, policy, tick)
	check(result.get("success", false), "scale evaluation " + str(result.get("error_code", "")))
	return result

func _initialize() -> void:
	physical_smoke()
	if OS.get_cmdline_user_args().has("--smoke-only"):
		finish("FABRIC B0.6-E Local Lifecycle Smoke")
		return
	if not failures.is_empty():
		finish("FABRIC B0.6-E Scale Anti-thrash")
		return
	var campaigns: Array = []
	for count in [500, 1000, 2000]:
		var result := campaign(count)
		if not failures.is_empty():
			finish("FABRIC B0.6-E Scale Anti-thrash")
			return
		campaigns.append(result)
		print("B06E_SCALE_%d=%s" % [count, Utils.NetworkUtils.canonical_json(result)])
	for index in [1, 2]:
		for counter in Runtime.COUNTERS:
			check(campaigns[index]["work_counters"][counter] == 2 * campaigns[index - 1]["work_counters"][counter], "linear measured work " + counter)
	print("B06E_FINAL_STATE_HASH=" + Utils.canonical_hash(campaigns.map(func(x): return x["state_hash"])))
	print("B06E_TRANSITION_HASH=" + Utils.canonical_hash(campaigns.map(func(x): return x["transition_hash"])))
	print("B06E_WORK_HASH=" + Utils.canonical_hash(campaigns.map(func(x): return x["work_counters"])))
	finish("FABRIC B0.6-E Scale Anti-thrash")

func campaign(count: int) -> Dictionary:
	var runtime := Runtime.new()
	var group: int = count / 100
	for index in range(count):
		var src := source(index)
		var result := runtime.register(src, authority_for(src), spec_for(index), candidates(), Envelope.LEVELS[index % 5])
		check(result.get("success", false), "registered actual BRIDGE-2 physical representation")
		if not result.get("success", false):
			return {"work_counters": runtime.counters(), "state_hash": "", "transition_hash": ""}
	for index in range(count):
		evaluate(runtime, index, candidates(), 1, "HOLD_IF_SAFE")
	var regular := runtime.counters()
	check(regular["subjects_evaluated"] == 2 * count, "ordinary full pass linear subjects")
	check(regular["envelopes_compiled"] == 2 * count and regular["selector_decisions"] == 2 * count, "ordinary full pass linear A/B work")
	check(regular["reconstructions"] == count and regular["actual_transitions"] == 0, "stable sweep does not rebuild representations")
	var untouched := runtime.state(key_for(count - 1))
	var before := runtime.counters()
	for item in range(group):
		var index := 5 * (group + item) + 2
		evaluate(runtime, index, candidates(1), 2)
		check(runtime.state(key_for(index))["current_fidelity"] == "STRUCTURAL_BAKE", "immediate safety promotion under scale")
	check(runtime.counters()["promotions"] - before["promotions"] == group, "danger localized promotions")
	check(runtime.counters()["local_rebuilds"] - before["local_rebuilds"] == group, "danger bounded reconstruction")
	before = runtime.counters()
	for item in range(group):
		var index := 5 * item + 4
		var causal := candidates()
		causal[4]["causal_dependencies"] = ["dependency/live-load"]
		evaluate(runtime, index, causal, 2)
		check(runtime.can_execute(key_for(index)), "causal wake enables physical execution")
	check(runtime.counters()["promotions"] - before["promotions"] == group, "only causal subset woke")
	for item in range(group):
		var index := 5 * (group + item) + 1
		evaluate(runtime, index, candidates(), 2, "CHEAPEST_SAFE", 2)
		check(runtime.state(key_for(index))["current_fidelity"] == "FULL_FABRIC", "canonical structural invalidation forces fresh FULL")
		check(runtime.state(key_for(index))["source_revision"] == source(index, 2), "source revision remains canonical")
	before = runtime.counters()
	for tick in range(2, 5):
		for item in range(group):
			evaluate(runtime, 5 * item, candidates(), tick)
	check(runtime.counters()["demotions"] - before["demotions"] == group, "local delayed demotion occurs")
	check(runtime.counters()["local_rebuilds"] - before["local_rebuilds"] == group, "demotion bounded reconstruction")
	before = runtime.counters()
	for tick in range(2, 82):
		for item in range(group):
			var rows := candidates(3)
			rows[3]["validity_margin"] = 0.001 if tick % 2 == 0 else -0.001
			evaluate(runtime, 5 * item + 2, rows, tick)
	check(runtime.counters()["actual_transitions"] == before["actual_transitions"], "80 threshold-noise ticks produce zero transitions")
	check(runtime.counters()["reconstructions"] == before["reconstructions"], "threshold noise causes no physical rebake")
	for tick in range(82, 85):
		for item in range(group):
			evaluate(runtime, 5 * item + 2, candidates(3), tick)
	check(runtime.counters()["demotions"] - before["demotions"] == group, "sustained safe after noise demotes")
	check(runtime.state(key_for(count - 1)) == untouched, "unrelated object unchanged through all stimuli")
	for index in range(count):
		var contract := runtime.ownership(key_for(index))
		check(contract["region_bindings"].size() == 1 and contract["representations"].size() == 1, "one authoritative physical owner per source")
		check(not contract["representations"][0]["canonical_write_authorized"], "derived physics cannot write canonical world")
	var result := runtime.snapshot()
	check(result["work_counters"]["duplicate_ownership_count"] == 0, "no duplicate ownership")
	check(result["work_counters"]["unsafe_selection_count"] == 0, "no unsafe selected")
	check(result["work_counters"]["global_rebuilds"] == 0, "no global rebuild path")
	check(result["work_counters"]["failed_closed"] == 0, "valid scale stimuli all succeed")
	check(result["work_counters"]["subjects_evaluated"] == 2 * count + 89 * group, "exact linear work formula")
	check(result["work_counters"]["actual_transitions"] == 5 * group, "bounded actual transitions")
	result["ordinary_sweep_counters"] = regular
	return result

func physical_smoke() -> void:
	var runtime := Runtime.new()
	var index := 9999
	var src := source(index)
	var key := key_for(index)
	check(runtime.register(src, authority_for(src), spec_for(index), candidates()).get("success", false), "physical smoke register")
	check(not runtime.register(src, authority_for(src), spec_for(index), candidates()).get("success", false), "duplicate subject rejected")
	var descriptor := runtime.execution_descriptor(key)
	check(descriptor.get("success", false), "existing BRIDGE-2 adapter execution gate")
	check(descriptor["details"]["adapter"]["representation_kind"] == "FULL", "correct initial physical backend descriptor")
	descriptor["details"]["state_values"][spec_for(index)["state_id"]] = 999.0
	check(runtime.physical_state(key)[spec_for(index)["state_id"]] == 2.0, "descriptor cannot mutate the physical execution slot")
	var physical := runtime.physical_state(key)
	for tick in range(1, 19):
		evaluate(runtime, index, candidates(), tick)
		check(runtime.physical_state(key) == physical, "all representation handoffs preserve physical state")
	check(not runtime.can_execute(key), "dormant execution parked")
	check(not runtime.execution_descriptor(key).get("success", false), "dormant cannot dispatch despite retained owner")
	var causal := candidates()
	causal[4]["causal_dependencies"] = ["dependency/live-load"]
	evaluate(runtime, index, causal, 19)
	check(runtime.can_execute(key), "causal wake actual executor")
	var before := runtime.counters()
	var repeat := evaluate(runtime, index, causal, 19)
	check(not repeat["details"]["applied"] and runtime.counters() == before, "duplicate input zero physical work")
	var bad := candidates()
	bad[0]["available"] = false
	check(not runtime.evaluate(key, src, bad, "CHEAPEST_SAFE", 20).get("success", false), "unsafe FULL fails closed")
	check(not runtime.can_execute(key), "failed safety input disables old physical executor")
	evaluate(runtime, index, candidates(), 20)
	check(runtime.can_execute(key), "valid new envelope safely restores execution")
	var capsule := unpack(Recovery.capture(runtime.state(key)), "capsule")
	check(runtime.restore(key, src, candidates(), "CHEAPEST_SAFE", 21, capsule).get("success", false), "runtime recovery publishes one owner")
	before = runtime.counters()
	var restored := runtime.restore(key, src, candidates(), "CHEAPEST_SAFE", 21, capsule)
	check(restored.get("success", false) and not restored["details"]["applied"], "repeat recovery idempotent")
	check(runtime.counters() == before, "repeat recovery no duplicate physical reconstruction")

	# A late old capsule cannot roll a newer live execution slot backwards.
	var current := runtime.state(key)
	check(not runtime.restore(key, src, candidates(), "SAFEST", 20, capsule).get("success", false), "recovery cannot rewind an active authoritative tick")
	check(runtime.state(key) == current, "rejected recovery leaves committed state unchanged")
	var new_source := source(index, 2, "stable", 2)
	var new_spec := spec_for(index)
	new_spec["initial_value"] = 3.0
	check(runtime.restore(key, new_source, candidates(), "CHEAPEST_SAFE", 22, capsule, authority_for(new_source), new_spec).get("success", false), "new canonical authority/source rebuilds safely")
	check(runtime.state(key)["source_revision"] == new_source, "canonical source supplied by owner retained")
	check(runtime.physical_state(key)[new_spec["state_id"]] == 3.0, "reconstruction uses new canonical physical input")
