extends RefCounted
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Record=preload("res://scripts/construction/distributed/construction_authority_record.gd")
const Command=preload("res://scripts/construction/distributed/construction_distributed_command.gd")
const Plan=preload("res://scripts/construction/distributed/construction_authority_migration_plan.gd")
const Handoff=preload("res://scripts/construction/distributed/construction_authority_handoff.gd")
const Replica=preload("res://scripts/construction/distributed/construction_authority_read_replica.gd")
const Registry=preload("res://scripts/construction/distributed/construction_authority_registry.gd")
const AuthorityState=preload("res://scripts/construction/distributed/construction_distributed_authority_state.gd")
const CrossZoneTransfer=preload("res://scripts/construction/distributed/construction_cross_zone_item_transfer.gd")
var _registry;var _servers:Dictionary={};var _replicas:Dictionary={};var _pending:Dictionary={};var _tick:=0
func setup(registry=null)->Dictionary:
 _registry=registry if registry!=null else Registry.new();return P.success()
func register_server(server_id:String,cell_id:String,gateway)->Dictionary:
 if not P.path_id(server_id,"server/") or not P.path_id(cell_id,"cell/") or gateway==null or not gateway.has_method("submit") or not gateway.has_method("export_construct_state") or not gateway.has_method("import_construct_state") or not gateway.has_method("get_construct_checksum"):return P.failure("INVALID_CONSTRUCTION_AUTHORITY_SERVER_ENDPOINT")
 _servers[server_id]={"cell_id":cell_id,"gateway":gateway,"available":true};return P.success()
func set_tick(tick:int)->Dictionary:
 if tick<_tick:return P.failure("CONSTRUCTION_AUTHORITY_CLUSTER_TICK_ROLLBACK")
 _tick=tick;return P.success()
func get_tick()->int:return _tick
func set_server_available(server_id:String,available:bool)->Dictionary:
 if not _servers.has(server_id):return P.failure("CONSTRUCTION_AUTHORITY_SERVER_NOT_FOUND")
 _servers[server_id].available=available;return P.success()
func register_construct(record:Dictionary,state:Dictionary)->Dictionary:
 var x=Record.validate(record);if not bool(x.success):return x
 if String(state.get("construct_id",""))!=String(record.construct_id) or String(state.get("checksum",""))!=String(record.construct_checksum):return P.failure("CONSTRUCTION_AUTHORITY_INITIAL_STATE_MISMATCH")
 var owner=String(record.owner_server_id)
 if not _server_available(owner):return P.failure("CONSTRUCTION_AUTHORITY_OWNER_UNAVAILABLE")
 x=_servers[owner].gateway.import_construct_state(state);if not bool(x.success):return x
 x=_registry.publish(record);if not bool(x.success):return x
 _sync_replicas(String(record.construct_id));return x
func register_replica(construct_id:String,server_id:String)->Dictionary:
 if not _servers.has(server_id):return P.failure("CONSTRUCTION_AUTHORITY_SERVER_NOT_FOUND")
 var record=_registry.get_record(construct_id);if record.is_empty():return P.failure("CONSTRUCTION_AUTHORITY_RECORD_NOT_FOUND")
 var replica=Replica.new();var x=replica.configure(server_id);if not bool(x.success):return x
 _replicas[_replica_key(construct_id,server_id)]=replica
 return _sync_replica(construct_id,server_id)
func get_replica(construct_id:String,server_id:String):return _replicas.get(_replica_key(construct_id,server_id))
func get_registry():return _registry
func submit(entry_server_id:String,routed_command:Dictionary)->Dictionary:
 var x=Command.validate(routed_command);if not bool(x.success):return x
 if not _server_available(entry_server_id):return P.failure("CONSTRUCTION_AUTHORITY_ENTRY_SERVER_UNAVAILABLE")
 var inner:Dictionary=routed_command.command;var construct_id=String(inner.construct_id);var record=_registry.get_record(construct_id)
 if record.is_empty():return P.failure("CONSTRUCTION_AUTHORITY_RECORD_NOT_FOUND")
 if String(record.state)!=Record.ACTIVE:return P.failure("CONSTRUCTION_AUTHORITY_MIGRATION_FENCED")
 var owner=String(record.owner_server_id)
 if not _server_available(owner):return P.failure("CONSTRUCTION_AUTHORITY_OWNER_UNAVAILABLE")
 if int(routed_command.authority_epoch)!=int(record.authority_epoch) or String(routed_command.expected_owner_server_id)!=owner:
  if _servers[owner].gateway.has_method("has_terminal_command") and bool(_servers[owner].gateway.has_terminal_command(String(inner.command_id),String(inner.checksum))):
   var terminal_replay:Dictionary=_servers[owner].gateway.submit(inner)
   if bool(terminal_replay.get("success",false)):return P.success({"forwarded":entry_server_id!=owner,"entry_server_id":entry_server_id,"owner_server_id":owner,"authority_epoch":int(record.authority_epoch),"gateway_result":terminal_replay,"record":record,"cross_epoch_replay":true})
  if int(routed_command.authority_epoch)!=int(record.authority_epoch):return P.failure("CONSTRUCTION_AUTHORITY_EPOCH_MISMATCH",{"current_authority_epoch":int(record.authority_epoch),"owner_server_id":owner})
  return P.failure("CONSTRUCTION_AUTHORITY_OWNER_MISMATCH",{"owner_server_id":owner})
 var result:Dictionary=_servers[owner].gateway.submit(inner)
 if not bool(result.get("success",false)):return result
 var new_checksum=String(_servers[owner].gateway.get_construct_checksum(construct_id))
 var refreshed:Dictionary=_registry.refresh_checksum(construct_id,owner,int(record.authority_epoch),new_checksum,maxi(int(record.lease_expires_tick),_tick+10));if not bool(refreshed.success):return refreshed
 _sync_replicas(construct_id)
 return P.success({"forwarded":entry_server_id!=owner,"entry_server_id":entry_server_id,"owner_server_id":owner,"authority_epoch":int(record.authority_epoch),"gateway_result":result.duplicate(true),"record":refreshed.record})
func begin_migration(plan:Dictionary)->Dictionary:
 var x=Plan.validate(plan);if not bool(x.success):return x
 if not _server_available(String(plan.source_server_id)) or not _servers.has(String(plan.target_server_id)):return P.failure("CONSTRUCTION_AUTHORITY_MIGRATION_SERVER_UNAVAILABLE")
 x=_registry.begin_migration(plan);if not bool(x.success):return x
 var exported:Dictionary=_servers[String(plan.source_server_id)].gateway.export_construct_state(String(plan.construct_id));if not bool(exported.get("success",false)):_registry.abort_migration(plan);return exported
 var handoff=Handoff.create("authority-transfer/%s"%String(plan.migration_id).trim_prefix("authority-migration/"),plan,Dictionary(exported.state),Array(exported.get("terminal_operations",[])),_tick)
 _pending[String(plan.migration_id)]={"handoff":handoff,"installed":false};return P.success({"record":x.record,"handoff":handoff})
func install_migration(handoff:Dictionary)->Dictionary:
 var x=Handoff.validate(handoff);if not bool(x.success):return x
 var plan:Dictionary=handoff.migration_plan;var id=String(plan.migration_id)
 if not _pending.has(id) or String(_pending[id].handoff.checksum)!=String(handoff.checksum):return P.failure("CONSTRUCTION_AUTHORITY_HANDOFF_NOT_PENDING")
 if not _server_available(String(plan.target_server_id)):return P.failure("CONSTRUCTION_AUTHORITY_MIGRATION_TARGET_UNAVAILABLE")
 x=_servers[String(plan.target_server_id)].gateway.import_construct_state(Dictionary(handoff.construct_state),Array(handoff.terminal_operations));if not bool(x.success):return x
 _pending[id].installed=true;return P.success()
func commit_migration(plan:Dictionary,lease_expires_tick:int)->Dictionary:
 var x=Plan.validate(plan);if not bool(x.success):return x
 var id=String(plan.migration_id)
 if not _pending.has(id) or not bool(_pending[id].installed):return P.failure("CONSTRUCTION_AUTHORITY_HANDOFF_NOT_INSTALLED")
 var checksum=String(_servers[String(plan.target_server_id)].gateway.get_construct_checksum(String(plan.construct_id)))
 x=_registry.commit_migration(plan,checksum,lease_expires_tick);if not bool(x.success):return x
 _pending.erase(id);_sync_replicas(String(plan.construct_id));return x
func abort_migration(plan:Dictionary)->Dictionary:
 _pending.erase(String(plan.get("migration_id","")));return _registry.abort_migration(plan)
func register_split_child(parent_construct_id:String,child_record:Dictionary,child_state:Dictionary)->Dictionary:
 var x=Record.validate(child_record);if not bool(x.success):return x
 var owner=String(child_record.owner_server_id)
 if not _server_available(owner):return P.failure("CONSTRUCTION_AUTHORITY_SPLIT_TARGET_UNAVAILABLE")
 x=_servers[owner].gateway.import_construct_state(child_state);if not bool(x.success):return x
 x=_registry.register_split_child(parent_construct_id,child_record);if not bool(x.success):return x
 _sync_replicas(String(child_record.construct_id));return x
func takeover(construct_id:String,target_server_id:String,current_tick:int,new_lease_expires_tick:int)->Dictionary:
 if current_tick!=_tick:return P.failure("CONSTRUCTION_AUTHORITY_TAKEOVER_TICK_MISMATCH")
 var current=_registry.get_record(construct_id)
 if current.is_empty():return P.failure("CONSTRUCTION_AUTHORITY_RECORD_NOT_FOUND")
 if _server_available(String(current.owner_server_id)):return P.failure("CONSTRUCTION_AUTHORITY_OWNER_STILL_AVAILABLE")
 if not _server_available(target_server_id):return P.failure("CONSTRUCTION_AUTHORITY_TAKEOVER_TARGET_UNAVAILABLE")
 var replica=get_replica(construct_id,target_server_id)
 if replica==null:return P.failure("CONSTRUCTION_AUTHORITY_TAKEOVER_REPLICA_REQUIRED")
 var replica_state:Dictionary=replica.get_state();if replica_state.is_empty():return P.failure("CONSTRUCTION_AUTHORITY_TAKEOVER_REPLICA_REQUIRED")
 var imported:Dictionary=_servers[target_server_id].gateway.import_construct_state(Dictionary(replica_state.state_bundle));if not bool(imported.success):return imported
 var x=_registry.takeover(construct_id,target_server_id,String(_servers[target_server_id].cell_id),current_tick,String(replica_state.construct_checksum),new_lease_expires_tick);if not bool(x.success):return x
 _sync_replicas(construct_id);return x
func authorize_cross_zone_transfer(transfer:Dictionary)->Dictionary:
 var x=CrossZoneTransfer.validate(transfer);if not bool(x.success):return x
 var source=_registry.get_record(String(transfer.source_construct_id));var target=_registry.get_record(String(transfer.target_construct_id))
 if source.is_empty() or target.is_empty():return P.failure("CONSTRUCTION_CROSS_ZONE_TRANSFER_AUTHORITY_NOT_FOUND")
 if String(source.state)!=Record.ACTIVE or String(target.state)!=Record.ACTIVE:return P.failure("CONSTRUCTION_CROSS_ZONE_TRANSFER_AUTHORITY_FENCED")
 if int(transfer.authority_epoch)!=int(source.authority_epoch):return P.failure("CONSTRUCTION_CROSS_ZONE_TRANSFER_EPOCH_MISMATCH")
 if String(source.owner_server_id)!=String(transfer.source_server_id) or String(target.owner_server_id)!=String(transfer.target_server_id):return P.failure("CONSTRUCTION_CROSS_ZONE_TRANSFER_OWNER_MISMATCH")
 if String(source.owner_cell_id)!=String(transfer.source_cell_id) or String(target.owner_cell_id)!=String(transfer.target_cell_id):return P.failure("CONSTRUCTION_CROSS_ZONE_TRANSFER_CELL_MISMATCH")
 return P.success({"source_record":source,"target_record":target})
func export_state()->Dictionary:
 var keys:Array=_replicas.keys();keys.sort();var replicas:Array=[]
 for key in keys:replicas.append(_replicas[key].get_state())
 return AuthorityState.create(_registry.export_state(),replicas,_tick)
func load_state(state:Dictionary)->Dictionary:
 var checked=AuthorityState.validate(state);if not bool(checked.success):return checked
 var x=_registry.load_state(state.registry);if not bool(x.success):return x
 var next:Dictionary={}
 for row in state.replicas:
  var replica=Replica.new();x=replica.load_state(row);if not bool(x.success):return x
  next[_replica_key(String(row.construct_id),String(row.replica_server_id))]=replica
 _replicas=next;_tick=int(state.tick);return P.success()
func _sync_replicas(construct_id:String)->void:
 var record=_registry.get_record(construct_id)
 for server_id in record.get("replica_server_ids",[]):
  if _replicas.has(_replica_key(construct_id,String(server_id))):_sync_replica(construct_id,String(server_id))
func _sync_replica(construct_id:String,server_id:String)->Dictionary:
 var record=_registry.get_record(construct_id);if record.is_empty():return P.failure("CONSTRUCTION_AUTHORITY_RECORD_NOT_FOUND")
 var owner=String(record.owner_server_id);if not _server_available(owner):return P.failure("CONSTRUCTION_AUTHORITY_OWNER_UNAVAILABLE")
 var exported:Dictionary=_servers[owner].gateway.export_construct_state(construct_id);if not bool(exported.success):return exported
 return _replicas[_replica_key(construct_id,server_id)].apply(record,Dictionary(exported.state),_tick)
func _server_available(server_id:String)->bool:return _servers.has(server_id) and bool(_servers[server_id].available)
static func _replica_key(construct_id:String,server_id:String)->String:return "%s|%s"%[construct_id,server_id]
