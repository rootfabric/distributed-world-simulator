class_name Fabric0MultiContactConeExperimentsV1
extends RefCounted

const Fabric = preload("res://scripts/research/fabric0/fabric0_multicontact_cone_v1.gd")

static func build_corner_body() -> Dictionary:
	return Fabric.new_box_body(
		"box",
		2.0,
		Vector3(0.5, 1.2, 0.8),
		Vector3(0.5, 0.5, 0.0),
		Vector3(-2.0, -3.0, 1.0),
		Vector3(0.4, 0.2, -0.6),
		Vector3(0.5, 0.5, 0.75),
		Basis.IDENTITY
	)

static func build_corner_planes() -> Array:
	return [
		Fabric.new_plane("floor", Vector3(0.0, 1.0, 0.0), 0.0, 0.25, 0.2),
		Fabric.new_plane("wall", Vector3(1.0, 0.0, 0.0), 0.0, 0.25, 0.2),
	]

static func compile_corner_manifold(reverse_planes: bool = false) -> Dictionary:
	var planes := build_corner_planes()
	if reverse_planes:
		planes.reverse()
	return Fabric.compile_box_plane_manifold(build_corner_body(), planes, 1.0e-9)

static func solve_corner(reverse_contacts: bool = false, reverse_planes: bool = false) -> Dictionary:
	var manifold := compile_corner_manifold(reverse_planes)
	assert(bool(manifold["ok"]))
	var contacts: Array = manifold["contacts"].duplicate(true)
	if reverse_contacts:
		contacts.reverse()
	return Fabric.solve_impact(build_corner_body(), contacts, {
		"rho": 0.1,
		"tolerance": 1.0e-9,
		"max_iterations": 12000,
	})
