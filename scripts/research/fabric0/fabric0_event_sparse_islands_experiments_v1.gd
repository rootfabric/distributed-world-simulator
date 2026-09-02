class_name Fabric0EventSparseIslandsExperimentsV1
extends RefCounted

const Fabric = preload("res://scripts/research/fabric0/fabric0_event_sparse_islands_v1.gd")

static func floor_planes() -> Array:
	return [Fabric.new_plane("floor", Vector3.UP, 0.0, 0.7, 0.0)]

static func build_resting_stack(reverse_insertion: bool = false) -> Dictionary:
	var world := Fabric.new_world(Vector3(0.0, -9.81, 0.0))
	var bodies := [
		Fabric.new_sphere_body("A", 1.0, 0.5, Vector3(0.0, 0.5, 0.0), Vector3.ZERO, Vector3.ZERO, 0.7, 0.0),
		Fabric.new_sphere_body("B", 1.0, 0.5, Vector3(0.0, 1.5, 0.0), Vector3.ZERO, Vector3.ZERO, 0.7, 0.0),
	]
	if reverse_insertion:
		bodies.reverse()
	for body in bodies:
		assert(Fabric.add_body(world, body))
	return world

static func warm_stack(world: Dictionary, reverse_contacts: bool = false, reverse_schedule: bool = false) -> Array:
	var results: Array = []
	for _step in range(4):
		var compiled := Fabric.compile_contacts(world, floor_planes(), 1.0e-6)
		assert(bool(compiled["ok"]))
		var contacts: Array = compiled["contacts"].duplicate(true)
		if reverse_contacts:
			contacts.reverse()
		var result := Fabric.step_sparse(world, contacts, 0.01, {
			"rho":0.2,
			"tolerance":1.0e-9,
			"pcg_tolerance":1.0e-12,
			"reverse_island_schedule":reverse_schedule,
		})
		assert(bool(result["ok"]))
		results.append(result)
	return results

static func add_incoming_body(world: Dictionary) -> void:
	assert(Fabric.add_body(world, Fabric.new_sphere_body(
		"C", 1.0, 0.5,
		Vector3(0.0, 3.5, 0.0),
		Vector3(0.0, -1.0, 0.0),
		Vector3.ZERO,
		0.7, 0.0
	)))

static func run_impact_sequence(reverse_insertion: bool = false, reverse_contacts: bool = false, reverse_schedule: bool = false) -> Dictionary:
	var world := build_resting_stack(reverse_insertion)
	var warm_results := warm_stack(world, reverse_contacts, reverse_schedule)
	add_incoming_body(world)
	var before_event_hash := Fabric.world_hash(world)
	var result := Fabric.advance_event_localized(world, floor_planes(), 0.6, {
		"rho":0.2,
		"tolerance":1.0e-9,
		"pcg_tolerance":1.0e-12,
		"pcg_max_iterations":128,
		"max_substep":0.01,
		"contact_tolerance":1.0e-7,
		"impact_reference_dt":0.01,
		"reverse_island_schedule":reverse_schedule,
	})
	assert(bool(result["ok"]))
	return {
		"world":world,
		"warm_results":warm_results,
		"event":result,
		"before_event_hash":before_event_hash,
		"hash":Fabric.world_hash(world),
	}

static func build_two_independent_stacks(reverse_insertion: bool = false) -> Dictionary:
	var world := Fabric.new_world(Vector3(0.0, -9.81, 0.0))
	var bodies := [
		Fabric.new_sphere_body("A",1.0,0.5,Vector3(0.0,0.5,0.0),Vector3.ZERO,Vector3.ZERO,0.7,0.0),
		Fabric.new_sphere_body("B",1.0,0.5,Vector3(0.0,1.5,0.0),Vector3.ZERO,Vector3.ZERO,0.7,0.0),
		Fabric.new_sphere_body("D",1.0,0.5,Vector3(4.0,0.5,0.0),Vector3.ZERO,Vector3.ZERO,0.7,0.0),
		Fabric.new_sphere_body("E",1.0,0.5,Vector3(4.0,1.5,0.0),Vector3.ZERO,Vector3.ZERO,0.7,0.0),
	]
	if reverse_insertion:
		bodies.reverse()
	for body in bodies:
		assert(Fabric.add_body(world,body))
	return world

static func solve_two_stacks(reverse_insertion: bool = false, reverse_contacts: bool = false, reverse_schedule: bool = false) -> Dictionary:
	var world := build_two_independent_stacks(reverse_insertion)
	var compiled := Fabric.compile_contacts(world, floor_planes(), 1.0e-6)
	assert(bool(compiled["ok"]))
	var contacts: Array = compiled["contacts"].duplicate(true)
	if reverse_contacts:
		contacts.reverse()
	var result := Fabric.step_sparse(world, contacts, 0.01, {
		"rho":0.2,
		"tolerance":1.0e-9,
		"pcg_tolerance":1.0e-12,
		"reverse_island_schedule":reverse_schedule,
	})
	assert(bool(result["ok"]))
	return {"world":world,"result":result,"hash":Fabric.world_hash(world)}
