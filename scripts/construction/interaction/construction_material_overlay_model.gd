extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const Build=preload("res://scripts/construction/build/construction_build_plan.gd")
const Repair=preload("res://scripts/construction/damage/construction_repair_ghost_state.gd")
const SCHEMA="planet_simulator.construction_material_overlay.v1"
const FIELDS:Array[String]=["schema","context_kind","context_id","requirements","ready","summary","checksum"]
static func from_build_plan(plan:Dictionary,available_item_ids:Array)->Dictionary:
 var e=Build.validate(plan);if not e.success:return e
 var available={};for i in available_item_ids:available[String(i)]=true
 var reqs=[]
 for stage in plan.stages:
  for a in stage.material_allocations:reqs.append({"item_instance_id":String(a.item_instance_id),"definition_id":String(a.definition_id),"required_quantity":int(a.quantity),"available":available.has(String(a.item_instance_id)),"stage_id":String(stage.stage_id)})
 return _make("BUILD",String(plan.build_plan_id),reqs)
static func from_repair_ghost(ghost:Dictionary)->Dictionary:
 var e=Repair.validate(ghost);if not e.success:return e
 var reqs=[];for s in ghost.part_states:reqs.append({"item_instance_id":String(s.item_instance_id),"definition_id":"","required_quantity":1,"available":String(s.status)=="AVAILABLE","stage_id":""})
 return _make("REPAIR",String(ghost.repair_id),reqs)
static func _make(kind,id,reqs):
 reqs.sort_custom(func(a,b):return String(a.item_instance_id)<String(b.item_instance_id));var missing=0;for r in reqs:if not r.available:missing+=1
 var v={"schema":SCHEMA,"context_kind":kind,"context_id":id,"requirements":reqs,"ready":missing==0,"summary":{"required_count":reqs.size(),"missing_count":missing},"checksum":""};v.checksum=compute_checksum(v);return {"success":true,"overlay":v}
static func validate(v:Dictionary)->Dictionary:
 var e=Utils.validate_exact_fields(v,FIELDS);if not e.success:return e
 if v.schema!=SCHEMA or v.context_kind not in ["BUILD","REPAIR"] or typeof(v.requirements)!=TYPE_ARRAY:return _f("INVALID_CONSTRUCTION_MATERIAL_OVERLAY")
 var missing=0;var prev=""
 for r in v.requirements:
  if typeof(r)!=TYPE_DICTIONARY or r.keys().size()!=5:return _f("INVALID_CONSTRUCTION_MATERIAL_OVERLAY_REQUIREMENT")
  if String(r.item_instance_id)<prev or typeof(r.available)!=TYPE_BOOL or int(r.required_quantity)<1:return _f("INVALID_CONSTRUCTION_MATERIAL_OVERLAY_REQUIREMENT")
  if not r.available:missing+=1
  prev=String(r.item_instance_id)
 if bool(v.ready)!=(missing==0) or int(v.summary.missing_count)!=missing or int(v.summary.required_count)!=v.requirements.size():return _f("CONSTRUCTION_MATERIAL_OVERLAY_SUMMARY_MISMATCH")
 if v.checksum!=compute_checksum(v):return _f("CONSTRUCTION_MATERIAL_OVERLAY_CHECKSUM_MISMATCH")
 return Utils.validation_success()
static func compute_checksum(v):var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
static func _f(c):return Utils.validation_failure(c,c)
