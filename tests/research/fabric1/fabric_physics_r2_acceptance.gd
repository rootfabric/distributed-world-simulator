extends SceneTree

const Compiler = preload("res://scripts/research/fabric_bake0/fabric_physics_r2_compiler_v1.gd")
const MaterialLaw = preload("res://scripts/research/fabric_bake0/fabric_physics_r2_material_law_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Bond = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const Batch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")

const REL_TOL := 1.0e-9
const ABS_TOL := 1.0e-12

var _failures: Array[String] = []

func _initialize() -> void:
	_test_material_laws()
	_test_mechanical_analytic_and_capacity_separation()
	_test_mechanical_geometry_material_metamorphics()
	_test_guard_is_not_failure()
	_test_small_mechanical_systems()
	_test_electrical_series_parallel()
	_test_electrical_metamorphics_and_strength_independence()
	_test_fail_closed_inputs()

	if not _failures.is_empty():
		print("FABRIC_PHYSICS_R2_FAILURES=", JSON.stringify(_failures))
		print("FABRIC-PHYSICS-R2: FAIL")
		quit(1)
		return
	print("FABRIC-PHYSICS-R2: PASS")
	quit(0)

func _test_material_laws() -> void:
	var steel_mech := MaterialLaw.resolve("material/steel", MaterialLaw.DOMAIN_MECHANICAL_AXIAL)
	var copper_elec := MaterialLaw.resolve("material/copper", MaterialLaw.DOMAIN_ELECTRICAL_RESISTIVE)
	_expect(bool(steel_mech.get("success", false)), "R2-A steel mechanical law resolves")
	_expect(bool(copper_elec.get("success", false)), "R2-A copper electrical law resolves")
	if steel_mech.get("success", false):
		_expect(_near(float(steel_mech.details.law.parameters.youngs_modulus_pa), 2.00e11), "R2-A steel E nominal")
	if copper_elec.get("success", false):
		_expect(_near(float(copper_elec.details.law.parameters.resistivity_ohm_m), 1.68e-8), "R2-A copper rho nominal")

func _test_mechanical_analytic_and_capacity_separation() -> void:
	var snapshot := _mechanical_chain("spring-base", 2, 2.0, 0.01, 100.0, [0.0, 0.0, 0.0])
	var matter := _matter("spring-base", 2.0, "material/steel")
	var compiled := Compiler.compile_mechanical(snapshot, matter)
	_expect(bool(compiled.get("success", false)), "R2-B base spring compiles")
	if not compiled.get("success", false):
		return
	var model: Dictionary = compiled.details.model
	var element: Dictionary = model.elements[0]
	var expected_k := 2.00e11 * 0.01 / 2.0
	_expect(_near(float(element.stiffness_n_per_m), expected_k), "R2-B k=E*A/L")
	_expect(_near(float(element.capacity_n), 100.0), "R2-B capacity preserved")

	var response := Compiler.mechanical_static_response(model, String(element.element_id), 50.0)
	_expect(bool(response.get("success", false)), "R2-G static response evaluates")
	if response.get("success", false):
		var expected_x := 50.0 / expected_k
		var expected_energy := 0.5 * expected_k * expected_x * expected_x
		_expect(_near(float(response.details.displacement_m), expected_x), "R2-G x=F/k analytic")
		_expect(_near(float(response.details.stored_energy_j), expected_energy), "R2-G U=0.5*k*x^2")
		_expect(_near(float(response.details.stored_energy_j), float(response.details.quasistatic_work_j)), "R2-G elastic energy balance")

	var stronger_snapshot := _mechanical_chain("spring-stronger", 2, 2.0, 0.01, 200.0, [0.0, 0.0, 0.0])
	var stronger := Compiler.compile_mechanical(stronger_snapshot, _matter("spring-stronger", 2.0, "material/steel"))
	_expect(bool(stronger.get("success", false)), "R2-B capacity variant compiles")
	if stronger.get("success", false):
		var stronger_element: Dictionary = stronger.details.model.elements[0]
		_expect(_near(float(stronger_element.stiffness_n_per_m), float(element.stiffness_n_per_m)), "R2-B capacity does not alter stiffness")
		_expect(_near(float(stronger_element.capacity_n), 200.0), "R2-B capacity changes independently")

func _test_mechanical_geometry_material_metamorphics() -> void:
	var base := Compiler.compile_mechanical(
		_mechanical_chain("mech-morph-base", 2, 1.0, 0.002, 100.0, [0.0, 0.0, 0.0]),
		_matter("mech-morph-base", 2.0, "material/steel")
	)
	var long_case := Compiler.compile_mechanical(
		_mechanical_chain("mech-morph-long", 2, 2.0, 0.002, 100.0, [0.0, 0.0, 0.0]),
		_matter("mech-morph-long", 2.0, "material/steel")
	)
	var wide_case := Compiler.compile_mechanical(
		_mechanical_chain("mech-morph-wide", 2, 1.0, 0.004, 100.0, [0.0, 0.0, 0.0]),
		_matter("mech-morph-wide", 2.0, "material/steel")
	)
	var rubber_case := Compiler.compile_mechanical(
		_mechanical_chain("mech-morph-rubber", 2, 1.0, 0.002, 100.0, [0.0, 0.0, 0.0]),
		_matter("mech-morph-rubber", 2.0, "material/rubber")
	)
	var translated := Compiler.compile_mechanical(
		_mechanical_chain("mech-morph-shifted", 2, 1.0, 0.002, 100.0, [100.0, -25.0, 3.0]),
		_matter("mech-morph-shifted", 2.0, "material/steel")
	)
	var renamed := Compiler.compile_mechanical(
		_mechanical_chain("zz-renamed-physical-equivalent", 2, 1.0, 0.002, 100.0, [0.0, 0.0, 0.0]),
		_matter("zz-renamed-physical-equivalent", 2.0, "material/steel")
	)
	for pair in [
		[base, "base"], [long_case, "length"], [wide_case, "area"],
		[rubber_case, "material"], [translated, "translation"], [renamed, "rename"],
	]:
		_expect(bool(pair[0].get("success", false)), "R2-F mechanical %s variant compiles" % pair[1])
	if not _all_success([base, long_case, wide_case, rubber_case, translated, renamed]):
		return
	var k0 := float(base.details.model.elements[0].stiffness_n_per_m)
	_expect(_near(float(long_case.details.model.elements[0].stiffness_n_per_m), 0.5 * k0), "R2-F k inverse with length")
	_expect(_near(float(wide_case.details.model.elements[0].stiffness_n_per_m), 2.0 * k0), "R2-F k linear with area")
	_expect(_near(float(rubber_case.details.model.elements[0].stiffness_n_per_m) / k0, 1.00e6 / 2.00e11), "R2-F material changes stiffness by law")
	_expect(_near(float(translated.details.model.elements[0].stiffness_n_per_m), k0), "R2-F rigid translation preserves stiffness")
	_expect(_near(float(renamed.details.model.elements[0].stiffness_n_per_m), k0), "R2-F canonical ID rename preserves stiffness")

func _test_guard_is_not_failure() -> void:
	var compiled := Compiler.compile_mechanical(
		_mechanical_chain("guard", 2, 1.0, 0.001, 100.0, [0.0, 0.0, 0.0]),
		_matter("guard", 2.0, "material/steel")
	)
	_expect(bool(compiled.get("success", false)), "R2-D guard fixture compiles")
	if not compiled.get("success", false):
		return
	var element: Dictionary = compiled.details.model.elements[0]
	var at70 := Compiler.evaluate_guard(element, 70.0, 0.8)
	var at90 := Compiler.evaluate_guard(element, 90.0, 0.8)
	var unload70 := Compiler.evaluate_guard(element, 70.0, 0.8)
	var at110 := Compiler.evaluate_guard(element, 110.0, 0.8)
	_expect(at70.get("success", false) and at70.details.decision == "SAFE", "R2-D 70N SAFE")
	_expect(at90.get("success", false) and at90.details.decision == "REFINE", "R2-D 90N REFINE")
	_expect(at90.get("success", false) and not bool(at90.details.failure_proposal) and not bool(at90.details.damage_committed), "R2-D guard crossing is not damage")
	_expect(unload70.get("success", false) and unload70.details.decision == "SAFE", "R2-D unload after guard returns SAFE")
	_expect(at110.get("success", false) and at110.details.decision == "FAILURE_PROPOSAL", "R2-D 110N proposes failure")
	_expect(at110.get("success", false) and bool(at110.details.failure_proposal) and not bool(at110.details.damage_committed), "R2-D proposal does not commit canonical damage")

func _test_small_mechanical_systems() -> void:
	for count in [2, 6, 20]:
		var label := "small-%d" % count
		var compiled := Compiler.compile_mechanical(
			_mechanical_chain(label, count, 0.5, 0.001, 100.0, [0.0, 0.0, 0.0]),
			_matter(label, float(count), "material/steel")
		)
		_expect(bool(compiled.get("success", false)), "R2-E %d-part system compiles" % count)
		if compiled.get("success", false):
			_expect(compiled.details.model.nodes.size() == count, "R2-E %d-part node count" % count)
			_expect(compiled.details.model.elements.size() == count - 1, "R2-E %d-part element count" % count)

func _test_electrical_series_parallel() -> void:
	var series_snapshot := _electrical_series("series", 1.0, 1.0e-6, 100.0, [0.0, 0.0, 0.0])
	var series := Compiler.compile_electrical(series_snapshot, _matter("series", 3.0, "material/copper"))
	_expect(bool(series.get("success", false)), "R2-C series fixture compiles")
	if series.get("success", false):
		var expected_r := 1.68e-8 * 1.0 / 1.0e-6
		var r0 := float(series.details.model.elements[0].resistance_ohm)
		var r1 := float(series.details.model.elements[1].resistance_ohm)
		_expect(_near(r0, expected_r) and _near(r1, expected_r), "R2-G resistor R=rho*L/A")
		_expect(_near(r0 + r1, 2.0 * expected_r), "R2-G two resistors series analytic")

	var parallel_snapshot := _electrical_parallel("parallel", 1.0, 1.0e-6, 100.0, [0.0, 0.0, 0.0])
	var parallel := Compiler.compile_electrical(parallel_snapshot, _matter("parallel", 2.0, "material/copper"))
	_expect(bool(parallel.get("success", false)), "R2-C parallel fixture compiles")
	if parallel.get("success", false):
		var elements: Array = parallel.details.model.elements
		var g_total := float(elements[0].conductance_siemens) + float(elements[1].conductance_siemens)
		var equivalent_r := 1.0 / g_total
		var expected_single := 1.68e-8 * 1.0 / 1.0e-6
		_expect(_near(equivalent_r, expected_single / 2.0), "R2-G two resistors parallel analytic")

func _test_electrical_metamorphics_and_strength_independence() -> void:
	var base := Compiler.compile_electrical(
		_electrical_parallel("elec-base", 1.0, 1.0e-6, 10.0, [0.0, 0.0, 0.0]),
		_matter("elec-base", 2.0, "material/copper")
	)
	var stronger := Compiler.compile_electrical(
		_electrical_parallel("elec-stronger", 1.0, 1.0e-6, 10000.0, [0.0, 0.0, 0.0]),
		_matter("elec-stronger", 2.0, "material/copper")
	)
	var longer := Compiler.compile_electrical(
		_electrical_parallel("elec-longer", 2.0, 1.0e-6, 10.0, [0.0, 0.0, 0.0]),
		_matter("elec-longer", 2.0, "material/copper")
	)
	var wider := Compiler.compile_electrical(
		_electrical_parallel("elec-wider", 1.0, 2.0e-6, 10.0, [0.0, 0.0, 0.0]),
		_matter("elec-wider", 2.0, "material/copper")
	)
	var aluminum := Compiler.compile_electrical(
		_electrical_parallel("elec-aluminum", 1.0, 1.0e-6, 10.0, [0.0, 0.0, 0.0]),
		_matter("elec-aluminum", 2.0, "material/aluminum")
	)
	var translated := Compiler.compile_electrical(
		_electrical_parallel("elec-translated", 1.0, 1.0e-6, 10.0, [17.0, 4.0, -9.0]),
		_matter("elec-translated", 2.0, "material/copper")
	)
	if not _all_success([base, stronger, longer, wider, aluminum, translated]):
		_expect(false, "R2-F electrical metamorphic variants compile")
		return
	var r0 := float(base.details.model.elements[0].resistance_ohm)
	_expect(_near(float(stronger.details.model.elements[0].resistance_ohm), r0), "R2-C strength_n does not alter electrical R")
	_expect(_near(float(longer.details.model.elements[0].resistance_ohm), 2.0 * r0), "R2-F R linear with length")
	_expect(_near(float(wider.details.model.elements[0].resistance_ohm), 0.5 * r0), "R2-F R inverse with area")
	_expect(_near(float(aluminum.details.model.elements[0].resistance_ohm) / r0, 2.82e-8 / 1.68e-8), "R2-F material changes R by law")
	_expect(_near(float(translated.details.model.elements[0].resistance_ohm), r0), "R2-F rigid translation preserves resistance")

func _test_fail_closed_inputs() -> void:
	var unknown := Compiler.compile_mechanical(
		_mechanical_chain("unknown-material", 2, 1.0, 0.001, 100.0, [0.0, 0.0, 0.0]),
		_matter("unknown-material", 2.0, "material/unobtainium")
	)
	_expect(not unknown.get("success", false) and unknown.get("error_code", "") == "PHYSICS_R2_MATERIAL_LAW_MISSING", "R2-A unknown material fails closed")

	var mixed := Compiler.compile_mechanical(
		_mechanical_chain("mixed-material", 2, 1.0, 0.001, 100.0, [0.0, 0.0, 0.0]),
		_mixed_matter("mixed-material", 2.0)
	)
	_expect(not mixed.get("success", false) and mixed.get("error_code", "") == "PHYSICS_R2_MIXED_MATERIAL_OUT_OF_SCOPE", "R2-A mixture fails closed")

	var hot := Compiler.compile_mechanical(
		_mechanical_chain("hot-material", 2, 1.0, 0.001, 100.0, [0.0, 0.0, 0.0]),
		_matter("hot-material", 2.0, "material/steel", 350.0)
	)
	_expect(not hot.get("success", false) and hot.get("error_code", "") == "PHYSICS_R2_TEMPERATURE_OUT_OF_SCOPE", "R2-A unsupported temperature fails closed")

	var missing_area := _mechanical_chain("missing-area", 2, 1.0, 0.001, 100.0, [0.0, 0.0, 0.0])
	missing_area.bonds[0].metadata.erase("area_m2")
	missing_area.checksum = Snapshot.compute_checksum(missing_area)
	var no_area := Compiler.compile_mechanical(missing_area, _matter("missing-area", 2.0, "material/steel"))
	_expect(not no_area.get("success", false) and no_area.get("error_code", "") == "PHYSICS_R2_AREA_REQUIRED", "R2-B missing geometry fails closed")

func _mechanical_chain(label: String, count: int, spacing_m: float, area_m2: float, strength_n: float, offset: Array) -> Dictionary:
	var parts: Array = []
	for index in range(count):
		parts.append(Part.create(
			"part/%s/%03d" % [label, index],
			"item/%s-%03d" % [label, index],
			"BEAM",
			"anchor" if index == 0 else "member",
			1.0,
			[
				float(offset[0]) + float(index) * spacing_m,
				float(offset[1]),
				float(offset[2]),
			],
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
			{"area_m2": area_m2, "damping_ns_per_m": 5.0}
		))
	return Snapshot.create("construct/%s" % label, "item/%s-root" % label, 0, "OPERATIONAL", parts, bonds, {})

func _electrical_series(label: String, spacing_m: float, area_m2: float, strength_n: float, offset: Array) -> Dictionary:
	var parts: Array = []
	for index in range(3):
		parts.append(Part.create(
			"part/%s/%03d" % [label, index], "item/%s-%03d" % [label, index],
			"CONDUCTOR", "terminal" if index == 0 or index == 2 else "junction", 1.0,
			[float(offset[0]) + float(index) * spacing_m, float(offset[1]), float(offset[2])]
		))
	var bonds: Array = []
	for index in range(2):
		bonds.append(Bond.create(
			"bond/%s/%03d" % [label, index], "part/%s/%03d" % [label, index],
			"part/%s/%03d" % [label, index + 1], "ELECTRICAL_RESISTOR", strength_n,
			"INTACT", {"area_m2": area_m2}
		))
	return Snapshot.create("construct/%s" % label, "item/%s-root" % label, 0, "OPERATIONAL", parts, bonds, {})

func _electrical_parallel(label: String, spacing_m: float, area_m2: float, strength_n: float, offset: Array) -> Dictionary:
	var parts: Array = [
		Part.create("part/%s/a" % label, "item/%s-a" % label, "CONDUCTOR", "terminal", 1.0,
			[float(offset[0]), float(offset[1]), float(offset[2])]),
		Part.create("part/%s/b" % label, "item/%s-b" % label, "CONDUCTOR", "terminal", 1.0,
			[float(offset[0]) + spacing_m, float(offset[1]), float(offset[2])]),
	]
	var bonds: Array = [
		Bond.create("bond/%s/a" % label, "part/%s/a" % label, "part/%s/b" % label,
			"ELECTRICAL_RESISTOR", strength_n, "INTACT", {"area_m2": area_m2}),
		Bond.create("bond/%s/b" % label, "part/%s/a" % label, "part/%s/b" % label,
			"ELECTRICAL_RESISTOR", strength_n, "INTACT", {"area_m2": area_m2}),
	]
	return Snapshot.create("construct/%s" % label, "item/%s-root" % label, 0, "OPERATIONAL", parts, bonds, {})

func _matter(label: String, mass_kg: float, material_id: String, temperature_k: float = MaterialLaw.REFERENCE_TEMPERATURE_K) -> Dictionary:
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
		"temperature_k": MaterialLaw.REFERENCE_TEMPERATURE_K,
	})

func _all_success(results: Array) -> bool:
	for result in results:
		if typeof(result) != TYPE_DICTIONARY or not bool(result.get("success", false)):
			return false
	return true

func _near(left: float, right: float, rel_tol: float = REL_TOL, abs_tol: float = ABS_TOL) -> bool:
	if not is_finite(left) or not is_finite(right):
		return false
	var scale := maxf(1.0, maxf(absf(left), absf(right)))
	return absf(left - right) <= abs_tol + rel_tol * scale

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
