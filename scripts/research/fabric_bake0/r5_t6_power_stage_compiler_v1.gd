extends RefCounted
## T6 compiler: four parallel semiconductor banks -> bidirectional H-bridge power stage.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/power_stage_graph_v1.gd")
const Physics = preload("res://scripts/research/fabric_bake0/power_stage_physics_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/power_stage_interface_contract_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/power_stage_descriptor_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/power_stage_execution_artifact_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")

const VERSION := "FABRIC_R5_2_T6_POWER_STAGE_COMPILER_R1"
const SYNCHRONY_REL_TOL := 1.0e-10

static func compile(graph: Dictionary, request: Dictionary, capsule_id: String) -> Dictionary:
	var checked := Graph.validate(graph)
	if not checked.success:
		return checked
	if typeof(request.get("canonical_source_frontier")) != TYPE_DICTIONARY:
		return U.failure("POWER_STAGE_CANONICAL_FRONTIER_REQUIRED")
	var graph_bound := false
	var matter_bound := false
	for source in request.canonical_source_frontier.get("sources", []):
		if String(source.get("source_domain", "")) == "CONSTRUCTION" and String(source.get("source_hash", "")) == String(graph.graph_hash):
			graph_bound = true
		if String(source.get("source_domain", "")) == "MATTER" and String(source.get("source_hash", "")) == String(graph.material_catalog.catalog_hash):
			matter_bound = true
	if not graph_bound:
		return U.failure("POWER_STAGE_CANONICAL_GRAPH_SOURCE_MISMATCH")
	if not matter_bound:
		return U.failure("POWER_STAGE_CANONICAL_MATERIAL_SOURCE_MISMATCH")

	var banks: Array = [[], [], [], []]
	var all_rows: Array = []
	var active_count := 0
	var total_mass := 0.0
	var stage_profile_id := ""
	for die in graph.switch_dies:
		var derived := Physics.derive_die(graph, die)
		if not derived.success:
			return derived
		var row: Dictionary = derived.details.die
		all_rows.append(row)
		banks[int(row.bank_index)].append(row)
		total_mass += float(row.mass_kg)
		if bool(row.enabled):
			active_count += 1
			if stage_profile_id.is_empty():
				stage_profile_id = String(row.profile_id)
			elif String(row.profile_id) != stage_profile_id:
				return U.failure("POWER_STAGE_PROFILE_MISMATCH", {"die_id": row.die_id})
	if stage_profile_id.is_empty():
		return U.failure("POWER_STAGE_NO_ACTIVE_DIES")

	var bank_resistance: Array = []
	var bank_max_current: Array = []
	var bank_transition: Array = []
	var alpha := -1.0
	var reference_t := -1.0
	var min_t := 0.0
	var max_t := INF
	var max_bus_voltage := INF
	for bank_index in range(4):
		var active_rows: Array = []
		for row in banks[bank_index]:
			if bool(row.enabled):
				active_rows.append(row)
		if active_rows.is_empty():
			return U.failure("POWER_STAGE_BANK_OPEN", {"bank_index": bank_index})
		var conductance_sum := 0.0
		var current_sum := 0.0
		var weighted_transition := 0.0
		var synchrony_reference := float(active_rows[0].current_limit_per_conductance)
		for row in active_rows:
			if String(row.profile_id) != stage_profile_id:
				return U.failure("POWER_STAGE_PROFILE_MISMATCH", {"bank_index": bank_index, "die_id": row.die_id})
			var synchrony := float(row.current_limit_per_conductance)
			var scale := maxf(1.0e-18, maxf(absf(synchrony), absf(synchrony_reference)))
			if absf(synchrony - synchrony_reference) > SYNCHRONY_REL_TOL * scale:
				return U.failure("POWER_STAGE_PARALLEL_CURRENT_SYNCHRONY_UNSAFE", {"bank_index": bank_index, "die_id": row.die_id})
			conductance_sum += float(row.conductance_ref_s)
			current_sum += float(row.max_abs_current_a)
			weighted_transition += float(row.conductance_ref_s) * float(row.transition_time_s)
			if alpha < 0.0:
				alpha = float(row.resistance_temp_coefficient_per_k)
				reference_t = float(row.reference_temperature_k)
			elif absf(alpha - float(row.resistance_temp_coefficient_per_k)) > 1.0e-15 or absf(reference_t - float(row.reference_temperature_k)) > 1.0e-12:
				return U.failure("POWER_STAGE_TEMPERATURE_LAW_MISMATCH")
			min_t = maxf(min_t, float(row.min_temperature_k))
			max_t = minf(max_t, float(row.max_temperature_k))
			max_bus_voltage = minf(max_bus_voltage, float(row.max_bus_voltage_v))
		if conductance_sum <= 0.0 or current_sum <= 0.0:
			return U.failure("POWER_STAGE_BANK_AGGREGATE_INVALID", {"bank_index": bank_index})
		bank_resistance.append(1.0 / conductance_sum)
		bank_max_current.append(current_sum)
		bank_transition.append(weighted_transition / conductance_sum)

	if min_t >= max_t or max_bus_voltage <= 0.0:
		return U.failure("POWER_STAGE_DOMAIN_EMPTY")
	var positive_path_r := float(bank_resistance[0]) + float(bank_resistance[3])
	var negative_path_r := float(bank_resistance[1]) + float(bank_resistance[2])
	var positive_current := minf(float(bank_max_current[0]), float(bank_max_current[3]))
	var negative_current := minf(float(bank_max_current[1]), float(bank_max_current[2]))
	var positive_transition := float(bank_transition[0]) + float(bank_transition[3])
	var negative_transition := float(bank_transition[1]) + float(bank_transition[2])

	var interface := Interface.create()
	if interface.is_empty():
		return U.failure("POWER_STAGE_INTERFACE_CREATE_FAILED")
	var source_count := graph.switch_dies.size()
	var source_operations := source_count * 6
	var compiled_operations := 18
	var descriptor := Descriptor.create({
		"graph_hash": graph.graph_hash,
		"material_catalog_hash": graph.material_catalog.catalog_hash,
		"interface_contract": interface,
		"switch_die_count": source_count,
		"active_die_count": active_count,
		"bank_count": 4,
		"profile_id": stage_profile_id,
		"bank_resistance_ref_ohm": bank_resistance,
		"bank_max_abs_current_a": bank_max_current,
		"bank_effective_transition_time_s": bank_transition,
		"positive_path_resistance_ref_ohm": positive_path_r,
		"negative_path_resistance_ref_ohm": negative_path_r,
		"positive_path_max_abs_current_a": positive_current,
		"negative_path_max_abs_current_a": negative_current,
		"positive_path_transition_time_s": positive_transition,
		"negative_path_transition_time_s": negative_transition,
		"resistance_temp_coefficient_per_k": alpha,
		"reference_temperature_k": reference_t,
		"min_temperature_k": min_t,
		"max_temperature_k": max_t,
		"max_bus_voltage_v": max_bus_voltage,
		"total_semiconductor_mass_kg": total_mass,
		"source_operation_count": source_operations,
		"compiled_operation_count": compiled_operations,
	})
	if descriptor.is_empty():
		return U.failure("POWER_STAGE_DESCRIPTOR_CREATE_FAILED")
	var artifact := Artifact.create(
		String(request.get("artifact_id", "")),
		request.canonical_source_frontier,
		request.authority_envelope,
		request.dependency_set,
		String(graph.graph_hash),
		String(graph.material_catalog.catalog_hash),
		interface,
		descriptor,
		int(request.get("build_generation", 1))
	)
	if artifact.is_empty():
		return U.failure("POWER_STAGE_ARTIFACT_CREATE_FAILED")
	var provenance := U.canonical_hash({
		"compiler_version": VERSION,
		"graph_hash": graph.graph_hash,
		"material_catalog_hash": graph.material_catalog.catalog_hash,
		"descriptor_hash": descriptor.descriptor_hash,
		"artifact_hash": artifact.artifact_hash,
		"reduction": "PARALLEL_SWITCH_BANKS",
	})
	var capsule := Capsule.create(
		capsule_id,
		"POWER_STAGE",
		"PARALLEL_SWITCH_BANKS",
		String(artifact.canonical_source_frontier.frontier_hash),
		String(graph.graph_hash),
		String(interface.interface_hash),
		"POWER_STAGE",
		String(artifact.checksum),
		String(descriptor.checksum),
		String(artifact.state_schema_hash),
		source_count,
		source_operations,
		compiled_operations,
		0,
		int(artifact.build_generation),
		["BIDIRECTIONAL", "ELECTRICAL", "POWER_CONVERSION", "STATELESS"],
		provenance
	)
	if capsule.is_empty():
		return U.failure("POWER_STAGE_CAPSULE_CREATE_FAILED")
	return U.success({
		"descriptor": descriptor,
		"artifact": artifact,
		"capsule": capsule,
		"compile_stats": {
			"source_dies": source_count,
			"active_dies": active_count,
			"banks": 4,
			"source_operations": source_operations,
			"compiled_operations": compiled_operations,
		},
	})
