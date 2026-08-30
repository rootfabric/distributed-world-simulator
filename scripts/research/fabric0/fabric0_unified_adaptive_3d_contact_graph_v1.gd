class_name Fabric0UnifiedAdaptive3DContactGraphV1
extends RefCounted

const Model = preload("res://scripts/research/fabric0/fabric0_unified_adaptive_3d_model_v1.gd")
const Driver = preload("res://scripts/research/fabric0/fabric0_unified_adaptive_3d_driver_v1.gd")
const Sparse = preload("res://scripts/research/fabric0/fabric0_unified_adaptive_3d_sparse_v1.gd")

static func new_world() -> Dictionary: return Model.new_world()
static func advance_adaptive(world: Dictionary, duration: float, options: Dictionary = {}) -> Dictionary: return Driver.advance_adaptive(world,duration,options)
static func current_contact_ids(world: Dictionary) -> Array: return Model.current_contact_ids(world)
static func free_support_gap(world: Dictionary, state: Array) -> float: return Model.free_support_gap(world,state)
static func quaternion_audit(world: Dictionary) -> Dictionary: return Model.quaternion_audit(world)
static func world_hash(world: Dictionary) -> String: return Model.world_hash(world)
static func parallel_island_snapshot(world: Dictionary, reverse_spawn: bool = false) -> Dictionary: return Driver.parallel_island_snapshot(world,reverse_spawn)
static func new_sleep_tracker() -> Dictionary: return Driver.new_sleep_tracker()
static func update_sleep(tracker: Dictionary, id: String, speed: float, residual: float, quiet_required: int=3) -> Dictionary: return Driver.update_sleep(tracker,id,speed,residual,quiet_required)
static func _prepare_pattern(cache: Dictionary, island: String, matrix: Array, mutate: bool) -> Dictionary: return Sparse._prepare_pattern(cache,island,matrix,mutate)
