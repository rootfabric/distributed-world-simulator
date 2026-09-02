class_name Fabric0PersistentContactGraphExperimentsV1
extends RefCounted

const Fabric = preload("res://scripts/research/fabric0/fabric0_persistent_contact_graph_v1.gd")

static func build_world(reverse_insertion: bool = false) -> Dictionary:
	var world := Fabric.new_world(Vector3(0.0, -9.81, 0.0))
	var bodies := [
		Fabric.new_sphere_body("A", 1.0, 0.5, Vector3(0.0, 0.5, 0.0), Vector3.ZERO, Vector3.ZERO, 0.6, 0.0),
		Fabric.new_sphere_body("B", 1.0, 0.5, Vector3(0.0, 1.5, 0.0), Vector3.ZERO, Vector3.ZERO, 0.6, 0.0),
		Fabric.new_sphere_body("D", 1.0, 0.5, Vector3(4.0, 0.5, 0.0), Vector3.ZERO, Vector3.ZERO, 0.6, 0.0),
		Fabric.new_sphere_body("E", 1.0, 0.5, Vector3(6.0, 0.5, 0.0), Vector3.ZERO, Vector3.ZERO, 0.6, 0.0),
	]
	if reverse_insertion:
		bodies.reverse()
	for body in bodies:
		assert(Fabric.add_body(world, body))
	return world

static func floor_planes() -> Array:
	return [Fabric.new_plane("floor", Vector3.UP, 0.0, 0.6, 0.0)]

static func compile_contacts(world: Dictionary, reverse_output: bool = false) -> Array:
	var compiled := Fabric.compile_sphere_contacts(world, floor_planes(), 1.0e-6)
	assert(bool(compiled["ok"]))
	var contacts: Array = compiled["contacts"].duplicate(true)
	if reverse_output:
		contacts.reverse()
	return contacts

static func merge_d_e(world: Dictionary) -> void:
	world["bodies"]["E"]["position"] = Vector3(5.0, 0.5, 0.0)
	world["bodies"]["E"]["linear_velocity"] = Vector3.ZERO
	world["bodies"]["E"]["angular_velocity"] = Vector3.ZERO

static func split_d_e(world: Dictionary) -> void:
	world["bodies"]["E"]["position"] = Vector3(7.0, 0.5, 0.0)
	world["bodies"]["E"]["linear_velocity"] = Vector3.ZERO
	world["bodies"]["E"]["angular_velocity"] = Vector3.ZERO

static func run_sequence(reverse_insertion: bool = false, reverse_contacts: bool = false) -> Dictionary:
	var world := build_world(reverse_insertion)
	var results: Array = []
	for phase in range(5):
		if phase == 2:
			merge_d_e(world)
		if phase == 4:
			split_d_e(world)
		var contacts := compile_contacts(world, reverse_contacts)
		var result := Fabric.step(world, contacts, 0.01, {"rho":0.2,"tolerance":1.0e-9,"max_iterations":10000})
		assert(bool(result["ok"]))
		results.append(result)
	return {"world":world,"results":results,"hash":Fabric.world_hash(world)}
