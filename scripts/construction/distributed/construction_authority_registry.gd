extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Record=preload("res://scripts/construction/distributed/construction_authority_record.gd")
const Plan=preload("res://scripts/construction/distributed/construction_authority_migration_plan.gd")
const SCHEMA="planet_simulator.construction_authority_registry.v1"
const FIELDS:Array[String]=["schema","generation","records","checksum"]
var _records:Dictionary={};var _generation:=0
func publish(record:Dictionary)->Dictionary:
 var x=Record.validate(record);if not bool(x.success):return x
 var id=String(record.construct_id)
 if _records.has(id):
  var old:Dictionary=_records[id]
  if String(old.checksum)==String(record.checksum):return P.success({"replay":true,"record":old.duplicate(true)})
  if int(record.authority_epoch)<=int(old.authority_epoch):return P.failure("CONSTRUCTION_AUTHORITY_EPOCH_NOT_MONOTONIC")
 _records[id]=record.duplicate(true);_generation+=1;return P.success({"replay":false,"record":record.duplicate(true)})
func get_record(construct_id:String)->Dictionary:return Dictionary(_records.get(construct_id,{})).duplicate(true)
func get_generation()->int:return _generation
func begin_migration(plan:Dictionary)->Dictionary:
 var x=Plan.validate(plan);if not bool(x.success):return x
 var id=String(plan.construct_id);var current=get_record(id)
 if current.is_empty():return P.failure("CONSTRUCTION_AUTHORITY_RECORD_NOT_FOUND")
 if String(current.checksum)!=String(plan.source_record_checksum) or int(current.authority_epoch)!=int(plan.source_authority_epoch) or String(current.owner_server_id)!=String(plan.source_server_id) or String(current.construct_checksum)!=String(plan.construct_checksum):return P.failure("CONSTRUCTION_AUTHORITY_MIGRATION_PRECONDITION_MISMATCH")
 if String(current.state)!=Record.ACTIVE:return P.failure("CONSTRUCTION_AUTHORITY_ALREADY_FENCED")
 var next=Record.create(id,String(current.owner_server_id),String(current.owner_cell_id),int(current.authority_epoch),String(current.construct_checksum),Array(current.replica_server_ids),int(current.lease_expires_tick),String(current.section_coordinator_server_id),Dictionary(current.metadata),Record.MIGRATING,String(plan.migration_id),String(plan.target_server_id))
 _records[id]=next;_generation+=1;return P.success({"record":next.duplicate(true)})
func abort_migration(plan:Dictionary)->Dictionary:
 var x=Plan.validate(plan);if not bool(x.success):return x
 var current=get_record(String(plan.construct_id))
 if current.is_empty() or String(current.state)!=Record.MIGRATING or String(current.migration_id)!=String(plan.migration_id):return P.failure("CONSTRUCTION_AUTHORITY_MIGRATION_NOT_ACTIVE")
 var next=Record.create(String(current.construct_id),String(current.owner_server_id),String(current.owner_cell_id),int(current.authority_epoch),String(current.construct_checksum),Array(current.replica_server_ids),int(current.lease_expires_tick),String(current.section_coordinator_server_id),Dictionary(current.metadata))
 _records[String(current.construct_id)]=next;_generation+=1;return P.success({"record":next.duplicate(true)})
func commit_migration(plan:Dictionary,new_construct_checksum:String,lease_expires_tick:int)->Dictionary:
 var x=Plan.validate(plan);if not bool(x.success):return x
 var current=get_record(String(plan.construct_id))
 if current.is_empty() or String(current.state)!=Record.MIGRATING or String(current.migration_id)!=String(plan.migration_id) or String(current.target_server_id)!=String(plan.target_server_id):return P.failure("CONSTRUCTION_AUTHORITY_MIGRATION_NOT_ACTIVE")
 var next=Record.create(String(plan.construct_id),String(plan.target_server_id),String(plan.target_cell_id),int(plan.target_authority_epoch),new_construct_checksum,Array(plan.replica_server_ids),lease_expires_tick,String(plan.target_server_id),Dictionary(plan.metadata))
 _records[String(plan.construct_id)]=next;_generation+=1;return P.success({"record":next.duplicate(true)})
func refresh_checksum(construct_id:String,owner_server_id:String,authority_epoch:int,new_checksum:String,lease_expires_tick:int)->Dictionary:
 var current=get_record(construct_id)
 if current.is_empty():return P.failure("CONSTRUCTION_AUTHORITY_RECORD_NOT_FOUND")
 if String(current.state)!=Record.ACTIVE or String(current.owner_server_id)!=owner_server_id or int(current.authority_epoch)!=authority_epoch:return P.failure("CONSTRUCTION_AUTHORITY_WRITE_FENCED")
 if new_checksum.length()!=64:return P.failure("INVALID_CONSTRUCTION_AUTHORITY_CONSTRUCT_CHECKSUM")
 if String(current.construct_checksum)==new_checksum and int(current.lease_expires_tick)==lease_expires_tick:return P.success({"replay":true,"record":current})
 var next=Record.create(construct_id,owner_server_id,String(current.owner_cell_id),authority_epoch,new_checksum,Array(current.replica_server_ids),lease_expires_tick,String(current.section_coordinator_server_id),Dictionary(current.metadata))
 _records[construct_id]=next;_generation+=1;return P.success({"replay":false,"record":next.duplicate(true)})
func takeover(construct_id:String,target_server_id:String,target_cell_id:String,current_tick:int,new_construct_checksum:String,new_lease_expires_tick:int)->Dictionary:
 var current=get_record(construct_id)
 if current.is_empty():return P.failure("CONSTRUCTION_AUTHORITY_RECORD_NOT_FOUND")
 if String(current.state)!=Record.ACTIVE:return P.failure("CONSTRUCTION_AUTHORITY_WRITE_FENCED")
 if current_tick<=int(current.lease_expires_tick):return P.failure("CONSTRUCTION_AUTHORITY_LEASE_NOT_EXPIRED")
 if target_server_id==String(current.owner_server_id):return P.failure("CONSTRUCTION_AUTHORITY_TAKEOVER_OWNER_UNCHANGED")
 var replicas:Array=Array(current.replica_server_ids).duplicate();replicas.erase(target_server_id);replicas.append(String(current.owner_server_id));replicas=P.sorted_strings(replicas)
 var next=Record.create(construct_id,target_server_id,target_cell_id,int(current.authority_epoch)+1,new_construct_checksum,replicas,new_lease_expires_tick,target_server_id,{"takeover_from":String(current.owner_server_id),"takeover_tick":current_tick})
 _records[construct_id]=next;_generation+=1;return P.success({"record":next.duplicate(true)})
func register_split_child(parent_construct_id:String,child_record:Dictionary)->Dictionary:
 var parent=get_record(parent_construct_id)
 if parent.is_empty() or String(parent.state)!=Record.ACTIVE:return P.failure("CONSTRUCTION_AUTHORITY_SPLIT_PARENT_NOT_ACTIVE")
 if _records.has(String(child_record.get("construct_id",""))):return P.failure("CONSTRUCTION_AUTHORITY_SPLIT_CHILD_EXISTS")
 return publish(child_record)
func export_state()->Dictionary:
 var ids:Array=_records.keys();ids.sort();var rows:Array=[]
 for id in ids:rows.append(Dictionary(_records[id]).duplicate(true))
 var s={"schema":SCHEMA,"generation":_generation,"records":rows,"checksum":""};s.checksum=compute_state_checksum(s);return s
func load_state(state:Dictionary)->Dictionary:
 var x=validate_state(state);if not bool(x.success):return x
 var next:Dictionary={}
 for record in state.records:next[String(record.construct_id)]=Dictionary(record).duplicate(true)
 _records=next;_generation=int(state.generation);return P.success()
static func validate_state(state:Dictionary)->Dictionary:
 var x=Utils.validate_exact_fields(state,FIELDS);if not bool(x.success):return x
 if state.get("schema")!=SCHEMA or not Utils.is_json_integer(state.get("generation")) or int(state.generation)<0 or typeof(state.get("records"))!=TYPE_ARRAY:return P.failure("INVALID_CONSTRUCTION_AUTHORITY_REGISTRY_STATE")
 var prev=""
 for record in state.records:
  if typeof(record)!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_AUTHORITY_REGISTRY_RECORD")
  x=Record.validate(record);if not bool(x.success):return x
  var id=String(record.construct_id);if not prev.is_empty() and id<=prev:return P.failure("NON_CANONICAL_CONSTRUCTION_AUTHORITY_REGISTRY_RECORDS")
  prev=id
 if String(state.get("checksum",""))!=compute_state_checksum(state):return P.failure("CONSTRUCTION_AUTHORITY_REGISTRY_STATE_CHECKSUM_MISMATCH")
 return P.success()
static func compute_state_checksum(state:Dictionary)->String:var p=state.duplicate(true);p.checksum="";return Utils.payload_hash(p)
