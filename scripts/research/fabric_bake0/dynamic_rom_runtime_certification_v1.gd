extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const FullModel = preload("res://scripts/research/fabric_bake0/dynamic_full_model_descriptor_v1.gd")
const ROM = preload("res://scripts/research/fabric_bake0/dynamic_rom_descriptor_v1.gd")
const ValidatedDomain = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")
const ErrorEnvelope = preload("res://scripts/research/fabric_bake0/error_envelope_v1.gd")
const ConservationEnvelope = preload("res://scripts/research/fabric_bake0/conservation_envelope_v1.gd")
const RuntimeErrorEstimator = preload("res://scripts/research/fabric_bake0/runtime_error_estimator_v1.gd")
const RefinementGuard = preload("res://scripts/research/fabric_bake0/refinement_guard_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_dynamic_rom_runtime_certification.v1"
const MODE := "DYNAMIC_ROM_R1"
const FLOW_L1_QUANTITY := "quantity/dynamic-rom/flow-l1"
const ERROR_QUANTITY := "quantity/dynamic-rom/effort-error-bound"
const ELAPSED_QUANTITY := "quantity/dynamic-rom/elapsed"
const FLOW_GUARD_ID := "guard/dynamic-rom/flow-domain"
const ERROR_GUARD_ID := "guard/dynamic-rom/error-bound"
const HORIZON_GUARD_ID := "guard/dynamic-rom/horizon"
const MAX_FLOW_L1 := 1.0
const FLOW_GUARD_TRIGGER := 0.95
const MAX_HORIZON_S := 4.0
const HORIZON_GUARD_TRIGGER_S := 3.8
const MAX_STEP_S := 0.02
const EFFORT_ERROR_ABS_MAX := 0.01
const ERROR_GUARD_TRIGGER := 0.008
const ERROR_GUARD_UNCERTAINTY := 0.0005

const FIELDS: Array[String] = [
	"schema", "rom_descriptor_hash", "full_model_hash", "source_binding_checksum",
	"alpha_dissipation_lower_bound", "max_step_s", "max_flow_l1",
	"initial_error_c_norm_max", "validated_domain", "error_envelope",
	"conservation_envelope", "refinement_guards", "certification_hash", "checksum",
]

static func create(full_model: Dictionary, rom: Dictionary) -> Dictionary:
	var checked := FullModel.validate(full_model)
	if not bool(checked.get("success", false)):
		return {}
	checked = ROM.validate(rom)
	if not bool(checked.get("success", false)):
		return {}
	if String(rom["full_model_hash"]) != String(full_model["model_hash"]):
		return {}
	if String(rom["source_binding_checksum"]) != String(full_model["source_binding"]["checksum"]):
		return {}
	if String(rom["boundary_contract_hash"]) != String(full_model["boundary_contract"]["contract_hash"]):
		return {}

	var flow_dimension: Array = full_model["boundary_contract"]["ports"][0]["flow_dimension"].duplicate(true)
	for port in full_model["boundary_contract"]["ports"]:
		if port["flow_dimension"] != flow_dimension:
			return {}

	var minimum_shunt := INF
	var maximum_storage := 0.0
	for shunt in full_model["shunts"]:
		minimum_shunt = minf(minimum_shunt, float(shunt["conductance"]))
	for node in full_model["storage_nodes"]:
		maximum_storage = maxf(maximum_storage, float(node["storage_coefficient"]))
	if minimum_shunt <= 0.0 or maximum_storage <= 0.0:
		return {}
	var alpha := minimum_shunt / maximum_storage

	var domain := ValidatedDomain.create(
		String(full_model["source_binding"]["frontier_hash"]),
		String(full_model["source_binding"]["fabric_graph_hash"]),
		[{
			"quantity_id": FLOW_L1_QUANTITY,
			"dimension": flow_dimension,
			"minimum": 0.0,
			"maximum": MAX_FLOW_L1,
		}],
		[MODE],
		MAX_HORIZON_S
	)
	var envelope := ErrorEnvelope.create(
		EFFORT_ERROR_ABS_MAX, 1.0e-3,
		0.0, 0.0,
		EFFORT_ERROR_ABS_MAX * MAX_FLOW_L1, 1.0e-3,
		0.0, 0.0,
		0.02, 0.0, 0.0,
		MAX_HORIZON_S,
		true
	)
	var conservation := ConservationEnvelope.create(
		2.0e-9, 2.0e-9, 0.0, 0.0, 0.0
	)
	var guards: Array = [
		RefinementGuard.create(
			ERROR_GUARD_ID,
			[ERROR_QUANTITY],
			EFFORT_ERROR_ABS_MAX,
			ERROR_GUARD_TRIGGER,
			"region/dynamic/all",
			1,
			ERROR_GUARD_UNCERTAINTY
		),
		RefinementGuard.create(
			FLOW_GUARD_ID,
			[FLOW_L1_QUANTITY],
			MAX_FLOW_L1,
			FLOW_GUARD_TRIGGER,
			"region/dynamic/all",
			1,
			0.0
		),
		RefinementGuard.create(
			HORIZON_GUARD_ID,
			[ELAPSED_QUANTITY],
			MAX_HORIZON_S,
			HORIZON_GUARD_TRIGGER_S,
			"region/dynamic/all",
			1,
			0.0
		),
	]
	guards = Utils.sorted_dicts(guards, "guard_id")
	for guard in guards:
		if guard.is_empty():
			return {}
	var value: Dictionary = {
		"schema": SCHEMA,
		"rom_descriptor_hash": String(rom["descriptor_hash"]),
		"full_model_hash": String(full_model["model_hash"]),
		"source_binding_checksum": String(full_model["source_binding"]["checksum"]),
		"alpha_dissipation_lower_bound": alpha,
		"max_step_s": MAX_STEP_S,
		"max_flow_l1": MAX_FLOW_L1,
		"initial_error_c_norm_max": 0.0,
		"validated_domain": domain,
		"error_envelope": envelope,
		"conservation_envelope": conservation,
		"refinement_guards": guards,
		"certification_hash": "",
		"checksum": "",
	}
	value["certification_hash"] = Utils.canonical_hash(_identity_payload(value))
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_DYNAMIC_ROM_RUNTIME_CERTIFICATION")
	for field in ["rom_descriptor_hash", "full_model_hash", "source_binding_checksum", "certification_hash"]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_DYNAMIC_ROM_CERTIFICATION_HASH", {"field": field})
	for field in ["alpha_dissipation_lower_bound", "max_step_s", "max_flow_l1"]:
		if not Utils.is_positive_number(value.get(field)):
			return Utils.failure("INVALID_DYNAMIC_ROM_CERTIFICATION_POSITIVE_BOUND", {"field": field})
	if not Utils.is_non_negative_number(value.get("initial_error_c_norm_max")):
		return Utils.failure("INVALID_DYNAMIC_ROM_INITIAL_ERROR_BOUND")
	if typeof(value.get("validated_domain")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_ROM_CERTIFIED_DOMAIN")
	checked = ValidatedDomain.validate(value["validated_domain"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("error_envelope")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_ROM_CERTIFIED_ERROR_ENVELOPE")
	checked = ErrorEnvelope.validate(value["error_envelope"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("conservation_envelope")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_ROM_CERTIFIED_CONSERVATION_ENVELOPE")
	checked = ConservationEnvelope.validate(value["conservation_envelope"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("refinement_guards")) != TYPE_ARRAY or value["refinement_guards"].size() != 3:
		return Utils.failure("DYNAMIC_ROM_REQUIRES_THREE_RUNTIME_GUARDS")
	var previous := ""
	for guard in value["refinement_guards"]:
		checked = RefinementGuard.validate(guard)
		if not bool(checked.get("success", false)):
			return checked
		var current := String(guard["guard_id"])
		if not previous.is_empty() and current <= previous:
			return Utils.failure("DYNAMIC_ROM_GUARDS_NOT_SORTED_UNIQUE")
		previous = current
	if String(value["certification_hash"]) != Utils.canonical_hash(_identity_payload(value)):
		return Utils.failure("DYNAMIC_ROM_CERTIFICATION_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func estimate_after_step(
	certification: Dictionary,
	full_model: Dictionary,
	rom: Dictionary,
	previous_error_c_norm: float,
	old_rom_values: Array,
	new_rom_values: Array,
	port_flows: Dictionary,
	delta_s: float,
	elapsed_s: float
) -> Dictionary:
	var checked := validate(certification)
	if not bool(checked.get("success", false)):
		return checked
	checked = FullModel.validate(full_model)
	if not bool(checked.get("success", false)):
		return checked
	checked = ROM.validate(rom)
	if not bool(checked.get("success", false)):
		return checked
	if String(certification["rom_descriptor_hash"]) != String(rom["descriptor_hash"]):
		return Utils.failure("DYNAMIC_ROM_CERTIFICATION_DESCRIPTOR_MISMATCH")
	if String(certification["full_model_hash"]) != String(full_model["model_hash"]):
		return Utils.failure("DYNAMIC_ROM_CERTIFICATION_FULL_MODEL_MISMATCH")
	if not Utils.is_non_negative_number(previous_error_c_norm):
		return Utils.failure("INVALID_DYNAMIC_ROM_PREVIOUS_ERROR_NORM")
	if not Utils.is_positive_number(delta_s) or delta_s > float(certification["max_step_s"]) + 1.0e-15:
		return Utils.failure("DYNAMIC_ROM_CERTIFIED_STEP_OUTSIDE_DOMAIN")
	if not Utils.is_non_negative_number(elapsed_s):
		return Utils.failure("INVALID_DYNAMIC_ROM_CERTIFIED_ELAPSED")
	var r := int(rom["reduced_state_count"])
	if old_rom_values.size() != r or new_rom_values.size() != r:
		return Utils.failure("DYNAMIC_ROM_CERTIFIED_STATE_LENGTH_MISMATCH")
	var flow_l1 := 0.0
	for port_id in rom["port_ids"]:
		if not port_flows.has(String(port_id)) or not Utils.is_finite_number(port_flows[String(port_id)]):
			return Utils.failure("DYNAMIC_ROM_CERTIFIED_FLOW_COVERAGE_MISMATCH")
		flow_l1 += absf(float(port_flows[String(port_id)]))

	var old_full := _reconstruct(rom, old_rom_values)
	var new_full := _reconstruct(rom, new_rom_values)
	var residual := _full_residual(full_model, old_full, new_full, port_flows, delta_s)
	var residual_dual_c_norm := 0.0
	for index in range(residual.size()):
		var storage := float(full_model["storage_nodes"][index]["storage_coefficient"])
		residual_dual_c_norm += float(residual[index]) * float(residual[index]) / storage
	residual_dual_c_norm = sqrt(maxf(0.0, residual_dual_c_norm))
	var alpha := float(certification["alpha_dissipation_lower_bound"])
	var error_c_norm := (
		float(previous_error_c_norm) + delta_s * residual_dual_c_norm
	) / (1.0 + alpha * delta_s)

	var state_index := FullModel.state_index(full_model)
	var minimum_port_storage := INF
	for binding in full_model["port_bindings"]:
		var state_i := int(state_index[String(binding["state_id"])])
		minimum_port_storage = minf(
			minimum_port_storage,
			float(full_model["storage_nodes"][state_i]["storage_coefficient"])
		)
	var effort_error_bound := error_c_norm / sqrt(minimum_port_storage)
	var power_error_bound := effort_error_bound * flow_l1

	var rom_storage_norm_squared := 0.0
	var mass_product := _matvec(rom["reduced_mass_matrix"], new_rom_values)
	for index in range(new_rom_values.size()):
		rom_storage_norm_squared += float(new_rom_values[index]) * float(mass_product[index])
	var rom_storage_norm := sqrt(maxf(0.0, rom_storage_norm_squared))
	var energy_error_bound := rom_storage_norm * error_c_norm + 0.5 * error_c_norm * error_c_norm

	var flow_margin := maxf(0.0, 1.0 - flow_l1 / float(certification["max_flow_l1"]))
	var horizon_margin := maxf(0.0, 1.0 - elapsed_s / MAX_HORIZON_S)
	var error_margin := maxf(0.0, (ERROR_GUARD_TRIGGER - effort_error_bound - ERROR_GUARD_UNCERTAINTY) / ERROR_GUARD_TRIGGER)
	var estimator := RuntimeErrorEstimator.create(
		"estimator/dynamic-rom/residual",
		effort_error_bound,
		0.0,
		power_error_bound,
		0.0,
		energy_error_bound,
		0.0,
		minf(flow_margin, horizon_margin),
		minf(flow_margin, minf(horizon_margin, error_margin)),
		minf(MAX_HORIZON_S, elapsed_s + delta_s)
	)
	if estimator.is_empty():
		return Utils.failure("DYNAMIC_ROM_RUNTIME_ESTIMATOR_CREATE_FAILED")
	return Utils.success({
		"estimator": estimator,
		"error_c_norm_bound": error_c_norm,
		"residual_dual_c_norm": residual_dual_c_norm,
		"flow_l1": flow_l1,
		"elapsed_s": elapsed_s,
		"runtime_domain": {
			"source_frontier_hash": String(full_model["source_binding"]["frontier_hash"]),
			"fabric_graph_hash": String(full_model["source_binding"]["fabric_graph_hash"]),
			"elapsed_s": elapsed_s,
			"mode": MODE,
			"quantities": {FLOW_L1_QUANTITY: flow_l1},
		},
		"guard_values": {
			ERROR_GUARD_ID: effort_error_bound,
			FLOW_GUARD_ID: flow_l1,
			HORIZON_GUARD_ID: elapsed_s,
		},
	})

static func evaluate_runtime(certification: Dictionary, estimate_details: Dictionary) -> Dictionary:
	var checked := validate(certification)
	if not bool(checked.get("success", false)):
		return checked
	if typeof(estimate_details.get("runtime_domain")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_ROM_RUNTIME_DOMAIN")
	checked = ValidatedDomain.contains(certification["validated_domain"], estimate_details["runtime_domain"])
	if not bool(checked.get("success", false)):
		return Utils.failure("DYNAMIC_ROM_VALIDITY_EXIT", {
			"cause": checked.get("error_code", "VALIDITY_EXIT"),
			"fallback": "FULL_OR_NO_SAFE_BAKE",
		})
	checked = RuntimeErrorEstimator.validate_against(
		estimate_details["estimator"],
		certification["error_envelope"]
	)
	if not bool(checked.get("success", false)):
		return Utils.failure("DYNAMIC_ROM_ERROR_ENVELOPE_EXIT", {
			"cause": checked.get("error_code", "ERROR_ENVELOPE_EXIT"),
			"fallback": "FULL_OR_NO_SAFE_BAKE",
		})
	for guard in certification["refinement_guards"]:
		checked = RefinementGuard.evaluate(guard, estimate_details["guard_values"])
		if not bool(checked.get("success", false)):
			return Utils.failure("DYNAMIC_ROM_REFINEMENT_REQUIRED", {
				"cause": checked.get("error_code", "REFINEMENT_REQUIRED"),
				"guard_id": guard["guard_id"],
				"fallback": "REFINE_OR_FULL",
			})
	return Utils.success({
		"status": "DYNAMIC_ROM_CERTIFIED_RUNTIME_SAFE",
		"minimum_safe_fidelity": "APPROXIMATE",
		"remaining_validity_margin": estimate_details["estimator"]["remaining_validity_margin"],
		"guard_margin": estimate_details["estimator"]["guard_margin"],
	})

static func _reconstruct(rom: Dictionary, reduced_values: Array) -> Array:
	var full: Array = []
	full.resize(int(rom["full_state_count"]))
	full.fill(0.0)
	for full_index in range(full.size()):
		var value := 0.0
		for reduced_index in range(reduced_values.size()):
			value += float(rom["basis_matrix"][full_index][reduced_index]) * float(reduced_values[reduced_index])
		full[full_index] = value
	return full

static func _full_residual(
	full_model: Dictionary,
	old_values: Array,
	new_values: Array,
	port_flows: Dictionary,
	delta_s: float
) -> Array:
	var n := old_values.size()
	var residual: Array = []
	residual.resize(n)
	for index in range(n):
		var storage := float(full_model["storage_nodes"][index]["storage_coefficient"])
		residual[index] = storage * (float(new_values[index]) - float(old_values[index])) / delta_s
	var state_index := FullModel.state_index(full_model)
	for shunt in full_model["shunts"]:
		var i := int(state_index[String(shunt["state_id"])])
		residual[i] = float(residual[i]) + float(shunt["conductance"]) * float(new_values[i])
	for edge in full_model["edges"]:
		var a := int(state_index[String(edge["state_a_id"])])
		var b := int(state_index[String(edge["state_b_id"])])
		var contribution := float(edge["conductance"]) * (float(new_values[a]) - float(new_values[b]))
		residual[a] = float(residual[a]) + contribution
		residual[b] = float(residual[b]) - contribution
	for index in range(full_model["port_bindings"].size()):
		var binding: Dictionary = full_model["port_bindings"][index]
		var port: Dictionary = full_model["boundary_contract"]["ports"][index]
		var state_i := int(state_index[String(binding["state_id"])])
		var sign := 1.0 if String(port["orientation"]) == "INTO_SUBSYSTEM" else -1.0
		residual[state_i] = float(residual[state_i]) - sign * float(port_flows[String(port["port_id"])])
	return residual

static func _matvec(matrix: Array, vector: Array) -> Array:
	var output: Array = []
	output.resize(matrix.size())
	for row in range(matrix.size()):
		var value := 0.0
		for column in range(vector.size()):
			value += float(matrix[row][column]) * float(vector[column])
		output[row] = value
	return output

static func _identity_payload(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("certification_hash")
	payload.erase("checksum")
	return payload
