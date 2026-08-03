extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Line=preload("res://scripts/construction/agents/construction_agent_bom_line.gd")
const SCHEMA="planet_simulator.construction_agent_bom.v1"
const FIELDS:Array[String]=["schema","bom_id","goal_id","goal_checksum","lines","total_estimated_cost","ready_for_execution","unresolved_line_ids","checksum"]
static func create(bom_id:String,goal:Dictionary,lines:Array)->Dictionary:
 var sorted=P.sorted_rows(lines,"line_id");var cost:=0.0;var unresolved:Array=[]
 for line in sorted:
  cost+=float(line.get("estimated_cost",0.0))
  if String(line.get("acquisition_mode","")) in ["PROCURE","BLOCKED"]:unresolved.append(String(line.get("line_id","")))
 unresolved.sort();var v={"schema":SCHEMA,"bom_id":bom_id,"goal_id":String(goal.get("goal_id","")),"goal_checksum":String(goal.get("checksum","")),"lines":sorted,"total_estimated_cost":P.metric(cost),"ready_for_execution":unresolved.is_empty(),"unresolved_line_ids":unresolved,"checksum":""};v.checksum=compute_checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
 var x=Utils.validate_exact_fields(v,FIELDS);if not bool(x.success):return x
 if v.get("schema")!=SCHEMA or not P.path_id(String(v.get("bom_id","")),"agent-bom/") or not P.path_id(String(v.get("goal_id","")),"agent-goal/") or String(v.get("goal_checksum","" )).length()!=64:return P.failure("INVALID_CONSTRUCTION_AGENT_BOM_IDENTITY")
 if typeof(v.get("lines"))!=TYPE_ARRAY:return P.failure("INVALID_CONSTRUCTION_AGENT_BOM_LINES")
 var previous:="";var seen:={};var cost:=0.0;var unresolved:Array=[]
 for row in v.lines:
  if typeof(row)!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_AGENT_BOM_LINE")
  x=Line.validate(row);if not bool(x.success):return x
  var id:=String(row.line_id);if seen.has(id) or (not previous.is_empty() and id<previous):return P.failure("NON_CANONICAL_CONSTRUCTION_AGENT_BOM_LINES")
  seen[id]=true;previous=id;cost+=float(row.estimated_cost)
  if String(row.acquisition_mode) in ["PROCURE","BLOCKED"]:unresolved.append(id)
 unresolved.sort()
 if not P.nearly_equal(float(v.get("total_estimated_cost",-1)),P.metric(cost)):return P.failure("CONSTRUCTION_AGENT_BOM_COST_MISMATCH")
 if bool(v.get("ready_for_execution",false))!=unresolved.is_empty() or Array(v.get("unresolved_line_ids",[]))!=unresolved:return P.failure("CONSTRUCTION_AGENT_BOM_READINESS_MISMATCH")
 if String(v.get("checksum",""))!=compute_checksum(v):return P.failure("CONSTRUCTION_AGENT_BOM_CHECKSUM_MISMATCH")
 return P.success()
static func compute_checksum(v:Dictionary)->String:var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
