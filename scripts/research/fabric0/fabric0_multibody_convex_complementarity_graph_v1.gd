class_name Fabric0MultibodyConvexComplementarityGraphV1
extends RefCounted
const Model=preload("res://scripts/research/fabric0/fabric0_multibody_convex_model_v1.gd")
const Driver=preload("res://scripts/research/fabric0/fabric0_multibody_driver_v1.gd")
const Solver=preload("res://scripts/research/fabric0/fabric0_multibody_complementarity_v1.gd")
static func new_world()->Dictionary:return Model.new_world()
static func advance(world:Dictionary,duration:float,options:Dictionary={})->Dictionary:return Driver.advance(world,duration,options)
static func world_hash(world:Dictionary)->String:return Model.graph_hash(world)
static func components(world:Dictionary)->Array:return Model.dynamic_components(world,Model.discover_contacts(world))
static func parallel_island_audit(world:Dictionary,reverse_spawn:bool=false)->Dictionary:return Driver.parallel_island_audit(world,reverse_spawn)
static func energy_ledger_residual(world:Dictionary)->float:return Driver.energy_ledger_residual(world)
static func solve_contacts(world:Dictionary,contacts:Array,dt:float,reverse_order:bool=false)->Dictionary:return Solver.solve(world,contacts,dt,reverse_order)
static func discover_contacts(world:Dictionary)->Array:return Model.discover_contacts(world)
