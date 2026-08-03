extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Record=preload("res://scripts/construction/distributed/construction_authority_record.gd")
const InnerCommand=preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const RoutedCommand=preload("res://scripts/construction/distributed/construction_distributed_command.gd")
const Grant=preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_grant.gd")
const CONSTRUCT="construct/c17/habitat"
const CHILD="construct/c17/split-child"
const SERVER_A="server/c17/alpha"
const SERVER_B="server/c17/beta"
const SERVER_C="server/c17/gamma"
const CELL_A="cell/c17/100-100"
const CELL_B="cell/c17/101-100"
const CELL_C="cell/c17/102-100"
class FakeGateway extends RefCounted:
 var states:Dictionary={};var terminals:Dictionary={};var commit_count:=0;var submit_calls:=0
 func import_construct_state(state:Dictionary,terminal_operations:Array=[])->Dictionary:
  if not _valid_state(state):return P.failure("INVALID_FAKE_CONSTRUCTION_STATE")
  states[String(state.construct_id)]=state.duplicate(true)
  for op in terminal_operations:
   var command_id=String(op.get("command_id",op.get("operation_id","")));terminals[command_id]={"operation_id":String(op.get("operation_id","")),"command_checksum":String(op.get("command_checksum","")),"result":Dictionary(op.get("result",{})).duplicate(true)}
  return P.success()
 func export_construct_state(construct_id:String)->Dictionary:
  if not states.has(construct_id):return P.failure("FAKE_CONSTRUCTION_STATE_NOT_FOUND")
  var ops:Array=[];var ids:Array=terminals.keys();ids.sort()
  for id in ids:ops.append({"operation_id":String(terminals[id].get("operation_id",id)),"command_id":String(id),"command_checksum":String(terminals[id].command_checksum),"result":Dictionary(terminals[id].result).duplicate(true)})
  return P.success({"state":Dictionary(states[construct_id]).duplicate(true),"terminal_operations":ops})
 func get_construct_checksum(construct_id:String)->String:return String(states.get(construct_id,{}).get("checksum",""))
 func has_terminal_command(command_id:String,command_checksum:String)->bool:return terminals.has(command_id) and String(terminals[command_id].command_checksum)==command_checksum
 func submit(command:Dictionary)->Dictionary:
  submit_calls+=1;var id=String(command.command_id);var checksum=String(command.checksum)
  if terminals.has(id):
   if String(terminals[id].command_checksum)!=checksum:return P.failure("FAKE_COMMAND_ID_CONFLICT")
   var replay=Dictionary(terminals[id].result).duplicate(true);replay.replay=true;return replay
  var construct_id=String(command.construct_id)
  if not states.has(construct_id):return P.failure("FAKE_CONSTRUCTION_STATE_NOT_FOUND")
  var state:Dictionary=states[construct_id].duplicate(true);state.revision=int(state.revision)+1
  var commands:Array=Array(state.payload.get("commands",[])).duplicate();commands.append(id);state.payload.commands=commands;state.checksum=_state_checksum(state);states[construct_id]=state
  commit_count+=1;var result=P.success({"accepted":true,"replay":false,"construct_id":construct_id,"construct_checksum":String(state.checksum),"revision":int(state.revision)})
  var operation_id=String(command.payload.get("operation_id",command.payload.get("request",{}).get("operation_id","operation/c17/fallback")));terminals[id]={"operation_id":operation_id,"command_checksum":checksum,"result":result.duplicate(true)};return result
 func _valid_state(state:Dictionary)->bool:return String(state.get("construct_id","")).begins_with("construct/") and int(state.get("revision",-1))>=0 and typeof(state.get("payload"))==TYPE_DICTIONARY and String(state.get("checksum",""))==_state_checksum(state)
 func _state_checksum(state:Dictionary)->String:var p=state.duplicate(true);p.checksum="";return Utils.payload_hash(p)
class MemoryStore extends RefCounted:
 var values:Dictionary={}
 func save_state(key:String,state:Dictionary)->Dictionary:values[key]=state.duplicate(true);return P.success()
 func load_state(key:String)->Dictionary:return P.success({"state":Dictionary(values.get(key,{})).duplicate(true)}) if values.has(key) else P.failure("NOT_FOUND")
static func state(construct_id:String=CONSTRUCT,label:String="initial")->Dictionary:
 var v={"construct_id":construct_id,"revision":0,"payload":{"label":label,"commands":[]},"checksum":""};v.checksum=_state_checksum(v);return v
static func record(checksum:String,owner:String=SERVER_A,cell:String=CELL_A,epoch:int=1,replicas:Array=[SERVER_B,SERVER_C],lease:int=10)->Dictionary:return Record.create(CONSTRUCT,owner,cell,epoch,checksum,replicas,lease,owner,{"boundary_cells":[CELL_A,CELL_B]})
static func inner(index:int,construct_id:String=CONSTRUCT)->Dictionary:
 return InnerCommand.create("multiplayer-command/c17/%d"%index,"client/c17/operator","session/c17/operator",1,index,Grant.ACTION_EDIT,construct_id,"",-1,1,{"plan_id":"plan/c17/%d"%index,"request":{"operation_id":"operation/c17/%d"%index,"construct_id":construct_id},"failure_mode":""},{"source":"c17"})
static func routed(index:int,owner:String,epoch:int,source:String=SERVER_C,construct_id:String=CONSTRUCT)->Dictionary:return RoutedCommand.create("authority-route/c17/%d"%index,source,owner,epoch,inner(index,construct_id),{"trace":"c17"})
static func _state_checksum(v:Dictionary)->String:var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
