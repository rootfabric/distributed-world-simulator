extends RefCounted

const C = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_compiler_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Bond = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const Batch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")

# Fixture data only. No time, solver, failure target or scripted break sequence.
static func create(options: Dictionary = {}) -> Dictionary:
	var label: String = options.get("label", "mechanism")
	var basis: Basis = options.get("basis", Basis.IDENTITY)
	var origin: Vector3 = options.get("origin", Vector3.ZERO)
	var spring_k: Array = options.get("spring_k", [20.0, 30.0])
	var damping: Array = options.get("damping", [0.5, 1.0])
	var capacity: Array = options.get("capacity", [2.0, 1000.0])
	var mass: float = options.get("mass_kg", 2.0)
	var position := origin + basis * Vector3(1.0, 0.0, 0.0)
	var slider := "part/%s-slider" % label
	var parts: Array = [Part.create(slider, "item/%s-slider" % label, "BEAM", "slider", mass, _array(position), {"physics_r2_anchor": false})]
	var bonds: Array = []
	for i in range(spring_k.size()):
		var anchor := "part/%s-anchor-%02d" % [label, i]
		parts.append(Part.create(anchor, "item/%s-anchor-%02d" % [label, i], "BEAM", "anchor", 1.0, _array(origin), {"physics_r2_anchor": true}))
		bonds.append(Bond.create("bond/%s-support-%02d" % [label, i], anchor, slider, "AXIAL_SPRING", capacity[i], "INTACT", {"area_m2": float(spring_k[i]) / 1.0e6, "damping_ns_per_m": damping[i]}))
	var controls := {"composition_r3": {"source_voltage_v": options.get("voltage_v", 12.0), "external_force_n": options.get("force_n", 0.0), "coupling_n_per_a": options.get("coupling", 2.0), "guard_fraction": 0.8}}
	var mechanical := Snapshot.create("construct/%s-mechanical" % label, "item/%s-mechanical" % label, 1, "OPERATIONAL", parts, bonds, controls)
	parts = []
	bonds = []
	for i in range(3):
		parts.append(Part.create("part/%s-electric-%02d" % [label, i], "item/%s-electric-%02d" % [label, i], "BEAM", "terminal", 1.0, _array(origin + basis * Vector3(float(i), 2.0, 0.0))))
	for i in range(2):
		var resistance: float = options.get("source_resistance_ohm", 1.0) if i == 0 else options.get("load_resistance_ohm", 3.0)
		bonds.append(Bond.create("bond/%s-electric-%02d" % [label, i], parts[i].part_id, parts[i + 1].part_id, "ELECTRICAL_RESISTOR", 100.0, "INTACT", {"area_m2": 1.68e-8 / resistance, "composition_r3_role": "SOURCE_RESISTANCE" if i == 0 else "LOAD_RESISTANCE"}))
	var electrical := Snapshot.create("construct/%s-electrical" % label, "item/%s-electrical" % label, 1, "OPERATIONAL", parts, bonds, {})
	return {"mechanical": mechanical, "electrical": electrical, "mechanical_matter": _matter(label + "-mechanical", mass + spring_k.size(), "material/rubber"), "electrical_matter": _matter(label + "-electrical", 3.0, "material/copper")}

static func authority(sources: Dictionary, owner: String = "server/r3", epoch: int = 1) -> Dictionary:
	var records: Array = []
	var mutable: Array = []
	var readonly: Array = []
	for key in ["mechanical", "electrical"]:
		var id: String = sources[key].construct_id
		records.append({"source_domain": "CONSTRUCTION", "source_id": id, "authority_epoch": epoch, "owner_id": owner})
		mutable.append(C.U.source_key("CONSTRUCTION", id))
		id = sources[key + "_matter"].batch_id
		records.append({"source_domain": "MATTER", "source_id": id, "authority_epoch": epoch, "owner_id": owner})
		readonly.append(C.U.source_key("MATTER", id))
	return C.A.create(owner, records, mutable, readonly)

static func _matter(label: String, mass: float, material: String) -> Dictionary:
	return Batch.create({"batch_id": "batch/" + label, "container_id": "container/" + label, "source_body_id": "body/" + label, "source_operation_id": "operation/" + label, "total_mass_kg": mass, "bulk_volume_m3": mass * 0.001, "composition": Composition.create([{"material_id": material, "mass_fraction": 1.0}]), "temperature_k": 293.15})

static func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
