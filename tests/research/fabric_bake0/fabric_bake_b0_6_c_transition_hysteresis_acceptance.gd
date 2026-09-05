extends "res://tests/research/fabric_bake0/adaptive_fidelity_test_support_v1.gd"

const Controller = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_controller_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Ownership = preload("res://scripts/research/fabric_bake0/mixed_representation_ownership_contract_v1.gd")

func advance(state: Dictionary, rows: Array, tick: int, policy: String = "CHEAPEST_SAFE") -> Dictionary:
	var env := envelope(state["current_fidelity"], rows)
	var selected := decision(env, policy)
	var result := Controller.evaluate(state, env, selected, tick)
	check(result.get("success", false), "controller evaluation: " + str(result.get("error_code")))
	return result.get("details", {})

func _initialize() -> void:
	var src := source()
	var state := unpack(Controller.create(src), "state")
	var before := state.duplicate(true)
	for tick in range(1, 4):
		state = advance(state, candidates(), tick)["state"]
		check(state["current_fidelity"] == ("FULL_FABRIC" if tick < 3 else "STRUCTURAL_BAKE"), "stable demotion window")
	check(before["transition_count"] == 0 and before["safe_streak"] == 0, "input state not mutated")
	check(state["transition_count"] == 1, "one demotion only")
	state = unpack(Controller.create(src), "state")
	state = advance(state, candidates(), 1)["state"]
	state = advance(state, candidates(), 2)["state"]
	state = advance(state, candidates(0), 3)["state"]
	check(state["safe_streak"] == 0 and state["current_fidelity"] == "FULL_FABRIC", "one tick spike resets proof")
	state = advance(state, candidates(), 4)["state"]
	check(state["safe_streak"] == 1, "streak starts again")
	state = unpack(Controller.create(src, "DYNAMIC_ROM"), "state")
	state["cooldown_remaining"] = 2
	state = Controller.seal(state)
	var env := envelope("DYNAMIC_ROM", candidates(1))
	var selected := decision(env)
	var result := Controller.evaluate(state, env, selected, 1)
	state = unpack(result, "state")
	check(state["current_fidelity"] == "STRUCTURAL_BAKE", "unsafe promotion ignores cooldown/window")
	check(result["details"]["transition"]["reason"] == "UNSAFE_PROMOTION", "safety promotion reason")
	var repeat := Controller.evaluate(state, env, selected, 1)
	check(repeat.get("success", false) and not repeat["details"]["applied"], "exactly once repeat")
	check(repeat["details"]["transition"].is_empty() and repeat["details"]["state"] == state, "no duplicate transition or epoch")
	check(not Controller.evaluate(state, env, selected, 0).get("success", false), "old tick rejected")
	var different := candidates(1)
	different[0]["estimated_cost"] = 0.1
	var other := envelope("DYNAMIC_ROM", different)
	check(not Controller.evaluate(state, other, decision(other), 1).get("success", false), "same tick conflicting input rejected")
	state = unpack(Controller.create(src, "DYNAMIC_ROM"), "state")
	for tick in range(1, 81):
		state = advance(state, candidates(3 if tick % 2 == 1 else 2), tick)["state"]
	check(state["transition_count"] == 0 and state["current_fidelity"] == "DYNAMIC_ROM", "80 noisy ticks cannot thrash")
	for tick in range(81, 84):
		state = advance(state, candidates(3), tick)["state"]
	check(state["current_fidelity"] == "HYBRID_BAKE", "sustained safe still demotes")
	state = unpack(Controller.create(src), "state")
	var guarded := candidates()
	guarded[1]["pending_refinement_guards"] = ["guard/refine"]
	for tick in range(1, 8):
		state = advance(state, guarded, tick)["state"]
	check(state["current_fidelity"] == "FULL_FABRIC" and state["safe_streak"] == 0, "guard blocks demotion")
	state = unpack(Controller.create(src, "DORMANT"), "state")
	var causal := candidates()
	causal[4]["causal_dependencies"] = ["dependency/live-load"]
	state = advance(state, causal, 1)["state"]
	check(state["current_fidelity"] == "HYBRID_BAKE", "immediate causal wake")
	state = unpack(Controller.create(src), "state")
	state = advance(state, candidates(), 1)["state"]
	state = advance(state, candidates(), 3)["state"]
	check(state["safe_streak"] == 1, "missing authoritative tick resets consecutive proof")
	for field in ["safe_streak", "transition_epoch", "cooldown_remaining", "last_evaluation_tick", "transition_count"]:
		var bad := state.duplicate(true)
		bad[field] = -1
		bad = Controller.seal(bad)
		check(not Controller.validate_state(bad).get("success", false), "bad counter " + field)
	check(not Controller.create(src, "FULL_FABRIC", {"safe_window": 0, "cooldown_ticks": 0}).get("success", false), "zero window rejected")
	var first := timeline(src)
	var second := timeline(src)
	check(first == second, "same timeline same transitions epochs state")
	print("B06C_TRANSITION_HASH=" + first["transition_hash"])
	finish("FABRIC B0.6-C Transition Hysteresis")

func timeline(src: Dictionary) -> Dictionary:
	var state := unpack(Controller.create(src), "state")
	var authority := Authority.create("owner/research", [{"source_domain": src["source_domain"],
		"source_id": src["source_id"], "authority_epoch": src["authority_epoch"], "owner_id": "owner/research"}],
		[Utils.source_key(src["source_domain"], src["source_id"])])
	for tick in range(1, 22):
		var previous: String = state["current_fidelity"]
		state = advance(state, candidates(), tick)["state"]
		check(Envelope.LEVELS.find(state["current_fidelity"]) - Envelope.LEVELS.find(previous) <= 1, "one-level conservative demotion")
		var owner := Controller.bind_ownership(state, authority)
		check(owner.get("success", false), "actual BRIDGE-2 ownership contract validates")
		check(owner["details"]["contract"]["region_bindings"].size() == 1, "single physical owner")
		check(not owner["details"]["contract"]["representations"][0]["canonical_write_authorized"], "no forged source mutation")
		check(owner["details"]["execution_enabled"] == (state["current_fidelity"] != "DORMANT"), "dormant owner parked not forgotten")
	check(state["current_fidelity"] == "DORMANT" and state["transition_count"] == 4, "whole ladder four confirmed demotions")
	check(state["source_revision"] == src, "canonical source preserved")
	return state
