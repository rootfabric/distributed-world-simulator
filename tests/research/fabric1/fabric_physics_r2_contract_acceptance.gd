extends SceneTree

const Compiler = preload("res://scripts/research/fabric_bake0/fabric_physics_r2_compiler_v1.gd")
const ModelContract = preload("res://scripts/research/fabric_bake0/fabric_physics_r2_model_contract_v1.gd")
const MaterialLaw = preload("res://scripts/research/fabric_bake0/fabric_physics_r2_material_law_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Bond = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const Batch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	_test_mechanical_dimensions_and_full_fallback()
	_test_electrical_dimensions_and_legacy_quarantine()

	if not _failures.is_empty():
		print("FABRIC_PHYSICS_R2_CONTRACT_FAILURES=", JSON.stringify(_failures))
		print("FABRIC-PHYSICS-R2-CONTRACT: FAIL")
		quit(1)
		return
	print("FABRIC-PHYSICS-R2-CONTRACT: PASS")
	quit(0)

func _test_mechanical_dimensions_and_full_fallback() -> void:
	for count in [2, 6, 20]:
		var label := "contract-mech-%d" % count
		var compiled := Compiler.compile_mechanical(
			_mechanical_chain(label, count),
			_matter(label, float(count), "material/steel")
		)
		_expect(bool(compiled.get("success", false)), "mechanical %d-part model compiles" % count)
		if not compiled.get("success", false):
			continue
		var model: Dictionary = compiled.details.model
		var bound := ModelContract.bind(model)
		_expect(bool(bound.get("success", false)), "mechanical %d-part contract binds" % count)
		if not bound.get("success", false):
			continue
		var contract: Dictionary = bound.details.contract
		_expect(ModelContract.validate(contract).success, "mechanical %d-part contract validates" % count)
		_expect(contract.execution_mode == "FULL", "mechanical %d-part uses safe FULL fallback" % count)
		_expect(contract.bake_certified == false, "mechanical %d-part has no uncertified BAKE" % count)
		_expect(contract.legacy_surrogate_compatible == false, "mechanical %d-part rejects legacy surrogate" % count)
		_expect(model.nodes.size() == count, "mechanical %d-part has no hidden nodes" % count)
		_expect(model.elements.size() == count - 1, "mechanical %d-part preserves topology" % count)
		_expect(contract.dimension_basis == ["kg", "m", "s", "A", "K", "mol", "cd"], "SI basis is explicit")
		_expect(contract.dimensions.youngs_modulus_pa == [1, -1, -2, 0, 0, 0, 0], "Young modulus dimension is Pa")
		_expect(contract.dimensions.stiffness_n_per_m == [1, 0, -2, 0, 0, 0, 0], "stiffness dimension is N/m")
		_expect(contract.dimensions.capacity_n == [1, 1, -2, 0, 0, 0, 0], "capacity dimension is N")

func _test_electrical_dimensions_and_legacy_quarantine() -> void:
	var label := "contract-elec"
	var compiled := Compiler.compile_electrical(
		_electrical_pair(label),
		_matter(label, 2.0, "material/copper")
	)
	_expect(bool(compiled.get("success", false)), "electrical model compiles")
	if not compiled.get("success", false):
		return
	var model: Dictionary = compiled.details.model
	var bound := ModelContract.bind(model)
	_expect(bool(bound.get("success", false)), "electrical contract binds")
	if not bound.get("success", false):
		return
	var contract: Dictionary = bound.details.contract
	_expect(ModelContract.validate(contract).success, "electrical contract validates")
	_expect(contract.execution_mode == "FULL", "electrical model uses safe FULL fallback")
	_expect(contract.bake_certified == false, "electrical model has no uncertified BAKE")
	_expect(contract.legacy_surrogate_compatible == false, "electrical model rejects strength-as-conductance surrogate")
	_expect(contract.dimensions.resistivity_ohm_m == [1, 3, -3, -2, 0, 0, 0], "resistivity dimension is ohm*m")
	_expect(contract.dimensions.resistance_ohm == [1, 2, -3, -2, 0, 0, 0], "resistance dimension is ohm")
	_expect(contract.dimensions.conductance_siemens == [-1, -2, 3, 2, 0, 0, 0], "conductance dimension is siemens")

	var tampered := contract.duplicate(true)
	tampered.legacy_surrogate_compatible = true
	_expect(not ModelContract.validate(tampered).success, "legacy surrogate compatibility cannot be enabled by mutation")

func _mechanical_chain(label: String, count: int) -> Dictionary:
	var parts: Array = []
	for index in range(count):
		parts.append(Part.create(
			"part/%s/%03d" % [label, index],
			"item/%s-%03d" % [label, index],
			"BEAM",
			"anchor" if index == 0 else "member",
			1.0,
			[float(index), 0.0, 0.0],
			{"physics_r2_anchor": index == 0}
		))
	var bonds: Array = []
	for index in range(count - 1):
		bonds.append(Bond.create(
			"bond/%s/%03d" % [label, index],
			"part/%s/%03d" % [label, index],
			"part/%s/%03d" % [label, index + 1],
			"AXIAL_SPRING",
			100.0,
			"INTACT",
			{"area_m2": 0.001, "damping_ns_per_m": 5.0}
		))
	return Snapshot.create("construct/%s" % label, "item/%s-root" % label, 0, "OPERATIONAL", parts, bonds, {})

func _electrical_pair(label: String) -> Dictionary:
	var parts: Array = [
		Part.create("part/%s/a" % label, "item/%s-a" % label, "CONDUCTOR", "terminal", 1.0, [0.0, 0.0, 0.0]),
		Part.create("part/%s/b" % label, "item/%s-b" % label, "CONDUCTOR", "terminal", 1.0, [1.0, 0.0, 0.0]),
	]
	var bonds: Array = [
		Bond.create(
			"bond/%s/a" % label,
			"part/%s/a" % label,
			"part/%s/b" % label,
			"ELECTRICAL_RESISTOR",
			100.0,
			"INTACT",
			{"area_m2": 1.0e-6}
		),
	]
	return Snapshot.create("construct/%s" % label, "item/%s-root" % label, 0, "OPERATIONAL", parts, bonds, {})

func _matter(label: String, mass_kg: float, material_id: String) -> Dictionary:
	return Batch.create({
		"batch_id": "batch/%s" % label,
		"container_id": "container/%s" % label,
		"source_body_id": "body/%s" % label,
		"source_operation_id": "operation/%s" % label,
		"total_mass_kg": mass_kg,
		"bulk_volume_m3": mass_kg * 1.0e-3,
		"composition": Composition.create([{"material_id": material_id, "mass_fraction": 1.0}]),
		"temperature_k": MaterialLaw.REFERENCE_TEMPERATURE_K,
	})

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
