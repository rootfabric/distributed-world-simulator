extends RefCounted

const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const ProjectionScript=preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const Recipe=preload("res://scripts/construction/fabrication/construction_fabrication_recipe.gd")
const Goal=preload("res://scripts/construction/agents/construction_agent_goal.gd")
const C4=preload("res://tests/construction/fixtures/c4_reusable_table_fixture.gd")
const C17=preload("res://tests/construction/fixtures/c17_distributed_authority_fixture.gd")
const Cluster=preload("res://scripts/construction/distributed/construction_distributed_authority_cluster.gd")
const Record=preload("res://scripts/construction/distributed/construction_authority_record.gd")
const BuildPlan=preload("res://scripts/construction/build/construction_build_plan.gd")
const Instantiation=preload("res://scripts/construction/composites/construction_composite_instantiation.gd")
const RepairPlan=preload("res://scripts/construction/damage/construction_repair_plan.gd")
const C9=preload("res://tests/construction/fixtures/c9_damage_split_repair_fixture.gd")

const AGENT="agent/c19/builder-alpha"
const GOAL_ID="agent-goal/c19/reusable-table"
const TARGET="construct/c19/reusable-table"
const ROOT_ITEM="item/c19/reusable-table-root"
const TOOL="tool/c19/powered-driver"
const WORKSPACE="workspace/c19/assembly-bay"
const OWNER=C17.SERVER_A
const ENTRY=C17.SERVER_C

static func definition()->Dictionary:return C4.definition()
static func inventory()->Array:
 var values:Array=[]
 for projection in C4.source_projections("agent"):
  if String(projection.item_instance_id).ends_with("leg-d"):continue
  values.append(projection)
 values.append(ProjectionScript.create("item/c19/raw-lumber","raw_lumber","Raw lumber",4,ProjectionScript.container_relation("container/c19/raw"),{"grade":"structural"},0))
 return values
static func recipe()->Dictionary:
 return Recipe.create("fabrication-recipe/c19/structural-wood-beam",1,"Structural wood beam",[Recipe.input_requirement("raw_lumber",2,{"grade":"structural"})],[Recipe.output_product("beam","wood_beam","Fabricated structural beam",1,{"grade":{"class":"structural","batch":"c19"}})],["FABRICATION_CELL"],["POWER"],5,{"estimated_cost":8.0})
static func execution_context()->Dictionary:
 return {"client_id":"client/c19/builder-alpha","session_id":"session/c19/builder-alpha","session_epoch":1,"permission_epoch":1,"start_sequence":0,"entry_server_id":ENTRY,"expected_owner_server_id":OWNER,"authority_epoch":1,"expected_server_generation":-1}
static func goal(budget:float=100.0)->Dictionary:
 return Goal.create(GOAL_ID,AGENT,Goal.BUILD_COMPOSITE,definition(),TARGET,ROOT_ITEM,ProjectionScript.world_relation(),{"parameter/finish":"sealed","parameter/load-rating-kg":120.0},["SUPPORT_SURFACE"],900,budget,10000,["FASTEN","INSPECT","OPERATE_FABRICATION_CELL"],[TOOL],[WORKSPACE],execution_context(),{"purpose":"agent acceptance"})

static func repair_plan()->Dictionary:
 var snapshot_value := C9.snapshot("c19")
 var part_item_ids: Array = []
 for part in snapshot_value["parts"]:
  part_item_ids.append(String(part["item_instance_id"]))
 return RepairPlan.create(
  "repair/c19/bridge",
  "damage/bridge/c19/impact-1",
  snapshot_value,
  [],
  [],
  part_item_ids,
  ["bond/bridge/c19/joint-arm"],
  "a".repeat(64)
 )
static func repair_goal()->Dictionary:
 var source := C9.snapshot("c19")
 var context := execution_context().duplicate(true)
 context["start_sequence"] = 10
 return Goal.create(
  "agent-goal/c19/repair-bridge",
  AGENT,
  Goal.REPAIR_CONSTRUCT,
  {},
  String(source["construct_id"]),
  String(source["root_item_instance_id"]),
  ProjectionScript.world_relation(),
  {},
  ["SUPPORT_STRUCTURE"],
  850,
  50.0,
  10000,
  ["FASTEN", "INSPECT"],
  [TOOL],
  [WORKSPACE],
  context,
  {"purpose":"repair acceptance"}
 )
static func salvage_goal()->Dictionary:
 var source := C9.snapshot("c19")
 var context := execution_context().duplicate(true)
 context["start_sequence"] = 20
 return Goal.create(
  "agent-goal/c19/salvage-bridge",
  AGENT,
  Goal.SALVAGE_CONSTRUCT,
  {},
  String(source["construct_id"]),
  String(source["root_item_instance_id"]),
  ProjectionScript.world_relation(),
  {},
  ["SALVAGE_AVAILABLE"],
  800,
  20.0,
  10000,
  ["DISASSEMBLE", "INSPECT"],
  [TOOL],
  [WORKSPACE],
  context,
  {"purpose":"salvage acceptance"}
 )
static func repair_inventory()->Array:
 return C9.items("c19")
static func damage_request()->Dictionary:
 return C9.request("c19")
static func repair_capacities()->Dictionary:
 var result := {TOOL: 1.0, WORKSPACE: 1.0}
 for projection in repair_inventory():
  result[String(projection["item_instance_id"])] = float(projection["quantity"])
 return result
static func authority_cluster_for(construct_id:String)->Dictionary:
 var cluster=Cluster.new();cluster.setup();var owner=C17.FakeGateway.new();var entry=C17.FakeGateway.new();cluster.register_server(OWNER,C17.CELL_A,owner);cluster.register_server(ENTRY,C17.CELL_C,entry)
 var state={"construct_id":construct_id,"revision":0,"payload":{"label":"c19 domain target","commands":[]},"checksum":""};state.checksum=_state_checksum(state)
 var record=Record.create(construct_id,OWNER,C17.CELL_A,1,String(state.checksum),[ENTRY],100,OWNER,{"goal_id":"agent-goal/c19/domain"});cluster.register_construct(record,state)
 return {"cluster":cluster,"owner_gateway":owner,"entry_gateway":entry}

static func capacities()->Dictionary:
 var result={TOOL:1.0,WORKSPACE:1.0,"definition-stock/raw_lumber":4.0,"budget/c19/builder-alpha":100.0}
 for projection in inventory():
  result[String(projection.item_instance_id)] = float(projection.quantity)
 return result
static func authority_cluster()->Dictionary:
 var cluster=Cluster.new();cluster.setup();var owner=C17.FakeGateway.new();var entry=C17.FakeGateway.new();cluster.register_server(OWNER,C17.CELL_A,owner);cluster.register_server(ENTRY,C17.CELL_C,entry)
 var state={"construct_id":TARGET,"revision":0,"payload":{"label":"c19 target","commands":[]},"checksum":""};state.checksum=_state_checksum(state)
 var record=Record.create(TARGET,OWNER,C17.CELL_A,1,String(state.checksum),[ENTRY],100,OWNER,{"goal_id":GOAL_ID});cluster.register_construct(record,state)
 return {"cluster":cluster,"owner_gateway":owner,"entry_gateway":entry}
static func _state_checksum(v:Dictionary)->String:var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)

class FakeFabrication extends RefCounted:
 var calls:=0;var outputs:Dictionary={};var operations:Dictionary={}
 func fabricate(payload:Dictionary,operation_id:String)->Dictionary:
  var checksum=Utils.payload_hash({"payload":payload,"operation_id":operation_id})
  if operations.has(operation_id):
   if String(operations[operation_id].checksum)!=checksum:return P.failure("FAKE_FABRICATION_OPERATION_CONFLICT")
   var replay=Dictionary(operations[operation_id].result).duplicate(true);replay.replay=true;return replay
  var projection=Dictionary(payload.get("output_projection",{}));var checked=ProjectionScript.validate(projection);if not bool(checked.success):return checked
  calls+=1;outputs[String(projection.item_instance_id)]=projection.duplicate(true);var result=P.success({"output_projection":projection,"replay":false});operations[operation_id]={"checksum":checksum,"result":result.duplicate(true)};return result
class FakeLogistics extends RefCounted:
 var calls:=0;var operations:Dictionary={}
 func deliver(payload:Dictionary,operation_id:String)->Dictionary:
  var checksum=Utils.payload_hash({"payload":payload,"operation_id":operation_id})
  if operations.has(operation_id):var r=Dictionary(operations[operation_id].result).duplicate(true);r.replay=true;return r
  calls+=1;var result=P.success({"delivered_item_ids":Array(payload.get("item_instance_ids",[])).duplicate(),"replay":false});operations[operation_id]={"checksum":checksum,"result":result.duplicate(true)};return result
class FakeBuildRegistry extends RefCounted:
 var calls:=0;var plans:Dictionary={};var operations:Dictionary={}
 func register_plan(plan:Dictionary,instantiation:Dictionary,operation_id:String)->Dictionary:
  var checked=BuildPlan.validate(plan);if not bool(checked.success):return checked
  checked=Instantiation.validate(instantiation);if not bool(checked.success):return checked
  var checksum=Utils.payload_hash({"plan":plan,"instantiation":instantiation,"operation_id":operation_id})
  if operations.has(operation_id):var r=Dictionary(operations[operation_id].result).duplicate(true);r.replay=true;return r
  calls+=1;plans[String(plan.build_plan_id)]=plan.duplicate(true);var result=P.success({"build_plan_id":String(plan.build_plan_id),"replay":false});operations[operation_id]={"checksum":checksum,"result":result.duplicate(true)};return result
class FakeVerifier extends RefCounted:
 var gateway;var calls:=0;var operations:Dictionary={}
 func _init(source=null):gateway=source
 func verify(payload:Dictionary,operation_id:String)->Dictionary:
  if operations.has(operation_id):var r=Dictionary(operations[operation_id]).duplicate(true);r.replay=true;return r
  calls+=1;var exported=gateway.export_construct_state(String(payload.construct_id));if not bool(exported.success):return exported
  var revision=int(exported.state.revision);if revision<3:return P.failure("CONSTRUCTION_AGENT_OUTCOME_NOT_SATISFIED",{"status":"RETRYABLE","revision":revision})
  var result=P.success({"required_outcomes":Array(payload.required_outcomes).duplicate(),"construct_revision":revision,"replay":false});operations[operation_id]=result.duplicate(true);return result

class FakeVerifierAlways extends RefCounted:
 var calls:=0;var operations:Dictionary={}
 func verify(payload:Dictionary,operation_id:String)->Dictionary:
  if operations.has(operation_id):
   var replay=Dictionary(operations[operation_id]).duplicate(true);replay.replay=true;return replay
  calls+=1
  var result=P.success({"required_outcomes":Array(payload.get("required_outcomes",[])).duplicate(),"replay":false})
  operations[operation_id]=result.duplicate(true)
  return result

class PlannerAdapter extends RefCounted:
 const Planner=preload("res://scripts/construction/agents/construction_agent_planner.gd")
 func compile(goal:Dictionary,definition:Dictionary,inventory:Array,recipes:Array,options:Dictionary={})->Dictionary:return Planner.compile(goal,definition,inventory,recipes,options)
class MemoryStore extends RefCounted:
 var values:Dictionary={}
 func save_state(key:String,state:Dictionary)->Dictionary:values[key]=state.duplicate(true);return P.success()
 func load_state(key:String)->Dictionary:return P.success({"state":Dictionary(values.get(key,{})).duplicate(true)}) if values.has(key) else P.failure("NOT_FOUND")
