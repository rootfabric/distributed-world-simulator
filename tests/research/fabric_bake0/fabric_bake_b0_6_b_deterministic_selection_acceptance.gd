extends "res://tests/research/fabric_bake0/adaptive_fidelity_test_support_v1.gd"

func _initialize() -> void:
	var rows := candidates()
	var env := envelope("DYNAMIC_ROM", rows)
	var first := decision(env)
	check(first["target_fidelity"] == "DORMANT", "normal cost agrees with minimum safe")
	check(first == decision(env), "identical decision")
	check(first == decision(reverse_keys(env)), "dictionary key order irrelevant")
	check(Selector.validate_decision(first, env).get("success", false), "decision validates")
	check(decision(env, "SAFEST")["target_fidelity"] == "FULL_FABRIC", "SAFEST")
	check(decision(env, "HOLD_IF_SAFE")["target_fidelity"] == "DYNAMIC_ROM", "HOLD current safe")
	var altered := rows.duplicate(true)
	altered[1]["estimated_cost"] = 0.0001
	var changed := envelope("DYNAMIC_ROM", altered)
	check(decision(changed)["target_fidelity"] == "STRUCTURAL_BAKE", "safe scheduling cost changes target")
	check(changed["safety_hash"] == env["safety_hash"], "cost cannot change safety")
	for row in altered:
		row["estimated_cost"] = 1.0
	check(decision(envelope("DYNAMIC_ROM", altered))["target_fidelity"] == "FULL_FABRIC", "fixed safest tie break")
	altered = rows.duplicate(true)
	altered[2]["error_bound"] = 1.0
	altered[2]["estimated_cost"] = 0.000001
	altered[1]["estimated_cost"] = 1000000.0
	changed = envelope("DYNAMIC_ROM", altered)
	check(decision(changed)["target_fidelity"] == "FULL_FABRIC", "unsafe cheap ROM excluded")
	check(decision(changed, "HOLD_IF_SAFE")["target_fidelity"] == "STRUCTURAL_BAKE", "nearest safer HOLD")
	for policy in Selector.POLICIES:
		var chosen := decision(changed, policy)
		check(changed["admissible_fidelities"].has(chosen["target_fidelity"]), "safe set never expanded")
	check(not Selector.select(env, "DYNAMIC_ROM", "UNKNOWN").get("success", false), "unknown policy rejected")
	check(not Selector.select(env, "FULL_FABRIC", "SAFEST").get("success", false), "current mismatch rejected")
	var corrupt := env.duplicate(true)
	corrupt["checksum"] = "0".repeat(64)
	check(not Selector.select(corrupt, "DYNAMIC_ROM", "SAFEST").get("success", false), "tampered envelope")
	corrupt = env.duplicate(true)
	corrupt["admissible_fidelities"] = []
	check(not Selector.select(corrupt, "DYNAMIC_ROM", "SAFEST").get("success", false), "empty admissible set")
	for field in first:
		var bad := first.duplicate(true)
		bad[field] = 17
		check(not Selector.validate_decision(bad, env).get("success", false), "bad decision type " + field)
	var bad := first.duplicate(true)
	bad["target_fidelity"] = "FULL_FABRIC"
	check(not Selector.validate_decision(bad, env).get("success", false), "forged decision rejected")
	print("B06B_SELECTION_HASH=" + first["decision_hash"])
	finish("FABRIC B0.6-B Deterministic Selection")
