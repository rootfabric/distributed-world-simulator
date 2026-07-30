extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.canonical_multiplayer_item_graph_service.v1"
const SNAPSHOT_SCHEMA := "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1"

var _configured := false
var _authority_owner_id := ""
var _authority_epoch := 0
var _revision := 0
var _tick := 0
var _items: Dictionary = {}
var _inventories: Dictionary = {}
var _containers: Dictionary = {}
var _mounts: Dictionary = {}
var _open_containers: Dictionary = {}
var _ledger: Dictionary = {}

func setup(authority_owner_id: String, authority_epoch: int) -> Dictionary:
	if _configured: return _failure("ITEM_GRAPH_ALREADY_CONFIGURED")
	if authority_owner_id.strip_edges().is_empty() or authority_epoch < 1: return _failure("INVALID_ITEM_GRAPH_AUTHORITY")
	_authority_owner_id = authority_owner_id.strip_edges(); _authority_epoch = authority_epoch
	_items = {
		"item/shared/beacon/1": {"item_id":"item/shared/beacon/1","definition_id":"item/beacon","quantity":1,"location":{"kind":"WORLD"},"mounted":false},
		"item/shared/ore/1": {"item_id":"item/shared/ore/1","definition_id":"item/ore","quantity":8,"location":{"kind":"WORLD"},"mounted":false},
		"item/shared/crate/1": {"item_id":"item/shared/crate/1","definition_id":"item/crate","quantity":1,"location":{"kind":"WORLD"},"mounted":false},
	}
	_containers = {"container/shared/crate/1":{"container_id":"container/shared/crate/1","owner_item_id":"item/shared/crate/1","capacity":8,"slots":[]}}
	_mounts = {"mount/shared/socket/1":{"mount_id":"mount/shared/socket/1","item_id":""}}
	_configured = true
	return _success({"snapshot":create_snapshot()})

func ensure_player(logical_player_id: String) -> void:
	var id := logical_player_id.strip_edges().to_lower()
	if id.is_empty(): return
	if not _inventories.has(id): _inventories[id] = {"inventory":[],"hotbar":[],"selected_hotbar_index":0}

func execute(logical_player_id: String, ownership_epoch: int, operation_id: String, command_type: String, payload: Dictionary) -> Dictionary:
	if not _configured: return _failure("ITEM_GRAPH_NOT_CONFIGURED")
	var player_id := logical_player_id.strip_edges().to_lower()
	if player_id.is_empty() or ownership_epoch < 1 or operation_id.strip_edges().is_empty(): return _failure("INVALID_ITEM_COMMAND")
	ensure_player(player_id)
	var fingerprint := Utils.payload_hash({"player":player_id,"epoch":ownership_epoch,"type":command_type,"payload":payload})
	if _ledger.has(operation_id):
		var old: Dictionary = _ledger[operation_id]
		if String(old.get("fingerprint","")) != fingerprint: return _failure("OPERATION_REPLAY_CONFLICT")
		var replay: Dictionary = Dictionary(old.get("result",{})).duplicate(true); replay["replay"] = true; return replay
	var result := _execute(player_id, command_type, payload)
	if bool(result.get("success",false)):
		_revision += 1; _tick += 1
		result["snapshot"] = create_snapshot(); result["revision"] = _revision; result["replay"] = false
	_ledger[operation_id] = {"fingerprint":fingerprint,"result":result.duplicate(true)}
	return result

func _execute(player_id: String, command_type: String, payload: Dictionary) -> Dictionary:
	match command_type:
		"item.pickup": return _pickup(player_id, String(payload.get("item_id","")))
		"item.drop": return _drop(player_id, String(payload.get("item_id","")), int(payload.get("quantity",-1)))
		"item.split": return _split(player_id, String(payload.get("item_id","")), int(payload.get("quantity",0)))
		"item.stack": return _stack(player_id, String(payload.get("source_item_id","")), String(payload.get("target_item_id","")))
		"container.open": return _open_container(player_id, String(payload.get("container_id","")))
		"container.close": return _close_container(player_id, String(payload.get("container_id","")))
		"item.move_to_container": return _move_to_container(player_id, String(payload.get("item_id","")), String(payload.get("container_id","")))
		"item.mount": return _mount(player_id, String(payload.get("item_id","")), String(payload.get("mount_id","")))
		"item.detach": return _detach(player_id, String(payload.get("mount_id","")))
		"inventory.select_hotbar": return _select_hotbar(player_id, int(payload.get("selected_hotbar_index",0)))
		"inventory.permission_probe":
			return _success() if String(payload.get("target_player_id","")) == player_id else _failure("PLAYER_PERMISSION_DENIED")
	return _failure("UNSUPPORTED_ITEM_COMMAND")

func _pickup(player_id:String,item_id:String)->Dictionary:
	if not _items.has(item_id): return _failure("ITEM_NOT_FOUND")
	var item:Dictionary=_items[item_id]
	if String(item.get("location",{}).get("kind",""))!="WORLD": return _failure("ITEM_ALREADY_CLAIMED")
	item["location"]={"kind":"INVENTORY","player_id":player_id}; _items[item_id]=item
	var inv:Dictionary=_inventories[player_id]; var list:Array=inv["inventory"]
	if item_id not in list:list.append(item_id)
	inv["inventory"]=list; _inventories[player_id]=inv
	return _success({"item_id":item_id,"winner_player_id":player_id})

func _drop(player_id:String,item_id:String,quantity:int)->Dictionary:
	var access:=_owned_item(player_id,item_id); if not bool(access.get("success",false)): return access
	var item:Dictionary=_items[item_id]; var q:=int(item.get("quantity",1)); var amount:=q if quantity<0 else quantity
	if amount<1 or amount>q:return _failure("INVALID_SPLIT_QUANTITY")
	if amount==q:
		_remove_from_inventory(player_id,item_id); item["location"]={"kind":"WORLD"}; _items[item_id]=item; return _success({"item_id":item_id})
	item["quantity"]=q-amount; _items[item_id]=item
	var new_id:="%s/drop/%d"%[item_id,_revision+1]; _items[new_id]={"item_id":new_id,"definition_id":item["definition_id"],"quantity":amount,"location":{"kind":"WORLD"},"mounted":false}
	return _success({"item_id":new_id})

func _split(player_id:String,item_id:String,quantity:int)->Dictionary:
	var access:=_owned_item(player_id,item_id); if not bool(access.get("success",false)): return access
	var item:Dictionary=_items[item_id]; var q:=int(item.get("quantity",1)); if quantity<1 or quantity>=q:return _failure("INVALID_SPLIT_QUANTITY")
	item["quantity"]=q-quantity; _items[item_id]=item
	var new_id:="%s/split/%d"%[item_id,_revision+1]; _items[new_id]={"item_id":new_id,"definition_id":item["definition_id"],"quantity":quantity,"location":{"kind":"INVENTORY","player_id":player_id},"mounted":false}
	var inv:Dictionary=_inventories[player_id]; var list:Array=inv["inventory"]; list.append(new_id); inv["inventory"]=list; _inventories[player_id]=inv
	return _success({"item_id":new_id})

func _stack(player_id:String,source_id:String,target_id:String)->Dictionary:
	var a:=_owned_item(player_id,source_id); if not bool(a.get("success",false)):return a
	var b:=_owned_item(player_id,target_id); if not bool(b.get("success",false)):return b
	if source_id==target_id:return _failure("STACK_TARGET_EQUALS_SOURCE")
	var source:Dictionary=_items[source_id]; var target:Dictionary=_items[target_id]
	if source.get("definition_id")!=target.get("definition_id"):return _failure("STACK_DEFINITION_MISMATCH")
	target["quantity"]=int(target["quantity"])+int(source["quantity"]); _items[target_id]=target; _items.erase(source_id); _remove_from_inventory(player_id,source_id)
	return _success({"item_id":target_id,"quantity":target["quantity"]})

func _open_container(player_id:String,container_id:String)->Dictionary:
	if not _containers.has(container_id):return _failure("CONTAINER_NOT_FOUND")
	_open_containers[player_id]=container_id; return _success({"container_id":container_id})
func _close_container(player_id:String,container_id:String)->Dictionary:
	if String(_open_containers.get(player_id,""))!=container_id:return _failure("EXTERNAL_CONTAINER_NOT_OPEN")
	_open_containers.erase(player_id); return _success({"container_id":container_id})
func _move_to_container(player_id:String,item_id:String,container_id:String)->Dictionary:
	var access:=_owned_item(player_id,item_id); if not bool(access.get("success",false)):return access
	if String(_open_containers.get(player_id,""))!=container_id:return _failure("TARGET_CONTAINER_ACCESS_DENIED")
	var c:Dictionary=_containers.get(container_id,{}); var slots:Array=c.get("slots",[]); if slots.size()>=int(c.get("capacity",0)):return _failure("CONTAINER_FULL")
	slots.append(item_id); c["slots"]=slots; _containers[container_id]=c; _remove_from_inventory(player_id,item_id)
	var item:Dictionary=_items[item_id]; item["location"]={"kind":"CONTAINER","container_id":container_id}; _items[item_id]=item
	return _success({"item_id":item_id,"container_id":container_id})
func _mount(player_id:String,item_id:String,mount_id:String)->Dictionary:
	var access:=_owned_item(player_id,item_id); if not bool(access.get("success",false)):return access
	if not _mounts.has(mount_id):return _failure("MOUNT_NOT_FOUND")
	var mount:Dictionary=_mounts[mount_id]; if not String(mount.get("item_id","")).is_empty():return _failure("MOUNT_OCCUPIED")
	mount["item_id"]=item_id; _mounts[mount_id]=mount; _remove_from_inventory(player_id,item_id)
	var item:Dictionary=_items[item_id]; item["location"]={"kind":"MOUNT","mount_id":mount_id,"owner_player_id":player_id}; item["mounted"]=true; _items[item_id]=item
	return _success({"item_id":item_id,"mount_id":mount_id})
func _detach(player_id:String,mount_id:String)->Dictionary:
	if not _mounts.has(mount_id):return _failure("MOUNT_NOT_FOUND")
	var mount:Dictionary=_mounts[mount_id]; var item_id:=String(mount.get("item_id","")); if item_id.is_empty():return _failure("MOUNT_EMPTY")
	var item:Dictionary=_items[item_id]; if String(item.get("location",{}).get("owner_player_id",""))!=player_id:return _failure("PLAYER_PERMISSION_DENIED")
	mount["item_id"]=""; _mounts[mount_id]=mount; item["location"]={"kind":"INVENTORY","player_id":player_id}; item["mounted"]=false; _items[item_id]=item
	var inv:Dictionary=_inventories[player_id]; var list:Array=inv["inventory"]; list.append(item_id); inv["inventory"]=list; _inventories[player_id]=inv
	return _success({"item_id":item_id})
func _select_hotbar(player_id:String,index:int)->Dictionary:
	if index<0 or index>7:return _failure("INVALID_HOTBAR_INDEX")
	var inv:Dictionary=_inventories[player_id]; inv["selected_hotbar_index"]=index; _inventories[player_id]=inv; return _success({"selected_hotbar_index":index})
func _owned_item(player_id:String,item_id:String)->Dictionary:
	if not _items.has(item_id):return _failure("ITEM_NOT_FOUND")
	var loc:Dictionary=_items[item_id].get("location",{}); return _success() if String(loc.get("kind",""))=="INVENTORY" and String(loc.get("player_id",""))==player_id else _failure("PLAYER_PERMISSION_DENIED")
func _remove_from_inventory(player_id:String,item_id:String)->void:
	var inv:Dictionary=_inventories[player_id]; var list:Array=inv["inventory"]; list.erase(item_id); inv["inventory"]=list; _inventories[player_id]=inv

func create_snapshot()->Dictionary:
	var body={"schema":SNAPSHOT_SCHEMA,"authority_owner_id":_authority_owner_id,"authority_epoch":_authority_epoch,"revision":_revision,"tick":_tick,"items":_sorted_values(_items),"inventories":_sorted_map(_inventories),"containers":_sorted_values(_containers),"mounts":_sorted_values(_mounts),"open_containers":_sorted_map(_open_containers)}
	body["checksum"]=Utils.payload_hash(body); return body
func validate_snapshot(snapshot:Dictionary)->Dictionary:
	if String(snapshot.get("schema",""))!=SNAPSHOT_SCHEMA:return _failure("INVALID_ITEM_GRAPH_SCHEMA")
	var copy:=snapshot.duplicate(true); var checksum:=String(copy.get("checksum","")); copy.erase("checksum")
	return _success() if checksum==Utils.payload_hash(copy) else _failure("CHECKSUM_MISMATCH")
func _sorted_values(source: Dictionary) -> Array:
	var keys := source.keys()
	keys.sort()
	var out: Array = []
	for key in keys:
		out.append(Dictionary(source[key]).duplicate(true))
	return out
func _sorted_map(source: Dictionary) -> Dictionary:
	var keys := source.keys()
	keys.sort()
	var out: Dictionary = {}
	for key in keys:
		var value = source[key]
		out[String(key)] = Dictionary(value).duplicate(true) if value is Dictionary else value
	return out
func _success(details:Dictionary={})->Dictionary:return {"success":true,"error_code":"","details":details.duplicate(true)}
func _failure(code:String)->Dictionary:return {"success":false,"error_code":code,"details":{}}
