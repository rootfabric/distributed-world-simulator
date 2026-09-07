extends SceneTree

const Compiler = preload("res://scripts/research/fabric_bake0/fabric_physics_r2_compiler_v1.gd")
const MaterialLaw = preload("res://scripts/research/fabric_bake0/fabric_physics_r2_material_law_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Bond = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const Batch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")

const REL_TOL := 1.0e-10
const ABS_TOL := 1.0e-12

var _failures: Array[String] = []

func _initialize() -> void:
	_test_mechanical_rigid_transform_and_id_permutation()
	_test_electrical_rigid_transform_and_id_permutation()

	if not _failures.is_empty():
		print("FABRIC_PHYSICS_R2_METAMORPHIC_FAILURES=", JSON.stringify(_failures))
		print("FABRIC-PHYSICS-R2-METAMORPHIC: FAIL")
		quit(1)
		return
	print("FABRIC-PHYSICS-R2-METAMORPHIC: PASS")
	quit(0)

func _test_mechanical_rigid_transform_and_id_permutation() -> void:
	var base_positions := [
		[0.0, 0.0, 0.0],
		[1.0, 0.0, 0.0],
		[2.0, 0.0, 0.0],
	]
	# 90 degree rotation around Z followed by a global translation.
	var transformed_positions := [
		[7.0, -3.0, 11.0],
		[7.0, -2.0, 11.0],
		[7.0, -1.0, 11.0],
	]
	var base_ids := ["part/mech-base/a", "part/mech-base/b", "part/mech-base/c"]
	# The physical positions/topology are unchanged while canonical names are permuted.
	var permuted_ids := ["part/mech-permuted/z", "part/mech-permuted/x", "part/mech-permuted/y"]

	var base := Compiler.compile_mechanical(
		_mechanical_snapshot("mech-base", base_ids, base_positions),
		_matter("mech-base", 3.0, "material/steel")
	)
	var transformed := Compiler.compile_mechanical(
		_mechanical_snapshot("mech-rigid-transform", base_ids, transformed_positions),
		_matter("mech-rigid-transform", 3.0, "material/steel")
	)
	var permuted := Compiler.compile_mechanical(
		_mechanical_snapshot("mech-id-permutation", permuted_ids, base_positions),
		_matter("mech-id-permutation", 3.0, "material/steel")
	)

	_expect(_all_success([base, transformed, permuted]), "mechanical metamorphic fixtures compile")
	if not _all_success([base, transformed, permuted]):
		return
	var base_signature := _mechanical_signature(base.details.model)
	_expect(_float_arrays_near(base_signature, _mechanical_signature(transformed.details.model)), "mechanical global rigid rotation+translation preserves observables")
	_expect(_float_arrays_near(base_signature, _mechanical_signature(permuted.details.model)), "mechanical canonical ID permutation preserves observables")

func _test_electrical_rigid_transform_and_id_permutation() -> void:
	var base_positions := [
		[0.0, 0.0, 0.0],
		[0.0, 2.0, 0.0],
		[0.0, 5.0, 0.0],
	]
	# -90 degree rotation around Z followed by a global translation.
	var transformed_positions := [
		[-4.0, 6.0, 2.0],
		[-2.0, 6.0, 2.0],
		[1.0, 6.0, 2.0],
	]
	var base_ids := ["part/elec-base/a", "part/elec-base/b", "part/elec-base/c"]
	var permuted_ids := ["part/elec-permuted/m", "part/elec-permuted/k", "part/elec-permuted/q"]

	var base := Compiler.compile_electrical(
		_electrical_snapshot("elec-base", base_ids, base_positions),
		_matter("elec-base", 3.0, "material/copper")
	)
	var transformed := Compiler.compile_electrical(
		_electrical_snapshot("elec-rigid-transform", base_ids, transformed_positions),
		_matter("elec-rigid-transform", 3.0, "material/copper")
	)
	var permuted := Compiler.compile_electrical(
		_electrical_snapshot("elec-id-permutation", permuted_ids, base_positions),
		_matter("elec-id-permutation", 3.0, "material/copper")
	)

	_expect(_all_success([base, transformed, permuted]), "electrical metamorphic fixtures compile")
	if not _all_success([base, transformed, permuted]):
		return
	var base_signature := _electrical_signature(base.details.model)
	_expect(_float_arrays_near(base_signature, _electrical_signature(transformed.details.model)), "electrical global rigid rotation+translation preserves observables")
	_expect(_float_arrays_near(base_signature, _electrical_signature(permuted.details.model)), "electrical canonical ID permutation preserves observables")

func _mechanical_snapshot(label: String, ids: Array, positions: Array) -> Dictionary:
	var parts: Array = []
	for index in range(ids.size()):
		parts.append(Part.create(
			String(ids[index]),
			"item/%s/%03d" % [label, index],
			"BEAM",
			"anchor" if index == 0 else "member",
			1.0,
			Array(positions[index]).duplicate(),
			{"physics_r2_anchor": index == 0}
		))
	var bonds: Array = []
	for index in range(ids.size() - 1):
		bonds.append(Bond.create(
			"bond/%s/%03d" % [label, index],
			String(ids[index]),
			String(ids[index + 1]),
			"AXIAL_SPRING",
			100.0 + 10.0 * float(index),
			"INTACT",
			{"area_m2": 0.001 + 0.0002 * float(index), "damping_ns_per_m": 3.0 + float(index)}
		))
	return Snapshot.create("construct/%s" % label, "item/%s/root" % label, 0, "OPERATIONAL", parts, bonds, {})

func _electrical_snapshot(label: String, ids: Array, positions: Array) -> Dictionary:
	var parts: Array = []
	for index in range(ids.size()):
		parts.append(Part.create(
			String(ids[index]),
			"item/%s/%03d" % [label, index],
			"CONDUCTOR",
			"terminal" if index == 0 or index == ids.size() - 1 else "junction",
			1.0,
			Array(positions[index]).duplicate()
		))
	var bonds: Array = []
	for index in range(ids.size() - 1):
		bonds.append(Bond.create(
			"bond/%s/%03d" % [label, index],
			String(ids[index]),
			String(ids[index + 1]),
			"ELECTRICAL_RESISTOR",
			50.0 + 25.0 * float(index),
			"INTACT",
			{"area_m2": 1.0e-6 + 0.5e-6 * float(index)}
		))
	return Snapshot.create("construct/%s" % label, "item/%s/root" % label, 0, "OPERATIONAL", parts, bonds, {})

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

func _mechanical_signature(model: Dictionary) -> Array[float]:
	var signature: Array[float] = []
	for raw_element in model.elements:
		var element: Dictionary = raw_element
		signature.append(float(element.length_m))
		signature.append(float(element.area_m2))
		signature.append(float(element.stiffness_n_per_m))
		signature.append(float(element.damping_ns_per_m))
		signature.append(float(element.capacity_n))
	return signature

func _electrical_signature(model: Dictionary) -> Array[float]:
	var signature: Array[float] = []
	for raw_element in model.elements:
		var element: Dictionary = raw_element
		signature.append(float(element.length_m))
		signature.append(float(element.area_m2))
		signature.append(float(element.resistance_ohm))
		signature.append(float(element.conductance_siemens))
	return signature

func _float_arrays_near(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if not _near(float(left[index]), float(right[index])):
			return false
	return true

func _all_success(results: Array) -> bool:
	for result in results:
		if typeof(result) != TYPE_DICTIONARY or not bool(result.get("success", false)):
			return false
	return true

func _near(left: float, right: float) -> bool:
	if not is_finite(left) or not is_finite(right):
		return false
	var scale := maxf(1.0, maxf(absf(left), absf(right)))
	return absf(left - right) <= ABS_TOL + REL_TOL * scale

func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
