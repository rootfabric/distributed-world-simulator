extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const FullModel = preload("res://scripts/research/fabric_bake0/dynamic_full_model_descriptor_v1.gd")

const VERSION := "FABRIC-BAKE/B0.4-B/FULL-VALIDATION-REFERENCE-R1"

static func prepare(model: Dictionary, delta_s: float) -> Dictionary:
	var checked := FullModel.validate(model)
	if not bool(checked.get("success", false)):
		return _failure(String(checked.get("error_code", "B0_4_B_INVALID_FULL_MODEL")))
	if not Utils.is_positive_number(delta_s):
		return _failure("B0_4_B_INVALID_FULL_VALIDATION_STEP")
	if delta_s > float(model["reference_solver"]["max_step_s"]) + 1.0e-15:
		return _failure("B0_4_B_FULL_VALIDATION_STEP_EXCEEDS_MAX")
	var n := int(model["full_state_schema"]["state_count"])
	var storage: Array = []
	storage.resize(n)
	for index in range(n):
		storage[index] = float(model["storage_nodes"][index]["storage_coefficient"])
	var state_index: Dictionary = FullModel.state_index(model)
	var shunts: Array = []
	shunts.resize(n)
	shunts.fill(0.0)
	for shunt in model["shunts"]:
		shunts[int(state_index[String(shunt["state_id"])])] = float(shunt["conductance"])
	var edge_g: Array = []
	edge_g.resize(n - 1)
	edge_g.fill(0.0)
	for edge in model["edges"]:
		var a := int(state_index[String(edge["state_a_id"])])
		var b := int(state_index[String(edge["state_b_id"])])
		if b != a + 1:
			return _failure("B0_4_B_FULL_VALIDATION_REQUIRES_PATH")
		edge_g[a] = float(edge["conductance"])

	var lower: Array = []
	var diag: Array = []
	var upper: Array = []
	lower.resize(n)
	diag.resize(n)
	upper.resize(n)
	lower.fill(0.0)
	diag.fill(0.0)
	upper.fill(0.0)
	for index in range(n):
		var left_g := float(edge_g[index - 1]) if index > 0 else 0.0
		var right_g := float(edge_g[index]) if index + 1 < n else 0.0
		lower[index] = -left_g
		upper[index] = -right_g
		diag[index] = float(storage[index]) / delta_s + float(shunts[index]) + left_g + right_g
	var factor := _factor_tridiagonal(lower, diag, upper)
	if not bool(factor.get("success", false)):
		return factor

	var port_indices: Array = []
	var port_signs: Array = []
	var port_ids: Array = []
	for index in range(model["port_bindings"].size()):
		var binding: Dictionary = model["port_bindings"][index]
		var port: Dictionary = model["boundary_contract"]["ports"][index]
		port_indices.append(int(state_index[String(binding["state_id"])]))
		port_signs.append(1.0 if String(port["orientation"]) == "INTO_SUBSYSTEM" else -1.0)
		port_ids.append(String(port["port_id"]))
	return {
		"success": true,
		"version": VERSION,
		"model_hash": String(model["model_hash"]),
		"delta_s": delta_s,
		"storage": storage,
		"port_indices": port_indices,
		"port_signs": port_signs,
		"port_ids": port_ids,
		"factor": factor,
	}

static func zero_state(prepared: Dictionary) -> Array:
	var values: Array = []
	values.resize(prepared["storage"].size())
	values.fill(0.0)
	return values

static func step(prepared: Dictionary, values: Array, port_flows: Dictionary) -> Dictionary:
	if values.size() != prepared["storage"].size():
		return _failure("B0_4_B_FULL_VALIDATION_STATE_LENGTH_MISMATCH")
	var rhs: Array = []
	rhs.resize(values.size())
	for index in range(values.size()):
		rhs[index] = float(prepared["storage"][index]) / float(prepared["delta_s"]) * float(values[index])
	for port_index in range(prepared["port_ids"].size()):
		var port_id := String(prepared["port_ids"][port_index])
		if not port_flows.has(port_id) or not Utils.is_finite_number(port_flows[port_id]):
			return _failure("B0_4_B_FULL_VALIDATION_FLOW_MISSING", {"port_id": port_id})
		var state_index := int(prepared["port_indices"][port_index])
		rhs[state_index] = float(rhs[state_index]) + float(prepared["port_signs"][port_index]) * float(port_flows[port_id])
	var solved := _solve_factored(prepared["factor"], rhs)
	if not bool(solved.get("success", false)):
		return solved
	var next_values: Array = solved["values"]
	var boundary: Array = []
	for port_index in range(prepared["port_ids"].size()):
		var state_index := int(prepared["port_indices"][port_index])
		boundary.append({
			"port_id": String(prepared["port_ids"][port_index]),
			"effort": float(next_values[state_index]),
		})
	return {
		"success": true,
		"values": next_values,
		"boundary": boundary,
	}

static func _factor_tridiagonal(lower: Array, diag: Array, upper: Array) -> Dictionary:
	var n := diag.size()
	if n < 1:
		return _failure("B0_4_B_FULL_VALIDATION_EMPTY_OPERATOR")
	var c_prime: Array = []
	var inverse_pivots: Array = []
	c_prime.resize(n)
	inverse_pivots.resize(n)
	var pivot := float(diag[0])
	if absf(pivot) <= 1.0e-15:
		return _failure("B0_4_B_FULL_VALIDATION_SINGULAR", {"index": 0})
	inverse_pivots[0] = 1.0 / pivot
	c_prime[0] = float(upper[0]) * float(inverse_pivots[0])
	for index in range(1, n):
		pivot = float(diag[index]) - float(lower[index]) * float(c_prime[index - 1])
		if absf(pivot) <= 1.0e-15:
			return _failure("B0_4_B_FULL_VALIDATION_SINGULAR", {"index": index})
		inverse_pivots[index] = 1.0 / pivot
		c_prime[index] = float(upper[index]) * float(inverse_pivots[index]) if index + 1 < n else 0.0
	return {
		"success": true,
		"lower": lower.duplicate(),
		"c_prime": c_prime,
		"inverse_pivots": inverse_pivots,
	}

static func _solve_factored(factor: Dictionary, rhs: Array) -> Dictionary:
	var n := rhs.size()
	var d_prime: Array = []
	d_prime.resize(n)
	d_prime[0] = float(rhs[0]) * float(factor["inverse_pivots"][0])
	for index in range(1, n):
		d_prime[index] = (
			float(rhs[index]) - float(factor["lower"][index]) * float(d_prime[index - 1])
		) * float(factor["inverse_pivots"][index])
	var values: Array = []
	values.resize(n)
	values[n - 1] = float(d_prime[n - 1])
	for index in range(n - 2, -1, -1):
		values[index] = float(d_prime[index]) - float(factor["c_prime"][index]) * float(values[index + 1])
	return {"success": true, "values": values}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": code,
		"details": details.duplicate(true),
	}
