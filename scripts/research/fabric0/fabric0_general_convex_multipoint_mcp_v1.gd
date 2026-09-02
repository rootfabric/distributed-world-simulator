class_name Fabric0GeneralConvexMultipointMcpV1
extends RefCounted

const Model = preload("res://scripts/research/fabric0/fabric0_general_convex_model_v1.gd")
const Collision = preload("res://scripts/research/fabric0/fabric0_gjk_epa_v1.gd")
const Manifold = preload("res://scripts/research/fabric0/fabric0_persistent_multipoint_manifold_v1.gd")
const Solver = preload("res://scripts/research/fabric0/fabric0_graph_mcp_v1.gd")

static func box_shape(id:String, half:Vector3) -> Dictionary:
	return Model.box_shape(id, half)

static func tetra_shape(id:String, scale:float=1.0) -> Dictionary:
	return Model.tetra_shape(id, scale)

static func new_body(
	id:String,
	shape:Dictionary,
	position:Vector3,
	orientation:Quaternion=Quaternion.IDENTITY,
	mass:float=1.0,
	inertia:Vector3=Vector3(0.2,0.25,0.3),
	linear_velocity:Vector3=Vector3.ZERO,
	angular_velocity:Vector3=Vector3.ZERO
) -> Dictionary:
	return Model.new_body(id, shape, position, orientation, mass, inertia, linear_velocity, angular_velocity)

static func support(body:Dictionary, direction:Vector3) -> Dictionary:
	return Model.support(body, direction)

static func broadphase_pairs(bodies:Array) -> Array:
	return Model.broadphase_pairs(bodies)

static func collide(a:Dictionary, b:Dictionary) -> Dictionary:
	return Collision.penetration(a, b)

static func build_manifold(
	a:Dictionary,
	b:Dictionary,
	collision:Dictionary,
	old_manifold:Dictionary={},
	max_points:int=4
) -> Dictionary:
	return Manifold.build(a, b, collision, old_manifold, max_points)

static func solve_contacts(bodies:Array, contacts:Array, dt:float, options:Dictionary={}) -> Dictionary:
	return Solver.solve(bodies, contacts, dt, options)

static func total_linear_momentum(bodies:Array) -> Vector3:
	return Model.total_linear_momentum(bodies)

static func total_angular_momentum_origin(bodies:Array) -> Vector3:
	return Model.total_angular_momentum_origin(bodies)

static func total_kinetic_energy(bodies:Array) -> float:
	return Model.total_kinetic_energy(bodies)
