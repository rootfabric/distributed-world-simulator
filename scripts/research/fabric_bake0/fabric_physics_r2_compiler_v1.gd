extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const MatterBatch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")
const MaterialLaw = preload("res://scripts/research/fabric_bake0/fabric_physics_r2_material_law_v1.gd")

const MECHANICAL_MODEL_SCHEMA := "planet_simulator.fabric_physics_r2_mechanical_axial_model.v1"
const ELECTRICAL_MODEL_SCHEMA := "planet_simulator.fabric_physics_r2_electrical_resistive_model.v1"
const MECHANICAL_BOND_KIND := "AXIAL_SPRING"
const ELECTRICAL_BOND_KIND := "ELECTRICAL_RESISTOR"
const AREA_FIELD := "area_m2"
const DAMPING_FIELD := "damping_ns_per_m"
const ANCHOR_FIELD := "physics_r2_anchor"
const MIN_LENGTH_M := 1.0e-9
const FRACTION_TOL := 1.0e-9
const MASS_ABS_TOL := 1.0e-9
const MASS_REL_TOL := 1.0e-12
const TEMPERATURE_REL_TOL := 1.0e-12

static func compile_mechanical(snapshot: Dictionary, matter_batch: Dictionary) -> Dictionary:
	var source := _validate_sources(snapshot, matter_batch, MaterialLaw.DOMAIN_MECHANICAL_AXIAL)
	if not source.success:
		return source
	var law: Dictionary = source.details.law
	var parts_by_id: Dictionary = source.details.parts_by_id
	var nodes := _mechanical_nodes(snapshot)
	if nodes.is_empty():
		return Utils.failure("PHYSICS_R2_MECHANICAL_NODE_SET_EMPTY")

	var elements: Array = []
	for raw_bond in snapshot["bonds"]:
		var bond: Dictionary = raw_bond
		if String(bond["bond_kind"]) != MECHANICAL_BOND_KIND:
			return Utils.failure("PHYSICS_R2_MECHANICAL_BOND_KIND_UNSUPPORTED", {
				"bond_id": bond["bond_id"],
				"bond_kind": bond["bond_kind"],
			})
		if String(bond["state"]) == "DEGRADED":
			return Utils.failure("PHYSICS_R2_DEGRADED_BOND_UNSUPPORTED", {"bond_id": bond["bond_id"]})
		var geometry := _bond_geometry(bond, parts_by_id)
		if not geometry.success:
			return geometry
		var metadata: Dictionary = bond["metadata"]
		if not metadata.has(DAMPING_FIELD) or not Utils.is_non_negative_number(metadata.get(DAMPING_FIELD)):
			return Utils.failure("PHYSICS_R2_DAMPING_REQUIRED", {"bond_id": bond["bond_id"]})
		var length_m: float = geometry.details.length_m
		var area_m2: float = geometry.details.area_m2
		var youngs_modulus_pa: float = law.parameters.youngs_modulus_pa
		var stiffness_n_per_m := youngs_modulus_pa * area_m2 / length_m
		if not Utils.is_positive_number(stiffness_n_per_m):
			return Utils.failure("PHYSICS_R2_STIFFNESS_INVALID", {"bond_id": bond["bond_id"]})
		elements.append({
			"element_id": String(bond["bond_id"]),
			"node_a": String(bond["part_a_id"]),
			"node_b": String(bond["part_b_id"]),
			"length_m": length_m,
			"area_m2": area_m2,
			"youngs_modulus_pa": youngs_modulus_pa,
			"stiffness_n_per_m": stiffness_n_per_m,
			"damping_ns_per_m": float(metadata[DAMPING_FIELD]),
			"capacity_n": float(bond["strength_n"]),
			"active": String(bond["state"]) != "BROKEN",
		})

	if elements.is_empty():
		return Utils.failure("PHYSICS_R2_MECHANICAL_ELEMENT_SET_EMPTY")
	var model := _model(
		MECHANICAL_MODEL_SCHEMA,
		MaterialLaw.DOMAIN_MECHANICAL_AXIAL,
		snapshot,
		matter_batch,
		law,
		nodes,
		elements
	)
	return Utils.success({"model": model})

static func compile_electrical(snapshot: Dictionary, matter_batch: Dictionary) -> Dictionary:
	var source := _validate_sources(snapshot, matter_batch, MaterialLaw.DOMAIN_ELECTRICAL_RESISTIVE)
	if not source.success:
		return source
	var law: Dictionary = source.details.law
	var parts_by_id: Dictionary = source.details.parts_by_id
	var nodes: Array = []
	for raw_part in snapshot["parts"]:
		var part: Dictionary = raw_part
		nodes.append({
			"node_id": String(part["part_id"]),
			"local_position_m": Array(part["local_position_m"]).duplicate(),
		})

	var elements: Array = []
	for raw_bond in snapshot["bonds"]:
		var bond: Dictionary = raw_bond
		if String(bond["bond_kind"]) != ELECTRICAL_BOND_KIND:
			return Utils.failure("PHYSICS_R2_ELECTRICAL_BOND_KIND_UNSUPPORTED", {
				"bond_id": bond["bond_id"],
				"bond_kind": bond["bond_kind"],
			})
		if String(bond["state"]) == "DEGRADED":
			return Utils.failure("PHYSICS_R2_DEGRADED_BOND_UNSUPPORTED", {"bond_id": bond["bond_id"]})
		var geometry := _bond_geometry(bond, parts_by_id)
		if not geometry.success:
			return geometry
		var length_m: float = geometry.details.length_m
		var area_m2: float = geometry.details.area_m2
		var resistivity_ohm_m: float = law.parameters.resistivity_ohm_m
		var resistance_ohm := resistivity_ohm_m * length_m / area_m2
		if not Utils.is_positive_number(resistance_ohm):
			return Utils.failure("PHYSICS_R2_RESISTANCE_INVALID", {"bond_id": bond["bond_id"]})
		var conductance_siemens := 1.0 / resistance_ohm
		elements.append({
			"element_id": String(bond["bond_id"]),
			"node_a": String(bond["part_a_id"]),
			"node_b": String(bond["part_b_id"]),
			"length_m": length_m,
			"area_m2": area_m2,
			"resistivity_ohm_m": resistivity_ohm_m,
			"resistance_ohm": resistance_ohm,
			"conductance_siemens": conductance_siemens,
			"active": String(bond["state"]) != "BROKEN",
		})

	if elements.is_empty():
		return Utils.failure("PHYSICS_R2_ELECTRICAL_ELEMENT_SET_EMPTY")
	var model := _model(
		ELECTRICAL_MODEL_SCHEMA,
		MaterialLaw.DOMAIN_ELECTRICAL_RESISTIVE,
		snapshot,
		matter_batch,
		law,
		nodes,
		elements
	)
	return Utils.success({"model": model})

static func mechanical_static_response(model: Dictionary, element_id: String, force_n: float) -> Dictionary:
	if model.get("schema") != MECHANICAL_MODEL_SCHEMA or model.get("domain") != MaterialLaw.DOMAIN_MECHANICAL_AXIAL:
		return Utils.failure("PHYSICS_R2_MECHANICAL_MODEL_REQUIRED")
	if not Utils.validate_checksum(model).success:
		return Utils.failure("PHYSICS_R2_MODEL_CHECKSUM_INVALID")
	if not Utils.is_finite_number(force_n):
		return Utils.failure("PHYSICS_R2_FORCE_INVALID")
	var element := element_by_id(model, element_id)
	if element.is_empty():
		return Utils.failure("PHYSICS_R2_ELEMENT_NOT_FOUND", {"element_id": element_id})
	if not bool(element["active"]):
		return Utils.failure("PHYSICS_R2_ELEMENT_INACTIVE", {"element_id": element_id})
	var stiffness: float = element["stiffness_n_per_m"]
	var displacement_m := force_n / stiffness
	var stored_energy_j := 0.5 * stiffness * displacement_m * displacement_m
	var quasistatic_work_j := 0.5 * force_n * displacement_m
	return Utils.success({
		"element_id": element_id,
		"force_n": force_n,
		"displacement_m": displacement_m,
		"stored_energy_j": stored_energy_j,
		"quasistatic_work_j": quasistatic_work_j,
	})

static func evaluate_guard(element: Dictionary, load_n: float, guard_fraction: float) -> Dictionary:
	if not Utils.is_finite_number(load_n):
		return Utils.failure("PHYSICS_R2_LOAD_INVALID")
	if not Utils.is_positive_number(guard_fraction) or guard_fraction >= 1.0:
		return Utils.failure("PHYSICS_R2_GUARD_FRACTION_INVALID")
	if not Utils.is_positive_number(element.get("capacity_n")):
		return Utils.failure("PHYSICS_R2_CAPACITY_INVALID")
	var capacity_n: float = element["capacity_n"]
	var magnitude := absf(load_n)
	var guard_n := guard_fraction * capacity_n
	var decision := "SAFE"
	var failure_proposal := false
	if magnitude > capacity_n:
		decision = "FAILURE_PROPOSAL"
		failure_proposal = true
	elif magnitude > guard_n:
		decision = "REFINE"
	return Utils.success({
		"decision": decision,
		"load_n": load_n,
		"guard_n": guard_n,
		"capacity_n": capacity_n,
		"failure_proposal": failure_proposal,
		"damage_committed": false,
	})

static func element_by_id(model: Dictionary, element_id: String) -> Dictionary:
	for raw in model.get("elements", []):
		if String(raw.get("element_id", "")) == element_id:
			return Dictionary(raw).duplicate(true)
	return {}

static func _validate_sources(snapshot: Dictionary, matter_batch: Dictionary, domain: String) -> Dictionary:
	var checked := Snapshot.validate(snapshot)
	if not bool(checked.get("success", false)):
		return Utils.failure("PHYSICS_R2_CONSTRUCTION_INVALID", {"cause": checked.get("error_code", "")})
	checked = MatterBatch.validate(matter_batch)
	if not bool(checked.get("success", false)):
		return Utils.failure("PHYSICS_R2_MATTER_INVALID", {"cause": checked.get("error_code", "")})
	if not ["OPERATIONAL", "DAMAGED"].has(String(snapshot["build_state"])):
		return Utils.failure("PHYSICS_R2_CONSTRUCTION_NOT_EXECUTABLE")
	if not _near(float(matter_batch["temperature_k"]), MaterialLaw.REFERENCE_TEMPERATURE_K, TEMPERATURE_REL_TOL):
		return Utils.failure("PHYSICS_R2_TEMPERATURE_OUT_OF_SCOPE", {
			"actual_k": matter_batch["temperature_k"],
			"required_k": MaterialLaw.REFERENCE_TEMPERATURE_K,
		})

	var mass_total := 0.0
	var parts_by_id: Dictionary = {}
	for raw_part in snapshot["parts"]:
		var part: Dictionary = raw_part
		var part_id := String(part["part_id"])
		parts_by_id[part_id] = part
		mass_total += float(part["mass_kg"])
	if not _near(mass_total, float(matter_batch["total_mass_kg"]), MASS_REL_TOL, MASS_ABS_TOL):
		return Utils.failure("PHYSICS_R2_CONSTRUCTION_MATTER_MASS_MISMATCH", {
			"construct_mass_kg": mass_total,
			"matter_mass_kg": matter_batch["total_mass_kg"],
		})

	var components: Array = matter_batch["composition"]["components"]
	if components.size() != 1 or not _near(float(components[0]["mass_fraction"]), 1.0, FRACTION_TOL):
		return Utils.failure("PHYSICS_R2_MIXED_MATERIAL_OUT_OF_SCOPE")
	var material_id := String(components[0]["material_id"])
	var resolved := MaterialLaw.resolve(material_id, domain)
	if not resolved.success:
		return resolved
	return Utils.success({
		"law": resolved.details.law,
		"parts_by_id": parts_by_id,
		"construct_mass_kg": mass_total,
	})

static func _mechanical_nodes(snapshot: Dictionary) -> Array:
	var nodes: Array = []
	for raw_part in snapshot["parts"]:
		var part: Dictionary = raw_part
		var metadata: Dictionary = part["metadata"]
		var anchored := false
		if metadata.has(ANCHOR_FIELD):
			if typeof(metadata[ANCHOR_FIELD]) != TYPE_BOOL:
				return []
			anchored = bool(metadata[ANCHOR_FIELD])
		nodes.append({
			"node_id": String(part["part_id"]),
			"mass_kg": float(part["mass_kg"]),
			"local_position_m": Array(part["local_position_m"]).duplicate(),
			"anchored": anchored,
		})
	return nodes

static func _bond_geometry(bond: Dictionary, parts_by_id: Dictionary) -> Dictionary:
	var part_a: Dictionary = parts_by_id.get(String(bond["part_a_id"]), {})
	var part_b: Dictionary = parts_by_id.get(String(bond["part_b_id"]), {})
	if part_a.is_empty() or part_b.is_empty():
		return Utils.failure("PHYSICS_R2_BOND_ENDPOINT_UNKNOWN", {"bond_id": bond["bond_id"]})
	var metadata: Dictionary = bond["metadata"]
	if not metadata.has(AREA_FIELD) or not Utils.is_positive_number(metadata.get(AREA_FIELD)):
		return Utils.failure("PHYSICS_R2_AREA_REQUIRED", {"bond_id": bond["bond_id"]})
	var position_a: Array = part_a["local_position_m"]
	var position_b: Array = part_b["local_position_m"]
	var dx := float(position_b[0]) - float(position_a[0])
	var dy := float(position_b[1]) - float(position_a[1])
	var dz := float(position_b[2]) - float(position_a[2])
	var length_m := sqrt(dx * dx + dy * dy + dz * dz)
	if not Utils.is_positive_number(length_m) or length_m <= MIN_LENGTH_M:
		return Utils.failure("PHYSICS_R2_LENGTH_INVALID", {"bond_id": bond["bond_id"], "length_m": length_m})
	return Utils.success({"length_m": length_m, "area_m2": float(metadata[AREA_FIELD])})

static func _model(
	schema: String,
	domain: String,
	snapshot: Dictionary,
	matter_batch: Dictionary,
	law: Dictionary,
	nodes: Array,
	elements: Array
) -> Dictionary:
	var model: Dictionary = {
		"schema": schema,
		"domain": domain,
		"construct_id": String(snapshot["construct_id"]),
		"construct_revision": int(snapshot["state_revision"]),
		"construct_checksum": String(snapshot["checksum"]),
		"matter_batch_id": String(matter_batch["batch_id"]),
		"matter_checksum": String(matter_batch["checksum"]),
		"material_law": law.duplicate(true),
		"nodes": nodes.duplicate(true),
		"elements": elements.duplicate(true),
		"checksum": "",
	}
	model["checksum"] = Utils.compute_checksum(model)
	return model

static func _near(left: float, right: float, rel_tol: float, abs_tol: float = 0.0) -> bool:
	if not is_finite(left) or not is_finite(right):
		return false
	var scale := maxf(1.0, maxf(absf(left), absf(right)))
	return absf(left - right) <= abs_tol + rel_tol * scale
