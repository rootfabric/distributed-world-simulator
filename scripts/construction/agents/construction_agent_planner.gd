extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Goal=preload("res://scripts/construction/agents/construction_agent_goal.gd")
const Line=preload("res://scripts/construction/agents/construction_agent_bom_line.gd")
const Bom=preload("res://scripts/construction/agents/construction_agent_bom.gd")
const Step=preload("res://scripts/construction/agents/construction_agent_step.gd")
const Plan=preload("res://scripts/construction/agents/construction_agent_plan.gd")
const Definition=preload("res://scripts/construction/composites/construction_composite_definition.gd")
const Slot=preload("res://scripts/construction/composites/composite_part_slot.gd")
const Compiler=preload("res://scripts/construction/composites/construction_composite_build_plan_compiler.gd")
const Recipe=preload("res://scripts/construction/fabrication/construction_fabrication_recipe.gd")
const ProjectionScript=preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const RepairPlan=preload("res://scripts/construction/damage/construction_repair_plan.gd")
const DamageRequest=preload("res://scripts/construction/damage/construction_damage_request.gd")
static func compile(goal: Dictionary, definition: Dictionary, available_projections: Array, recipes: Array, options: Dictionary = {}) -> Dictionary:
 var checked := Goal.validate(goal)
 if not bool(checked.get("success", false)):
  return checked
 match String(goal.get("goal_kind", "")):
  Goal.BUILD_COMPOSITE:
   return _compile_build(goal, definition, available_projections, recipes, options)
  Goal.REPAIR_CONSTRUCT:
   return _compile_repair(goal, available_projections, options)
  Goal.SALVAGE_CONSTRUCT:
   return _compile_salvage(goal, options)
  _:
   return P.failure("INVALID_CONSTRUCTION_AGENT_GOAL_KIND")

static func _compile_build(goal:Dictionary,definition:Dictionary,available_projections:Array,recipes:Array,options:Dictionary={})->Dictionary:
 var x=Goal.validate(goal);if not bool(x.success):return x
 x=Definition.validate(definition);if not bool(x.success):return x
 if String(goal.composite_definition_id)!=String(definition.composite_definition_id) or int(goal.definition_version)!=int(definition.definition_version) or String(goal.definition_checksum)!=String(definition.checksum):return P.failure("CONSTRUCTION_AGENT_GOAL_DEFINITION_PRECONDITION_MISMATCH")
 var projections:=_projection_map(available_projections);if not bool(projections.success):return projections
 var recipe_list:Array=[]
 for recipe in recipes:
  x=Recipe.validate(recipe);if not bool(x.success):return x
  recipe_list.append(recipe.duplicate(true))
 recipe_list.sort_custom(func(a,b):return "%s|%010d"%[a.recipe_id,int(a.recipe_version)]<"%s|%010d"%[b.recipe_id,int(b.recipe_version)])
 var used:Dictionary={};var lines:Array=[];var source_projections:Array=[];var fabrication_jobs:Array=[];var goal_key=String(goal.goal_id).trim_prefix("agent-goal/").replace("/",":")
 var slot_index:=0
 for slot in definition.part_slots:
  var alloc=_allocate_available(String(slot.definition_id),1,Dictionary(slot.required_components),projections.items,used,true)
  var bindings:Array=alloc.bindings;var fabrication:Array=[];var missing=1-int(alloc.quantity)
  if missing>0:
   var selected=_select_recipe(String(slot.definition_id),Dictionary(slot.required_components),recipe_list)
   if not bool(selected.success):
    lines.append(Line.create("bom-line/%s/part-%03d"%[goal_key,slot_index],"PART_SLOT",String(slot.slot_id),String(slot.definition_id),1,Dictionary(slot.required_components),bindings,[],missing,"PROCURE" if bool(options.get("allow_procurement",true)) else "BLOCKED",0.0));slot_index+=1;continue
   var output_id="item/agent/%s/fabricated-part-%03d"%[goal_key,slot_index];var product:Dictionary=selected.product
   var output_components=Dictionary(product.components).duplicate(true);fabrication=[{"recipe_id":String(selected.recipe.recipe_id),"recipe_version":int(selected.recipe.recipe_version),"recipe_checksum":String(selected.recipe.checksum),"product_key":String(product.product_key),"output_item_id":output_id,"output_quantity":1,"input_requirements":Array(selected.recipe.input_requirements).duplicate(true)}]
   var synthetic=ProjectionScript.create(output_id,String(slot.definition_id),String(product.display_name),1,ProjectionScript.container_relation("container/agent-staging/%s"%goal_key),output_components,0);source_projections.append(synthetic);fabrication_jobs.append({"line_id":"bom-line/%s/part-%03d"%[goal_key,slot_index],"binding":fabrication[0],"recipe":selected.recipe.duplicate(true),"output_projection":synthetic.duplicate(true)})
  for binding in bindings:source_projections.append(Dictionary(binding.projection).duplicate(true))
  var mode="AVAILABLE" if missing==0 else "FABRICATE"
  var cost=0.0 if missing==0 else float(fabrication[0].input_requirements.size()+int(_recipe_by_checksum(recipe_list,String(fabrication[0].recipe_checksum)).work_units))
  lines.append(Line.create("bom-line/%s/part-%03d"%[goal_key,slot_index],"PART_SLOT",String(slot.slot_id),String(slot.definition_id),1,Dictionary(slot.required_components),bindings,fabrication,0 if missing>0 else missing,mode,cost));slot_index+=1
 var material_index:=0
 for stage in definition.stage_templates:
  for req in stage.material_requirements:
   var quantity=int(req.quantity);var alloc=_allocate_available(String(req.definition_id),quantity,{},projections.items,used,false);var bindings:Array=alloc.bindings;var missing=quantity-int(alloc.quantity);var fabrication:Array=[]
   if missing>0:
    var selected=_select_recipe(String(req.definition_id),{},recipe_list)
    if bool(selected.success):
     var output_id="item/agent/%s/fabricated-material-%03d"%[goal_key,material_index];var product:Dictionary=selected.product;var output_quantity=maxi(missing,int(product.quantity));fabrication=[{"recipe_id":String(selected.recipe.recipe_id),"recipe_version":int(selected.recipe.recipe_version),"recipe_checksum":String(selected.recipe.checksum),"product_key":String(product.product_key),"output_item_id":output_id,"output_quantity":output_quantity,"input_requirements":Array(selected.recipe.input_requirements).duplicate(true)}];var synthetic=ProjectionScript.create(output_id,String(req.definition_id),String(product.display_name),output_quantity,ProjectionScript.container_relation("container/agent-staging/%s"%goal_key),Dictionary(product.components),0);source_projections.append(synthetic);fabrication_jobs.append({"line_id":"bom-line/%s/material-%03d"%[goal_key,material_index],"binding":fabrication[0],"recipe":selected.recipe.duplicate(true),"output_projection":synthetic.duplicate(true)});missing=0
   for binding in bindings:source_projections.append(Dictionary(binding.projection).duplicate(true))
   var mode="AVAILABLE" if fabrication.is_empty() and missing==0 else ("FABRICATE" if not fabrication.is_empty() else ("PROCURE" if bool(options.get("allow_procurement",true)) else "BLOCKED"))
   var fabricated_total:=0;for f in fabrication:fabricated_total+=int(f.output_quantity)
   lines.append(Line.create("bom-line/%s/material-%03d"%[goal_key,material_index],"MATERIAL","%s|%s"%[stage.stage_template_id,req.definition_id],String(req.definition_id),quantity,{},bindings,fabrication,missing,mode,float(fabrication.size())));material_index+=1
 var bom=Bom.create("agent-bom/%s"%goal_key,goal,lines);x=Bom.validate(bom);if not bool(x.success):return x
 if float(goal.budget_limit)>0.0 and float(bom.total_estimated_cost)>float(goal.budget_limit):return P.failure("CONSTRUCTION_AGENT_GOAL_BUDGET_EXCEEDED",{"estimated_cost":float(bom.total_estimated_cost)})
 if not bool(bom.ready_for_execution):
  var blocked=Plan.create("agent-plan/%s"%goal_key,goal,bom,{}, {}, []);return P.success({"bom":bom,"plan":blocked,"blocked":true})
 source_projections=_dedupe_projections(source_projections)
 var compiled=Compiler.compile(definition,"composite-instantiation/agent/%s"%goal_key,"build-plan/agent/%s"%goal_key,String(goal.target_construct_id),String(goal.root_item_instance_id),Dictionary(goal.placement_relation),source_projections,Dictionary(goal.parameter_values));if not bool(compiled.success):return compiled
 var steps:Array=[];var previous:Array=[];var index:=0
 var requests:Array=[]
 for line in bom.lines:
  for binding in line.available_bindings:requests.append({"resource_kind":"ITEM","resource_id":String(binding.item_instance_id),"quantity":float(binding.quantity),"exclusive":true})
 for job in fabrication_jobs:
  for req in job.recipe.input_requirements:requests.append({"resource_kind":"ITEM","resource_id":"definition-stock/%s"%String(req.definition_id),"quantity":float(req.quantity),"exclusive":false})
 for tool in goal.required_tool_ids:requests.append({"resource_kind":"TOOL","resource_id":String(tool),"quantity":1.0,"exclusive":true})
 for workspace in goal.workspace_ids:requests.append({"resource_kind":"WORKSPACE","resource_id":String(workspace),"quantity":1.0,"exclusive":true})
 if float(goal.budget_limit)>0.0:requests.append({"resource_kind":"BUDGET","resource_id":"budget/%s"%String(goal.agent_id).trim_prefix("agent/"),"quantity":float(bom.total_estimated_cost),"exclusive":false})
 requests=_canonical_resource_requests(requests)
 var step_id="agent-step/%s/%03d-reserve"%[goal_key,index];steps.append(Step.create(step_id,index,Step.RESERVE,previous,{"requests":requests,"lease_ticks":100},"operation/agent/%s/reserve"%goal_key,Array(goal.required_agent_capabilities),Array(goal.required_tool_ids),Array(goal.workspace_ids)));previous=[step_id];index+=1
 var fab_index:=0
 for job in fabrication_jobs:
  step_id="agent-step/%s/%03d-fabricate"%[goal_key,index];steps.append(Step.create(step_id,index,Step.FABRICATE,previous,{"recipe":job.recipe,"output_projection":job.output_projection,"binding":job.binding,"machine_construct_ids":Array(options.get("machine_construct_ids",[]))},"operation/agent/%s/fabricate-%03d"%[goal_key,fab_index],["OPERATE_FABRICATION_CELL"],Array(goal.required_tool_ids),Array(goal.workspace_ids),float(job.recipe.work_units)));previous=[step_id];index+=1;fab_index+=1
 step_id="agent-step/%s/%03d-deliver"%[goal_key,index];steps.append(Step.create(step_id,index,Step.DELIVER,previous,{"item_instance_ids":_build_source_ids(compiled.build_plan),"target_relation":Dictionary(goal.placement_relation)},"operation/agent/%s/deliver"%goal_key,Array(goal.required_agent_capabilities),Array(goal.required_tool_ids),Array(goal.workspace_ids)));previous=[step_id];index+=1
 step_id="agent-step/%s/%03d-register"%[goal_key,index];steps.append(Step.create(step_id,index,Step.REGISTER,previous,{"build_plan":compiled.build_plan,"instantiation":compiled.instantiation},"operation/agent/%s/register"%goal_key,Array(goal.required_agent_capabilities)));previous=[step_id];index+=1
 for stage in compiled.build_plan.stages:
  step_id="agent-step/%s/%03d-build"%[goal_key,index];steps.append(Step.create(step_id,index,Step.BUILD,previous,{"build_plan_id":String(compiled.build_plan.build_plan_id),"stage_index":int(stage.sequence_index),"command_sequence_offset":int(stage.sequence_index),"expected_construct_checksum":"","options":{}},"operation/agent/%s/build-%03d"%[goal_key,int(stage.sequence_index)],Array(stage.required_capabilities),Array(goal.required_tool_ids),Array(goal.workspace_ids)));previous=[step_id];index+=1
 step_id="agent-step/%s/%03d-verify"%[goal_key,index];steps.append(Step.create(step_id,index,Step.VERIFY,previous,{"construct_id":String(goal.target_construct_id),"required_outcomes":Array(goal.required_outcomes)},"operation/agent/%s/verify"%goal_key,Array(goal.required_agent_capabilities)));var plan=Plan.create("agent-plan/%s"%goal_key,goal,bom,compiled.build_plan,compiled.instantiation,steps);x=Plan.validate(plan);if not bool(x.success):return x
 return P.success({"bom":bom,"plan":plan,"blocked":false})
static func _compile_repair(goal: Dictionary, available_projections: Array, options: Dictionary) -> Dictionary:
 if typeof(options.get("repair_plan")) != TYPE_DICTIONARY:
  return P.failure("CONSTRUCTION_AGENT_REPAIR_PLAN_REQUIRED")
 var repair_plan: Dictionary = options["repair_plan"]
 var checked := RepairPlan.validate(repair_plan)
 if not bool(checked.get("success", false)):
  return checked
 if String(repair_plan.get("target_construct_id", "")) != String(goal.get("target_construct_id", "")) \
 or String(repair_plan.get("target_root_item_instance_id", "")) != String(goal.get("root_item_instance_id", "")):
  return P.failure("CONSTRUCTION_AGENT_REPAIR_TARGET_MISMATCH")
 var projections_result := _projection_map(available_projections)
 if not bool(projections_result.get("success", false)):
  return projections_result
 var projections_by_id := {}
 for projection in projections_result["items"]:
  projections_by_id[String(projection["item_instance_id"])] = projection
 var goal_key := String(goal["goal_id"]).trim_prefix("agent-goal/").replace("/", ":")
 var lines: Array = []
 var available_item_ids: Array = []
 var line_index := 0
 for item_id_value in repair_plan["required_part_item_ids"]:
  var item_id := String(item_id_value)
  var bindings: Array = []
  var definition_id := "repair_part"
  var missing := 1
  if projections_by_id.has(item_id):
   var projection: Dictionary = projections_by_id[item_id]
   definition_id = String(projection["definition_id"])
   bindings.append({"item_instance_id": item_id, "quantity": 1, "projection": projection.duplicate(true)})
   available_item_ids.append(item_id)
   missing = 0
  var mode := "AVAILABLE" if missing == 0 else ("PROCURE" if bool(options.get("allow_procurement", true)) else "BLOCKED")
  lines.append(Line.create(
   "bom-line/%s/repair-%03d" % [goal_key, line_index],
   "REPAIR_PART",
   item_id,
   definition_id,
   1,
   {},
   bindings,
   [],
   missing,
   mode,
   0.0
  ))
  line_index += 1
 var bom := Bom.create("agent-bom/%s" % goal_key, goal, lines)
 checked = Bom.validate(bom)
 if not bool(checked.get("success", false)):
  return checked
 if not bool(bom["ready_for_execution"]):
  var blocked := Plan.create("agent-plan/%s" % goal_key, goal, bom, {}, {}, [])
  return P.success({"bom": bom, "plan": blocked, "blocked": true})
 available_item_ids.sort()
 var steps: Array = []
 var previous: Array = []
 var index := 0
 var requests := _common_resource_requests(goal, bom)
 for item_id in available_item_ids:
  requests.append({"resource_kind": "ITEM", "resource_id": item_id, "quantity": 1.0, "exclusive": true})
 requests = _canonical_resource_requests(requests)
 if not requests.is_empty():
  var reserve_id := "agent-step/%s/%03d-reserve" % [goal_key, index]
  steps.append(Step.create(
   reserve_id, index, Step.RESERVE, previous,
   {"requests": requests, "lease_ticks": int(options.get("lease_ticks", 100))},
   "operation/agent/%s/reserve" % goal_key,
   Array(goal["required_agent_capabilities"]),
   Array(goal["required_tool_ids"]),
   Array(goal["workspace_ids"])
  ))
  previous = [reserve_id]
  index += 1
 if not available_item_ids.is_empty():
  var deliver_id := "agent-step/%s/%03d-deliver" % [goal_key, index]
  steps.append(Step.create(
   deliver_id, index, Step.DELIVER, previous,
   {"item_instance_ids": available_item_ids, "target_relation": Dictionary(goal["placement_relation"])},
   "operation/agent/%s/deliver" % goal_key,
   Array(goal["required_agent_capabilities"]),
   Array(goal["required_tool_ids"]),
   Array(goal["workspace_ids"])
  ))
  previous = [deliver_id]
  index += 1
 var repair_step_id := "agent-step/%s/%03d-repair" % [goal_key, index]
 steps.append(Step.create(
  repair_step_id, index, Step.REPAIR, previous,
  {
   "plan_id": "damage-plan/agent/%s/repair" % goal_key,
   "repair_plan": repair_plan,
   "failure_mode": String(options.get("failure_mode", "")),
   "command_sequence_offset": 0,
  },
  "operation/agent/%s/repair" % goal_key,
  Array(goal["required_agent_capabilities"]),
  Array(goal["required_tool_ids"]),
  Array(goal["workspace_ids"])
 ))
 previous = [repair_step_id]
 index += 1
 var verify_id := "agent-step/%s/%03d-verify" % [goal_key, index]
 steps.append(Step.create(
  verify_id, index, Step.VERIFY, previous,
  {"construct_id": String(goal["target_construct_id"]), "required_outcomes": Array(goal["required_outcomes"])},
  "operation/agent/%s/verify" % goal_key,
  Array(goal["required_agent_capabilities"])
 ))
 var plan := Plan.create("agent-plan/%s" % goal_key, goal, bom, {}, {}, steps)
 checked = Plan.validate(plan)
 if not bool(checked.get("success", false)):
  return checked
 return P.success({"bom": bom, "plan": plan, "blocked": false})

static func _compile_salvage(goal: Dictionary, options: Dictionary) -> Dictionary:
 if typeof(options.get("damage_request")) != TYPE_DICTIONARY:
  return P.failure("CONSTRUCTION_AGENT_DAMAGE_REQUEST_REQUIRED")
 var request: Dictionary = options["damage_request"]
 var checked := DamageRequest.validate(request)
 if not bool(checked.get("success", false)):
  return checked
 if String(request.get("construct_id", "")) != String(goal.get("target_construct_id", "")):
  return P.failure("CONSTRUCTION_AGENT_SALVAGE_TARGET_MISMATCH")
 var goal_key := String(goal["goal_id"]).trim_prefix("agent-goal/").replace("/", ":")
 var bom := Bom.create("agent-bom/%s" % goal_key, goal, [])
 checked = Bom.validate(bom)
 if not bool(checked.get("success", false)):
  return checked
 var steps: Array = []
 var previous: Array = []
 var index := 0
 var requests := _canonical_resource_requests(_common_resource_requests(goal, bom))
 if not requests.is_empty():
  var reserve_id := "agent-step/%s/%03d-reserve" % [goal_key, index]
  steps.append(Step.create(
   reserve_id, index, Step.RESERVE, previous,
   {"requests": requests, "lease_ticks": int(options.get("lease_ticks", 100))},
   "operation/agent/%s/reserve" % goal_key,
   Array(goal["required_agent_capabilities"]),
   Array(goal["required_tool_ids"]),
   Array(goal["workspace_ids"])
  ))
  previous = [reserve_id]
  index += 1
 var salvage_step_id := "agent-step/%s/%03d-salvage" % [goal_key, index]
 steps.append(Step.create(
  salvage_step_id, index, Step.SALVAGE, previous,
  {
   "plan_id": "damage-plan/agent/%s/salvage" % goal_key,
   "request": request,
   "failure_mode": String(options.get("failure_mode", "")),
   "command_sequence_offset": 0,
  },
  "operation/agent/%s/salvage" % goal_key,
  Array(goal["required_agent_capabilities"]),
  Array(goal["required_tool_ids"]),
  Array(goal["workspace_ids"])
 ))
 previous = [salvage_step_id]
 index += 1
 var verify_id := "agent-step/%s/%03d-verify" % [goal_key, index]
 steps.append(Step.create(
  verify_id, index, Step.VERIFY, previous,
  {"construct_id": String(goal["target_construct_id"]), "required_outcomes": Array(goal["required_outcomes"])},
  "operation/agent/%s/verify" % goal_key,
  Array(goal["required_agent_capabilities"])
 ))
 var plan := Plan.create("agent-plan/%s" % goal_key, goal, bom, {}, {}, steps)
 checked = Plan.validate(plan)
 if not bool(checked.get("success", false)):
  return checked
 return P.success({"bom": bom, "plan": plan, "blocked": false})

static func _common_resource_requests(goal: Dictionary, bom: Dictionary) -> Array:
 var requests: Array = []
 for tool in goal.get("required_tool_ids", []):
  requests.append({"resource_kind": "TOOL", "resource_id": String(tool), "quantity": 1.0, "exclusive": true})
 for workspace in goal.get("workspace_ids", []):
  requests.append({"resource_kind": "WORKSPACE", "resource_id": String(workspace), "quantity": 1.0, "exclusive": true})
 if float(goal.get("budget_limit", 0.0)) > 0.0 and float(bom.get("total_estimated_cost", 0.0)) > 0.0:
  requests.append({
   "resource_kind": "BUDGET",
   "resource_id": "budget/%s" % String(goal["agent_id"]).trim_prefix("agent/"),
   "quantity": float(bom["total_estimated_cost"]),
   "exclusive": false,
  })
 return requests

static func _canonical_resource_requests(requests: Array) -> Array:
 var by_key := {}
 for raw in requests:
  var key := "%s|%s" % [String(raw.get("resource_kind", "")), String(raw.get("resource_id", ""))]
  if by_key.has(key):
   var prior: Dictionary = by_key[key]
   prior["quantity"] = P.metric(float(prior["quantity"]) + float(raw.get("quantity", 0.0)))
   prior["exclusive"] = bool(prior["exclusive"]) or bool(raw.get("exclusive", false))
   by_key[key] = prior
  else:
   by_key[key] = {
    "resource_kind": String(raw.get("resource_kind", "")),
    "resource_id": String(raw.get("resource_id", "")),
    "quantity": P.metric(float(raw.get("quantity", 0.0))),
    "exclusive": bool(raw.get("exclusive", false)),
   }
 var keys := by_key.keys()
 keys.sort()
 var result: Array = []
 for key in keys:
  result.append(by_key[key])
 return result

static func _projection_map(values:Array)->Dictionary:
 var items:Array=[];var seen:={}
 for v in values:
  if typeof(v)!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_AGENT_INVENTORY_PROJECTION")
  var x=ProjectionScript.validate(v);if not bool(x.success):return x
  var id=String(v.item_instance_id);if seen.has(id):return P.failure("DUPLICATE_CONSTRUCTION_AGENT_INVENTORY_ITEM")
  seen[id]=true;items.append(v.duplicate(true))
 items.sort_custom(func(a,b):return String(a.item_instance_id)<String(b.item_instance_id));return P.success({"items":items})
static func _allocate_available(definition_id:String,required:int,components:Dictionary,items:Array,used:Dictionary,single:bool)->Dictionary:
 var bindings:Array=[];var total:=0
 for item in items:
  var id=String(item.item_instance_id);if used.has(id) or String(item.definition_id)!=definition_id or not _subset(components,Dictionary(item.components)):continue
  var quantity=1 if single else mini(int(item.quantity),required-total);if single and int(item.quantity)!=1:continue
  bindings.append({"item_instance_id":id,"quantity":quantity,"projection":item.duplicate(true)});used[id]=true;total+=quantity
  if total>=required:break
 return {"bindings":bindings,"quantity":total}
static func _subset(required:Dictionary,actual:Dictionary)->bool:
 for k in required:
  if not actual.has(k):return false
  if required[k] is Dictionary:
   if not actual[k] is Dictionary or not _subset(required[k],actual[k]):return false
  elif Utils.canonical_json(required[k])!=Utils.canonical_json(actual[k]):return false
 return true
static func _select_recipe(definition_id:String,components:Dictionary,recipes:Array)->Dictionary:
 for recipe in recipes:
  for product in recipe.output_products:
   if String(product.definition_id)==definition_id and _subset(components,Dictionary(product.components)):return P.success({"recipe":recipe.duplicate(true),"product":product.duplicate(true)})
 return P.failure("CONSTRUCTION_AGENT_FABRICATION_RECIPE_NOT_FOUND")
static func _recipe_by_checksum(recipes:Array,checksum:String)->Dictionary:
 for r in recipes:
  if String(r.checksum)==checksum:return r
 return {}
static func _dedupe_projections(values: Array) -> Array:
 var by_id: Dictionary = {}
 for value in values:
  by_id[String(value.item_instance_id)] = value.duplicate(true)
 var ids := by_id.keys()
 ids.sort()
 var result: Array = []
 for id in ids:
  result.append(by_id[id])
 return result
static func _build_source_ids(plan: Dictionary) -> Array:
 var ids: Array = []
 for projection in plan.source_item_projections:
  ids.append(String(projection.item_instance_id))
 ids.sort()
 return ids
