extends RefCounted
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const ProjectionScript=preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const Offer=preload("res://scripts/construction/economy/construction_procurement_offer.gd")
const Route=preload("res://scripts/construction/economy/construction_logistics_route.gd")
const Warehouse=preload("res://scripts/construction/economy/construction_warehouse_state.gd")
const Bid=preload("res://scripts/construction/economy/construction_contractor_bid.gd")
const Recipe=preload("res://scripts/construction/fabrication/construction_fabrication_recipe.gd")
const Chain=preload("res://scripts/construction/economy/construction_production_chain.gd")
const Line=preload("res://scripts/construction/agents/construction_agent_bom_line.gd")
const Bom=preload("res://scripts/construction/agents/construction_agent_bom.gd")
const C19=preload("res://tests/construction/fixtures/c19_agent_automation_fixture.gd")
const Listing=preload("res://scripts/construction/economy/construction_salvage_listing.gd")
const BUYER="agent/c19/builder-alpha"
const REMOTE_WAREHOUSE="warehouse/c20/remote"
const LOCAL_WAREHOUSE="warehouse/c20/local"
static func beam_item(id:String,warehouse:String)->Dictionary:return ProjectionScript.create(id,"wood_beam","Structural beam",1,ProjectionScript.container_relation(warehouse),{"grade":"structural","origin":"c20"},0)
static func remote_item()->Dictionary:return beam_item("item/c20/remote-beam",REMOTE_WAREHOUSE)
static func local_item()->Dictionary:return beam_item("item/c20/local-beam",LOCAL_WAREHOUSE)
static func salvage_item()->Dictionary:return ProjectionScript.create("item/c20/salvaged-sensor","sensor_module","Salvaged sensor",1,ProjectionScript.container_relation(REMOTE_WAREHOUSE),{"condition":"used","salvage_origin":"damage/c20"},2)
static func warehouses()->Array:
 return [Warehouse.create(LOCAL_WAREHOUSE,"supplier/c20/local","server/c20/local","cell/c20/local",100,[local_item()]),Warehouse.create(REMOTE_WAREHOUSE,"supplier/c20/remote","server/c20/remote","cell/c20/remote",100,[remote_item(),salvage_item()])]
static func local_offer()->Dictionary:return Offer.create("procurement-offer/c20/local","supplier/c20/local",LOCAL_WAREHOUSE,"wood_beam",{"grade":"structural"},1,15.0,"CREDITS",0,500,"cell/c20/local","server/c20/local",{})
static func remote_offer()->Dictionary:return Offer.create("procurement-offer/c20/remote","supplier/c20/remote",REMOTE_WAREHOUSE,"wood_beam",{"grade":"structural"},1,10.0,"CREDITS",0,500,"cell/c20/remote","server/c20/remote",{})
static func local_route()->Dictionary:return Route.create("logistics-route/c20/local",LOCAL_WAREHOUSE,ProjectionScript.container_relation("container/c20/site"),[Route.leg("route-leg/c20/local-00","cell/c20/local","cell/c20/site","carrier/c20/rover",10,2,1.0,10)],{})
static func remote_route()->Dictionary:return Route.create("logistics-route/c20/remote",REMOTE_WAREHOUSE,ProjectionScript.container_relation("container/c20/site"),[Route.leg("route-leg/c20/remote-00","cell/c20/remote","cell/c20/hub","carrier/c20/freighter",50,3,1.5,10),Route.leg("route-leg/c20/remote-01","cell/c20/hub","cell/c20/site","carrier/c20/rover",20,2,1.5,10)],{})
static func goal()->Dictionary:return C19.goal(100.0)
static func bom()->Dictionary:
 var line=Line.create("bom-line/c20/beam","PART_SLOT","slot/table/leg-d","wood_beam",1,{"grade":"structural"},[],[],1,"PROCURE",0.0)
 return Bom.create("agent-bom/c20/procurement",goal(),[line])
static func bids()->Array:
 return [Bid.create("contractor-bid/c20/cheap","contractor/c20/builders",["BUILD_COMPOSITE"],["FASTEN","INSPECT","OPERATE_FABRICATION_CELL"],2.0,20.0,"CREDITS",0,20,2,0.9,{}),Bid.create("contractor-bid/c20/late","contractor/c20/late",["BUILD_COMPOSITE"],["FASTEN","INSPECT","OPERATE_FABRICATION_CELL"],1.0,10.0,"CREDITS",9999,100,1,1.0,{})]
static func ore_recipe()->Dictionary:return Recipe.create("fabrication-recipe/c20/ore-to-ingot",1,"Ore to ingot",[Recipe.input_requirement("iron_ore",2,{})],[Recipe.output_product("ingot","iron_ingot","Iron ingot",1,{"grade":"construction"})],["FABRICATION_CELL"],["POWER"],4,{})
static func beam_recipe()->Dictionary:return Recipe.create("fabrication-recipe/c20/ingot-to-beam",1,"Ingot to beam",[Recipe.input_requirement("iron_ingot",1,{"grade":"construction"})],[Recipe.output_product("beam","steel_beam","Steel beam",1,{"grade":"construction"})],["FABRICATION_CELL"],["POWER"],6,{})
static func chain()->Dictionary:
 var s0=Chain.stage("production-stage/c20/00-smelt",0,ore_recipe(),"construct/c20/smelter",REMOTE_WAREHOUSE,"warehouse/c20/intermediate",[],["item/c20/chain-ingot"],2.0,3.0,1.0)
 var s1=Chain.stage("production-stage/c20/01-beam",1,beam_recipe(),"construct/c20/fabricator","warehouse/c20/intermediate",LOCAL_WAREHOUSE,["production-stage/c20/00-smelt"],["item/c20/chain-beam"],3.0,4.0,2.0)
 return Chain.create("production-chain/c20/beam",String(goal().goal_id),"steel_beam",[s0,s1],5.0,"CREDITS",{})
static func salvage_listing()->Dictionary:return Listing.create("salvage-listing/c20/sensor","supplier/c20/remote",REMOTE_WAREHOUSE,salvage_item(),"FIXED",7.0,"CREDITS",0.0,500)
class TransferService extends RefCounted:
 var calls:=0;var operations:Dictionary={}
 func transfer(payload:Dictionary,operation_id:String)->Dictionary:
  if operations.has(operation_id):var r=Dictionary(operations[operation_id]).duplicate(true);r.replay=true;return r
  calls+=1;var items:Array=[]
  for raw in payload.get("item_projections",[]):var p=Dictionary(raw).duplicate(true);p.relation=Dictionary(payload.get("target_relation",{})).duplicate(true);p.revision=int(p.revision)+1;items.append(p)
  var result=P.success({"item_projections":items,"replay":false});operations[operation_id]=result.duplicate(true);return result
class FabricationService extends RefCounted:
 var calls:=0;var operations:Dictionary={}
 func fabricate(stage:Dictionary,operation_id:String)->Dictionary:
  if operations.has(operation_id):var r=Dictionary(operations[operation_id]).duplicate(true);r.replay=true;return r
  calls+=1;var outputs:Array=[];var ids:Array=stage.output_item_ids;var index=0
  for product in stage.recipe.output_products:
   outputs.append(ProjectionScript.create(String(ids[index]),String(product.definition_id),String(product.display_name),int(product.quantity),ProjectionScript.container_relation(String(stage.output_warehouse_id)),Dictionary(product.components),0));index+=1
  var result=P.success({"output_projections":outputs,"replay":false});operations[operation_id]=result.duplicate(true);return result
class AgentBridge extends RefCounted:
 var calls:=0;var fulfilled:Dictionary={}
 func fulfill(goal_id:String,line_id:String,items:Array,operation_id:String)->Dictionary:calls+=1;fulfilled[line_id]=items.duplicate(true);return P.success({"goal_id":goal_id,"line_id":line_id,"item_projections":items.duplicate(true),"operation_id":operation_id})
class ContractVerifier extends RefCounted:
 var calls:=0
 func verify(contract:Dictionary,operation_id:String)->Dictionary:calls+=1;return P.success({"contract_id":String(contract.contract_id),"operation_id":operation_id})
class MemoryStore extends RefCounted:
 var values:Dictionary={}
 func save_state(key:String,state:Dictionary)->Dictionary:values[key]=state.duplicate(true);return P.success()
 func load_state(key:String)->Dictionary:return P.success({"state":Dictionary(values.get(key,{})).duplicate(true)}) if values.has(key) else P.failure("NOT_FOUND")
