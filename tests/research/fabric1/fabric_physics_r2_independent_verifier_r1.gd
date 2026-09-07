extends SceneTree

const Compiler = preload("res://scripts/research/fabric_bake0/fabric_physics_r2_compiler_v1.gd")
const MaterialLaw = preload("res://scripts/research/fabric_bake0/fabric_physics_r2_material_law_v1.gd")
const ModelContract = preload("res://scripts/research/fabric_bake0/fabric_physics_r2_model_contract_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Bond = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const Batch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")

const REFERENCE_TEMPERATURE_K := 293.15
const STEEL_E_PA := 2.00e11
const COPPER_RHO_OHM_M := 1.68e-8
const REL_TOL := 1.0e-10
const ABS_TOL := 1.0e-12

var _failures: Array[String] = []

func _initialize() -> void:
	_verify_nominal_material_laws()
	_verify_mechanical_reference_oracle()
	_verify_guard_boundaries()
	_verify_rigid_transform_and_id_permutation()
	_verify_small_systems_and_full_fallback()
	_verify_electrical_reference_oracles()
	_verify_fail_closed_and_checksum_fencing()

	if not _failures.is_empty():
		print("FABRIC_PHYSICS_R2_INDEPENDENT_VERIFIER_R1_FAILURES=", JSON.stringify(_failures))
		print("FABRIC-PHYSICS-R2-INDEPENDENT-VERIFIER-R1: FAIL")
		quit(1)
		return
	print("FABRIC-PHYSICS-R2-INDEPENDENT-VERIFIER-R1: PASS")
	quit(0)

func _verify_nominal_material_laws() -> void:
	var expected_mechanical := {
		"material/steel": 2.00e11,
		"material/aluminum": 6.90e10,
		"material/copper": 1.10e11,
		"material/rubber": 1.00e6,
	}
	var expected_electrical := {
		"material/steel": 1.43e-7,
		"material/aluminum": 2.82e-8,
		"material/copper": 1.68e-8,
		"material/rubber": 1.00e13,
	}
	for material_id in expected_mechanical.keys():
		var resolved := MaterialLaw.resolve(String(material_id), "MECHANICAL_AXIAL")
		_expect(bool(resolved.get("success", false)), "material mechanical resolves: %s" % material_id)
		if bool(resolved.get("success", false)):
			_expect(_near(float(resolved.details.law.parameters.youngs_modulus_pa), float(expected_mechanical[material_id])), "material mechanical nominal: %s" % material_id)
			_expect(_near(float(resolved.details.law.reference_temperature_k), REFERENCE_TEMPERATURE_K), "material mechanical temperature: %s" % material_id)
	for material_id in expected_electrical.keys():
		var resolved := MaterialLaw.resolve(String(material_id), "ELECTRICAL_RESISTIVE")
		_expect(bool(resolved.get("success", false)), "material electrical resolves: %s" % material_id)
		if bool(resolved.get("success", false)):
			_expect(_near(float(resolved.details.law.parameters.resistivity_ohm_m), float(expected_electrical[material_id])), "material electrical nominal: %s" % material_id)

func _verify_mechanical_reference_oracle() -> void:
	var p0 := [1.0, 2.0, 3.0]
	var p1 := [4.0, 6.0, 8.0]
	var area_m2 := 0.0025
	var capacity_n := 100.0
	var snapshot := _mechanical_pair("ivr-mech-reference", p0, p1, area_m2, capacity_n, "a", "b")
	var compiled := Compiler.compile_mechanical(snapshot, _matter("ivr-mech-reference", 2.0, "material/steel"))
	_expect(bool(compiled.get("success", false)), "mechanical reference compiles")
	if not bool(compiled.get("success", false)):
		return

	var element: Dictionary = compiled.details.model.elements[0]
	var expected_length := _distance(p0, p1)
	var expected_k := STEEL_E_PA * area_m2 / expected_length
	_expect(_near(float(element.length_m), expected_length), "mechanical reference length")
	_expect(_near(float(element.area_m2), area_m2), "mechanical reference area")
	_expect(_near(float(element.stiffness_n_per_m), expected_k), "mechanical k = E*A/L")
	_expect(_near(float(element.capacity_n), capacity_n), "mechanical capacity preserved")

	var force_n := 123.4
	var response := Compiler.mechanical_static_response(compiled.details.model, String(element.element_id), force_n)
	_expect(bool(response.get("success", false)), "mechanical static response evaluates")
	if bool(response.get("success", false)):
		var expected_x := force_n / expected_k
		var expected_u := 0.5 * expected_k * expected_x * expected_x
		_expect(_near(float(response.details.displacement_m), expected_x), "mechanical x = F/k")
		_expect(_near(float(response.details.stored_energy_j), expected_u), "mechanical U = 0.5*k*x^2")
		_expect(_near(float(response.details.quasistatic_work_j), 0.5 * force_n * expected_x), "mechanical W = 0.5*F*x")
		_expect(_near(float(response.details.stored_energy_j), float(response.details.quasistatic_work_j)), "mechanical energy/work parity")

	var stronger := Compiler.compile_mechanical(
		_mechanical_pair("ivr-mech-capacity", p0, p1, area_m2, 1000.0, "a", "b"),
		_matter("ivr-mech-capacity", 2.0, "material/steel")
	)
	_expect(bool(stronger.get("success", false)), "mechanical capacity variant compiles")
	if bool(stronger.get("success", false)):
		var stronger_element: Dictionary = stronger.details.model.elements[0]
		_expect(_near(float(stronger_element.stiffness_n_per_m), expected_k), "strength_n does not affect stiffness")
		_expect(_near(float(stronger_element.capacity_n), 1000.0), "strength_n changes capacity only")

func _verify_guard_boundaries() -> void:
	var compiled := Compiler.compile_mechanical(
		_mechanical_pair("ivr-guard", [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], 0.001, 100.0, "a", "b"),
		_matter("ivr-guard", 2.0, "material/steel")
	)
	_expect(bool(compiled.get("success", false)), "guard fixture compiles")
	if not bool(compiled.get("success", false)):
		return
	var element: Dictionary = compiled.details.model.elements[0]
	var cases := [
		[79.9999, "SAFE", false],
		[80.0, "SAFE", false],
		[80.0001, "REFINE", false],
		[100.0, "REFINE", false],
		[100.0001, "FAILURE_PROPOSAL", true],
		[-101.0, "FAILURE_PROPOSAL", true],
		[70.0, "SAFE", false],
	]
	for row in cases:
		var decision := Compiler.evaluate_guard(element, float(row[0]), 0.8)
		_expect(bool(decision.get("success", false)), "guard case evaluates: %s" % row[0])
		if bool(decision.get("success", false)):
			_expect(String(decision.details.decision) == String(row[1]), "guard decision: %s" % row[0])
			_expect(bool(decision.details.failure_proposal) == bool(row[2]), "guard proposal flag: %s" % row[0])
			_expect(not bool(decision.details.damage_committed), "guard never commits canonical damage: %s" % row[0])

func _verify_rigid_transform_and_id_permutation() -> void:
	var base_a := [2.0, -1.0, 4.0]
	var base_b := [5.0, 3.0, 10.0]
	var area_m2 := 0.003
	var base := Compiler.compile_mechanical(
		_mechanical_pair("ivr-rigid-base", base_a, base_b, area_m2, 250.0, "left", "right"),
		_matter("ivr-rigid-base", 2.0, "material/steel")
	)
	var transformed_a := _rigid_transform(base_a)
	var transformed_b := _rigid_transform(base_b)
	var transformed := Compiler.compile_mechanical(
		_mechanical_pair("ivr-rigid-permuted", transformed_a, transformed_b, area_m2, 250.0, "node-z", "node-a"),
		_matter("ivr-rigid-permuted", 2.0, "material/steel")
	)
	_expect(bool(base.get("success", false)), "rigid base compiles")
	_expect(bool(transformed.get("success", false)), "rigid transformed/permuted compiles")
	if not bool(base.get("success", false)) or not bool(transformed.get("success", false)):
		return
	var base_element: Dictionary = base.details.model.elements[0]
	var transformed_element: Dictionary = transformed.details.model.elements[0]
	_expect(_near(float(base_element.length_m), float(transformed_element.length_m)), "rigid transform preserves length")
	_expect(_near(float(base_element.stiffness_n_per_m), float(transformed_element.stiffness_n_per_m)), "rigid transform + ID permutation preserves stiffness")
	_expect(String(base_element.element_id) != String(transformed_element.element_id), "ID permutation actually changes element identity")

func _verify_small_systems_and_full_fallback() -> void:
	for count in [2, 6, 20]:
		var label := "ivr-small-%d" % count
		var snapshot := _mechanical_chain(label, count, 0.37, 0.0013, 77.0)
		var compiled := Compiler.compile_mechanical(snapshot, _matter(label, float(count), "material/steel"))
		_expect(bool(compiled.get("success", false)), "small system compiles: %d" % count)
		if not bool(compiled.get("success", false)):
			continue
		var model: Dictionary = compiled.details.model
		_expect(model.nodes.size() == count, "small system node count exact: %d" % count)
		_expect(model.elements.size() == count - 1, "small system element count exact: %d" % count)
		var bound := ModelContract.bind(model)
		_expect(bool(bound.get("success", false)), "small system model contract binds: %d" % count)
		if bool(bound.get("success", false)):
			var contract: Dictionary = bound.details.contract
			_expect(String(contract.execution_mode) == "FULL", "small system FULL fallback: %d" % count)
			_expect(contract.bake_certified == false, "small system bake remains uncertified: %d" % count)
			_expect(contract.legacy_surrogate_compatible == false, "small system legacy surrogate forbidden: %d" % count)
			_expect(String(contract.execution_reason) == "PHYSICS_R2_TYPED_BAKE_NOT_CERTIFIED", "small system execution reason exact: %d" % count)
			_expect(contract.dimension_basis == ["kg", "m", "s", "A", "K", "mol", "cd"], "mechanical SI basis exact: %d" % count)
			_expect(contract.dimensions == _expected_mechanical_dimensions(), "mechanical SI signatures exact: %d" % count)

func _verify_electrical_reference_oracles() -> void:
	var series := Compiler.compile_electrical(
		_electrical_series_nonuniform("ivr-elec-series"),
		_matter("ivr-elec-series", 3.0, "material/copper")
	)
	_expect(bool(series.get("success", false)), "electrical nonuniform series compiles")
	if bool(series.get("success", false)):
		var elements: Array = series.details.model.elements
		var expected_r0 := COPPER_RHO_OHM_M * 0.5 / 2.0e-6
		var expected_r1 := COPPER_RHO_OHM_M * 1.5 / 5.0e-6
		_expect(_near(float(elements[0].resistance_ohm), expected_r0), "series R0 = rho*L/A")
		_expect(_near(float(elements[1].resistance_ohm), expected_r1), "series R1 = rho*L/A")
		_expect(_near(float(elements[0].resistance_ohm) + float(elements[1].resistance_ohm), expected_r0 + expected_r1), "series equivalent analytic")

	var parallel := Compiler.compile_electrical(
		_electrical_parallel_nonuniform("ivr-elec-parallel", 10.0),
		_matter("ivr-elec-parallel", 2.0, "material/copper")
	)
	_expect(bool(parallel.get("success", false)), "electrical nonuniform parallel compiles")
	if bool(parallel.get("success", false)):
		var elements: Array = parallel.details.model.elements
		var expected_r0 := COPPER_RHO_OHM_M * 1.25 / 1.0e-6
		var expected_r1 := COPPER_RHO_OHM_M * 1.25 / 4.0e-6
		var expected_eq := 1.0 / (1.0 / expected_r0 + 1.0 / expected_r1)
		var actual_eq := 1.0 / (float(elements[0].conductance_siemens) + float(elements[1].conductance_siemens))
		_expect(_near(float(elements[0].resistance_ohm), expected_r0), "parallel R0 analytic")
		_expect(_near(float(elements[1].resistance_ohm), expected_r1), "parallel R1 analytic")
		_expect(_near(actual_eq, expected_eq), "parallel equivalent analytic")
		var bound := ModelContract.bind(parallel.details.model)
		_expect(bool(bound.get("success", false)), "electrical model contract binds")
		if bool(bound.get("success", false)):
			_expect(bound.details.contract.dimensions == _expected_electrical_dimensions(), "electrical SI signatures exact")
			_expect(bound.details.contract.execution_mode == "FULL", "electrical FULL fallback")
			_expect(bound.details.contract.bake_certified == false, "electrical bake uncertified")
			_expect(bound.details.contract.legacy_surrogate_compatible == false, "electrical legacy surrogate forbidden")

	var stronger := Compiler.compile_electrical(
		_electrical_parallel_nonuniform("ivr-elec-strength-independent", 100000.0),
		_matter("ivr-elec-strength-independent", 2.0, "material/copper")
	)
	_expect(bool(stronger.get("success", false)), "electrical strength variant compiles")
	if bool(parallel.get("success", false)) and bool(stronger.get("success", false)):
		for index in range(2):
			_expect(_near(float(parallel.details.model.elements[index].resistance_ohm), float(stronger.details.model.elements[index].resistance_ohm)), "strength_n does not affect resistance: %d" % index)

func _verify_fail_closed_and_checksum_fencing() -> void:
	var base_snapshot := _mechanical_pair("ivr-fail-base", [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], 0.001, 100.0, "a", "b")
	var unknown := Compiler.compile_mechanical(base_snapshot, _matter("ivr-fail-base", 2.0, "material/unobtainium"))
	_expect(not bool(unknown.get("success", false)) and String(unknown.get("error_code", "")) == "PHYSICS_R2_MATERIAL_LAW_MISSING", "unknown material fails closed")

	var mixed_snapshot := _mechanical_pair("ivr-fail-mixed", [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], 0.001, 100.0, "a", "b")
	var mixed := Compiler.compile_mechanical(mixed_snapshot, _mixed_matter("ivr-fail-mixed", 2.0))
	_expect(not bool(mixed.get("success", false)) and String(mixed.get("error_code", "")) == "PHYSICS_R2_MIXED_MATERIAL_OUT_OF_SCOPE", "mixed material fails closed")

	var hot_snapshot := _mechanical_pair("ivr-fail-temp", [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], 0.001, 100.0, "a", "b")
	var hot := Compiler.compile_mechanical(hot_snapshot, _matter("ivr-fail-temp", 2.0, "material/steel", 294.15))
	_expect(not bool(hot.get("success", false)) and String(hot.get("error_code", "")) == "PHYSICS_R2_TEMPERATURE_OUT_OF_SCOPE", "unsupported temperature fails closed")

	var missing_area := _mechanical_pair("ivr-fail-area", [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], 0.001, 100.0, "a", "b")
	missing_area.bonds[0].metadata.erase("area_m2")
	missing_area.checksum = Snapshot.compute_checksum(missing_area)
	var no_area := Compiler.compile_mechanical(missing_area, _matter("ivr-fail-area", 2.0, "material/steel"))
	_expect(not bool(no_area.get("success", false)) and String(no_area.get("error_code", "")) == "PHYSICS_R2_AREA_REQUIRED", "missing area fails closed")

	var valid := Compiler.compile_mechanical(
		_mechanical_pair("ivr-checksum", [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], 0.001, 100.0, "a", "b"),
		_matter("ivr-checksum", 2.0, "material/steel")
	)
	_expect(bool(valid.get("success", false)), "checksum fixture compiles")
	if bool(valid.get("success", false)):
		var tampered: Dictionary = valid.details.model.duplicate(true)
		var elements: Array = tampered.elements
		var first: Dictionary = Dictionary(elements[0]).duplicate(true)
		first.stiffness_n_per_m = float(first.stiffness_n_per_m) * 1.01
		elements[0] = first
		tampered.elements = elements
		var fenced := Compiler.mechanical_static_response(tampered, String(first.element_id), 10.0)
		_expect(not bool(fenced.get("success", false)) and String(fenced.get("error_code", "")) == "PHYSICS_R2_MODEL_CHECKSUM_INVALID", "tampered model checksum is fenced")

func _mechanical_pair(label: String, position_a: Array, position_b: Array, area_m2: float, strength_n: float, id_a: String, id_b: String) -> Dictionary:
	var parts: Array = [
		Part.create("part/%s/%s" % [label, id_a], "item/%s-%s" % [label, id_a], "BEAM", "anchor", 1.0, position_a.duplicate(), {"physics_r2_anchor": true}),
		Part.create("part/%s/%s" % [label, id_b], "item/%s-%s" % [label, id_b], "BEAM", "member", 1.0, position_b.duplicate(), {"physics_r2_anchor": false}),
	]
	var bonds: Array = [
		Bond.create("bond/%s/link" % label, "part/%s/%s" % [label, id_a], "part/%s/%s" % [label, id_b], "AXIAL_SPRING", strength_n, "INTACT", {"area_m2": area_m2, "damping_ns_per_m": 3.25}),
	]
	return Snapshot.create("construct/%s" % label, "item/%s-root" % label, 0, "OPERATIONAL", parts, bonds, {})

func _mechanical_chain(label: String, count: int, spacing_m: float, area_m2: float, strength_n: float) -> Dictionary:
	var parts: Array = []
	for index in range(count):
		parts.append(Part.create(
			"part/%s/%03d" % [label, index],
			"item/%s-%03d" % [label, index],
			"BEAM",
			"anchor" if index == 0 else "member",
			1.0,
			[float(index) * spacing_m, float(index % 3) * 0.11, float(index % 2) * 0.07],
			{"physics_r2_anchor": index == 0}
		))
	var bonds: Array = []
	for index in range(count - 1):
		bonds.append(Bond.create(
			"bond/%s/%03d" % [label, index],
			"part/%s/%03d" % [label, index],
			"part/%s/%03d" % [label, index + 1],
			"AXIAL_SPRING",
			strength_n,
			"INTACT",
			{"area_m2": area_m2, "damping_ns_per_m": 2.0 + float(index) * 0.01}
		))
	return Snapshot.create("construct/%s" % label, "item/%s-root" % label, 0, "OPERATIONAL", parts, bonds, {})

func _electrical_series_nonuniform(label: String) -> Dictionary:
	var parts: Array = [
		Part.create("part/%s/a" % label, "item/%s-a" % label, "CONDUCTOR", "terminal", 1.0, [0.0, 0.0, 0.0]),
		Part.create("part/%s/b" % label, "item/%s-b" % label, "CONDUCTOR", "junction", 1.0, [0.5, 0.0, 0.0]),
		Part.create("part/%s/c" % label, "item/%s-c" % label, "CONDUCTOR", "terminal", 1.0, [2.0, 0.0, 0.0]),
	]
	var bonds: Array = [
		Bond.create("bond/%s/ab" % label, "part/%s/a" % label, "part/%s/b" % label, "ELECTRICAL_RESISTOR", 17.0, "INTACT", {"area_m2": 2.0e-6}),
		Bond.create("bond/%s/bc" % label, "part/%s/b" % label, "part/%s/c" % label, "ELECTRICAL_RESISTOR", 900.0, "INTACT", {"area_m2": 5.0e-6}),
	]
	return Snapshot.create("construct/%s" % label, "item/%s-root" % label, 0, "OPERATIONAL", parts, bonds, {})

func _electrical_parallel_nonuniform(label: String, strength_n: float) -> Dictionary:
	var parts: Array = [
		Part.create("part/%s/a" % label, "item/%s-a" % label, "CONDUCTOR", "terminal", 1.0, [0.0, 0.0, 0.0]),
		Part.create("part/%s/b" % label, "item/%s-b" % label, "CONDUCTOR", "terminal", 1.0, [1.25, 0.0, 0.0]),
	]
	var bonds: Array = [
		Bond.create("bond/%s/narrow" % label, "part/%s/a" % label, "part/%s/b" % label, "ELECTRICAL_RESISTOR", strength_n, "INTACT", {"area_m2": 1.0e-6}),
		Bond.create("bond/%s/wide" % label, "part/%s/a" % label, "part/%s/b" % label, "ELECTRICAL_RESISTOR", strength_n, "INTACT", {"area_m2": 4.0e-6}),
	]
	return Snapshot.create("construct/%s" % label, "item/%s-root" % label, 0, "OPERATIONAL", parts, bonds, {})

func _matter(label: String, mass_kg: float, material_id: String, temperature_k: float = REFERENCE_TEMPERATURE_K) -> Dictionary:
	return Batch.create({
		"batch_id": "batch/%s" % label,
		"container_id": "container/%s" % label,
		"source_body_id": "body/%s" % label,
		"source_operation_id": "operation/%s" % label,
		"total_mass_kg": mass_kg,
		"bulk_volume_m3": maxf(1.0e-6, mass_kg * 1.0e-3),
		"composition": Composition.create([{"material_id": material_id, "mass_fraction": 1.0}]),
		"temperature_k": temperature_k,
	})

func _mixed_matter(label: String, mass_kg: float) -> Dictionary:
	return Batch.create({
		"batch_id": "batch/%s" % label,
		"container_id": "container/%s" % label,
		"source_body_id": "body/%s" % label,
		"source_operation_id": "operation/%s" % label,
		"total_mass_kg": mass_kg,
		"bulk_volume_m3": mass_kg * 1.0e-3,
		"composition": Composition.create([
			{"material_id": "material/copper", "mass_fraction": 0.5},
			{"material_id": "material/steel", "mass_fraction": 0.5},
		]),
		"temperature_k": REFERENCE_TEMPERATURE_K,
	})

func _rigid_transform(point: Array) -> Array:
	# Proper cyclic rotation (x,y,z)->(z,x,y), then translation.
	return [float(point[2]) + 11.0, float(point[0]) - 7.0, float(point[1]) + 4.5]

func _distance(a: Array, b: Array) -> float:
	var dx := float(b[0]) - float(a[0])
	var dy := float(b[1]) - float(a[1])
	var dz := float(b[2]) - float(a[2])
	return sqrt(dx * dx + dy * dy + dz * dz)

func _expected_mechanical_dimensions() -> Dictionary:
	return {
		"mass_kg": [1, 0, 0, 0, 0, 0, 0],
		"length_m": [0, 1, 0, 0, 0, 0, 0],
		"area_m2": [0, 2, 0, 0, 0, 0, 0],
		"youngs_modulus_pa": [1, -1, -2, 0, 0, 0, 0],
		"stiffness_n_per_m": [1, 0, -2, 0, 0, 0, 0],
		"damping_ns_per_m": [1, 0, -1, 0, 0, 0, 0],
		"capacity_n": [1, 1, -2, 0, 0, 0, 0],
		"force_n": [1, 1, -2, 0, 0, 0, 0],
		"displacement_m": [0, 1, 0, 0, 0, 0, 0],
		"energy_j": [1, 2, -2, 0, 0, 0, 0],
	}

func _expected_electrical_dimensions() -> Dictionary:
	return {
		"length_m": [0, 1, 0, 0, 0, 0, 0],
		"area_m2": [0, 2, 0, 0, 0, 0, 0],
		"resistivity_ohm_m": [1, 3, -3, -2, 0, 0, 0],
		"resistance_ohm": [1, 2, -3, -2, 0, 0, 0],
		"conductance_siemens": [-1, -2, 3, 2, 0, 0, 0],
	}

func _near(left: float, right: float, rel_tol: float = REL_TOL, abs_tol: float = ABS_TOL) -> bool:
	if not is_finite(left) or not is_finite(right):
		return false
	var scale := maxf(1.0, maxf(absf(left), absf(right)))
	return absf(left - right) <= abs_tol + rel_tol * scale

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
