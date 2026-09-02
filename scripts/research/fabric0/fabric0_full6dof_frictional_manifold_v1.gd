class_name Fabric0Full6DOFFrictionalManifoldV1
extends RefCounted
const Model=preload("res://scripts/research/fabric0/fabric0_full6dof_model_v1.gd")
const Contact=preload("res://scripts/research/fabric0/fabric0_full6dof_contact_v1.gd")
const Driver=preload("res://scripts/research/fabric0/fabric0_full6dof_driver_v1.gd")
static func new_world()->Dictionary:return Model.new_world()
static func advance(world:Dictionary,duration:float,options:Dictionary={})->Dictionary:return Driver.advance(world,duration,options)
static func world_hash(world:Dictionary)->String:return Model.world_hash(world)
static func support_feature_from_orientation(world:Dictionary,q:Quaternion,tol:float=1e-10)->Dictionary:return Model.support_feature_from_orientation(world,q,tol)
static func force_probe(world:Dictionary,s:Array,mode:String="slide")->Dictionary:return Model.force_probe(world,s,mode)
static func parallel_contact_audit(world:Dictionary,reverse_spawn:bool=false)->Dictionary:return Driver.parallel_contact_audit(world,reverse_spawn)
static func lineage_remap(old_feature:Dictionary,value,new_feature:Dictionary):return Model.lineage_remap(old_feature,value,new_feature)
static func ContactAPI():return Contact
