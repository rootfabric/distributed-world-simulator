extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.canonical_multiplayer_item_graph_service.v1"
const SNAPSHOT_SCHEMA := "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1"
const DURABLE_SCHEMA := "planet_simulator.canonical_multiplayer_item_graph_state.v1"
const REPLAY_SCHEMA := "planet_simulator.canonical_multiplayer_item_graph_replay.v1"

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
	_revision = 0; _tick = 0; _inventories.clear(); _open_containers.clear(); _ledger.clear()
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

func lookup_replay(logical_player_id: String, ownership_epoch: int, operation_id: String, command_type: String, payload: Dictionary) -> Dictionary:
	if operation_id.strip_edges().is_empty() or not _ledger.has(operation_id):
		return {"found": false, "conflict": false, "result": {}}
	var player_id := logical_player_id.strip_edges().to_lower()
	var fingerprint := Utils.payload_hash({"player": player_id, "epoch": ownership_epoch, "type": command_type, "payload": payload})
	var old: Dictionary = _ledger[operation_id]
	if String(old.get("fingerprint", "")) != fingerprint:
		return {"found": true, "conflict": true, "result": _failure("OPERATION_REPLAY_CONFLICT")}
	var replay: Dictionary = Dictionary(old.get("result", {})).duplicate(true)
	replay["replay"] = true
	var details: Dictionary = Dictionary(replay.get("details", {})).duplicate(true)
	details["replay"] = true
	replay["details"] = details
	return {"found": true, "conflict": false, "result": replay}

func execute(logical_player_id: String, ownership_epoch: int, operation_id: String, command_type: String, payload: Dictionary) -> Dictionary:
	if not _configured: return _failure("ITEM_GRAPH_NOT_CONFIGURED")
	var player_id := logical_player_id.strip_edges().to_lower()
	if player_id.is_empty() or ownership_epoch < 1 or operation_id.strip_edges().is_empty(): return _failure("INVALID_ITEM_COMMAND")
	ensure_player(player_id)
	var fingerprint := Utils.payload_hash({"player":player_id,"epoch":ownership_epoch,"type":command_type,"payload":payload})
	var replay_lookup := lookup_replay(player_id, ownership_epoch, operation_id, command_type, payload)
	if bool(replay_lookup.get("found", false)):
		return Dictionary(replay_lookup.get("result", {})).duplicate(true)
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
		"item.move_to_inventory": return _move_to_inventory(player_id, String(payload.get("item_id","")))
		"item.transfer": return _transfer(
			player_id,
			String(payload.get("item_id", "")),
			int(payload.get("quantity", -1)),
			String(payload.get("target_container_id", "")),
			int(payload.get("target_slot_index", -1)),
			String(payload.get("target_item_id", ""))
		)
		"item.mount": return _mount(player_id, String(payload.get("item_id","")), String(payload.get("mount_id","")))
		"item.detach": return _detach(player_id, String(payload.get("mount_id","")))
		"inventory.select_hotbar": return _select_hotbar(player_id, int(payload.get("selected_hotbar_index",0)))
		"inventory.assign_hotbar": return _assign_hotbar(
			player_id,
			String(payload.get("item_id", "")),
			int(payload.get("slot_index", -1))
		)
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
	return _transfer(player_id, item_id, -1, container_id, -1, "")

func _move_to_inventory(player_id: String, item_id: String) -> Dictionary:
	return _transfer(player_id, item_id, -1, "inventory/%s" % player_id, -1, "")

func _transfer(
	player_id: String,
	item_id: String,
	quantity: int,
	target_container_id: String,
	target_slot_index: int,
	target_item_id: String
) -> Dictionary:
	if not _items.has(item_id):
		return _failure("ITEM_NOT_FOUND")
	var access := _accessible_item(player_id, item_id)
	if not bool(access.get("success", false)):
		return access
	var source: Dictionary = _items[item_id]
	var source_quantity := int(source.get("quantity", 1))
	var amount := source_quantity if quantity < 0 else quantity
	if amount < 1 or amount > source_quantity:
		return _failure("INVALID_TRANSFER_QUANTITY")
	var normalized_target := target_container_id.strip_edges()
	if normalized_target.is_empty():
		return _failure("TARGET_CONTAINER_REQUIRED")
	if not target_item_id.strip_edges().is_empty():
		return _transfer_to_stack(player_id, item_id, amount, target_item_id.strip_edges())
	if normalized_target == "inventory/%s" % player_id:
		return _transfer_to_inventory(player_id, item_id, amount)
	if normalized_target == "hotbar/%s" % player_id:
		if amount != source_quantity:
			return _failure("HOTBAR_ASSIGNMENT_REQUIRES_WHOLE_ITEM")
		var location: Dictionary = source.get("location", {})
		if String(location.get("kind", "")) == "WORLD":
			var pickup_result := _transfer_to_inventory(player_id, item_id, source_quantity)
			if not bool(pickup_result.get("success", false)):
				return pickup_result
		elif String(location.get("kind", "")) != "INVENTORY" or String(location.get("player_id", "")) != player_id:
			return _failure("PLAYER_PERMISSION_DENIED")
		return _assign_hotbar(player_id, item_id, target_slot_index)
	if normalized_target.begins_with("container/"):
		return _transfer_to_container(player_id, item_id, amount, normalized_target, target_slot_index)
	return _failure("UNSUPPORTED_TRANSFER_TARGET")

func _transfer_to_inventory(player_id: String, item_id: String, amount: int) -> Dictionary:
	var item: Dictionary = _items[item_id]
	var location: Dictionary = item.get("location", {})
	var kind := String(location.get("kind", ""))
	if kind == "INVENTORY" and String(location.get("player_id", "")) == player_id:
		return _success({"item_id": item_id, "container_id": "inventory/%s" % player_id, "no_op": true})
	if kind == "CONTAINER":
		var source_container_id := String(location.get("container_id", ""))
		if String(_open_containers.get(player_id, "")) != source_container_id:
			return _failure("SOURCE_CONTAINER_ACCESS_DENIED")
	if kind == "MOUNT":
		return _failure("MOUNT_DETACH_REQUIRED")
	var moved_item_id := _extract_transfer_item(item_id, amount)
	if moved_item_id.is_empty():
		return _failure("INVALID_TRANSFER_QUANTITY")
	_remove_from_source(item_id if moved_item_id == item_id else "", location)
	var moved: Dictionary = _items[moved_item_id]
	moved["location"] = {"kind": "INVENTORY", "player_id": player_id}
	_items[moved_item_id] = moved
	_add_to_inventory(player_id, moved_item_id)
	return _success({"item_id": moved_item_id, "container_id": "inventory/%s" % player_id, "quantity": amount})

func _transfer_to_container(
	player_id: String,
	item_id: String,
	amount: int,
	container_id: String,
	target_slot_index: int
) -> Dictionary:
	if not _containers.has(container_id):
		return _failure("CONTAINER_NOT_FOUND")
	if String(_open_containers.get(player_id, "")) != container_id:
		return _failure("TARGET_CONTAINER_ACCESS_DENIED")
	var item: Dictionary = _items[item_id]
	var location: Dictionary = item.get("location", {})
	if String(location.get("kind", "")) == "CONTAINER" and String(location.get("container_id", "")) == container_id:
		return _success({"item_id": item_id, "container_id": container_id, "no_op": true})
	var container: Dictionary = _containers[container_id]
	var slots: Array = Array(container.get("slots", [])).duplicate()
	if slots.size() >= int(container.get("capacity", 0)):
		return _failure("CONTAINER_FULL")
	var moved_item_id := _extract_transfer_item(item_id, amount)
	if moved_item_id.is_empty():
		return _failure("INVALID_TRANSFER_QUANTITY")
	_remove_from_source(item_id if moved_item_id == item_id else "", location)
	var insertion_index := target_slot_index
	if insertion_index < 0 or insertion_index > slots.size():
		insertion_index = slots.size()
	slots.insert(insertion_index, moved_item_id)
	container["slots"] = slots
	_containers[container_id] = container
	var moved: Dictionary = _items[moved_item_id]
	moved["location"] = {"kind": "CONTAINER", "container_id": container_id}
	_items[moved_item_id] = moved
	return _success({"item_id": moved_item_id, "container_id": container_id, "quantity": amount, "target_slot_index": insertion_index})

func _transfer_to_stack(player_id: String, source_id: String, amount: int, target_id: String) -> Dictionary:
	if source_id == target_id:
		return _failure("STACK_TARGET_EQUALS_SOURCE")
	if not _items.has(target_id):
		return _failure("ITEM_NOT_FOUND")
	var target_access := _accessible_item(player_id, target_id)
	if not bool(target_access.get("success", false)):
		return target_access
	var source: Dictionary = _items[source_id]
	var target: Dictionary = _items[target_id]
	if String(source.get("definition_id", "")) != String(target.get("definition_id", "")):
		return _failure("STACK_DEFINITION_MISMATCH")
	var source_location: Dictionary = source.get("location", {})
	var target_location: Dictionary = target.get("location", {})
	if String(target_location.get("kind", "")) == "WORLD":
		return _failure("STACK_TARGET_NOT_ACCESSIBLE")
	target["quantity"] = int(target.get("quantity", 1)) + amount
	_items[target_id] = target
	if amount == int(source.get("quantity", 1)):
		_remove_from_source(source_id, source_location)
		_items.erase(source_id)
	else:
		source["quantity"] = int(source.get("quantity", 1)) - amount
		_items[source_id] = source
	return _success({"item_id": target_id, "quantity": int(target.get("quantity", 1)), "moved_quantity": amount})

func _extract_transfer_item(item_id: String, amount: int) -> String:
	var item: Dictionary = _items[item_id]
	var source_quantity := int(item.get("quantity", 1))
	if amount < 1 or amount > source_quantity:
		return ""
	if amount == source_quantity:
		return item_id
	item["quantity"] = source_quantity - amount
	_items[item_id] = item
	var new_id := "%s/transfer/%d" % [item_id, _revision + 1]
	var moved := item.duplicate(true)
	moved["item_id"] = new_id
	moved["quantity"] = amount
	_items[new_id] = moved
	return new_id

func _accessible_item(player_id: String, item_id: String) -> Dictionary:
	if not _items.has(item_id):
		return _failure("ITEM_NOT_FOUND")
	var location: Dictionary = _items[item_id].get("location", {})
	match String(location.get("kind", "")):
		"WORLD":
			return _success()
		"INVENTORY":
			return _success() if String(location.get("player_id", "")) == player_id else _failure("PLAYER_PERMISSION_DENIED")
		"CONTAINER":
			return _success() if String(_open_containers.get(player_id, "")) == String(location.get("container_id", "")) else _failure("SOURCE_CONTAINER_ACCESS_DENIED")
		"MOUNT":
			return _success() if String(location.get("owner_player_id", "")) == player_id else _failure("PLAYER_PERMISSION_DENIED")
	return _failure("ITEM_LOCATION_INVALID")

func _remove_from_source(item_id: String, location: Dictionary) -> void:
	if item_id.is_empty():
		return
	match String(location.get("kind", "")):
		"INVENTORY":
			_remove_from_inventory(String(location.get("player_id", "")), item_id)
		"CONTAINER":
			var container_id := String(location.get("container_id", ""))
			if _containers.has(container_id):
				var container: Dictionary = _containers[container_id]
				var slots: Array = Array(container.get("slots", [])).duplicate()
				slots.erase(item_id)
				container["slots"] = slots
				_containers[container_id] = container

func _add_to_inventory(player_id: String, item_id: String) -> void:
	ensure_player(player_id)
	var inventory: Dictionary = _inventories[player_id]
	var values: Array = Array(inventory.get("inventory", [])).duplicate()
	if item_id not in values:
		values.append(item_id)
	inventory["inventory"] = values
	_inventories[player_id] = inventory
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

func _assign_hotbar(player_id: String, item_id: String, slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index > 7:
		return _failure("INVALID_HOTBAR_INDEX")
	var access := _owned_item(player_id, item_id)
	if not bool(access.get("success", false)):
		return access
	var inventory: Dictionary = _inventories[player_id]
	var hotbar: Array = Array(inventory.get("hotbar", [])).duplicate()
	while hotbar.size() < 8:
		hotbar.append("")
	for index in range(hotbar.size()):
		if String(hotbar[index]) == item_id:
			hotbar[index] = ""
	hotbar[slot_index] = item_id
	inventory["hotbar"] = hotbar
	_inventories[player_id] = inventory
	return _success({"item_id": item_id, "slot_index": slot_index})

func _owned_item(player_id:String,item_id:String)->Dictionary:
	if not _items.has(item_id):return _failure("ITEM_NOT_FOUND")
	var loc:Dictionary=_items[item_id].get("location",{}); return _success() if String(loc.get("kind",""))=="INVENTORY" and String(loc.get("player_id",""))==player_id else _failure("PLAYER_PERMISSION_DENIED")

func _remove_from_inventory(player_id:String,item_id:String)->void:
	if not _inventories.has(player_id):
		return
	var inv:Dictionary=_inventories[player_id]
	var list:Array=Array(inv.get("inventory", [])).duplicate()
	list.erase(item_id)
	inv["inventory"]=list
	var hotbar: Array = Array(inv.get("hotbar", [])).duplicate()
	for index in range(hotbar.size()):
		if String(hotbar[index]) == item_id:
			hotbar[index] = ""
	inv["hotbar"] = hotbar
	_inventories[player_id]=inv

func export_durable_state() -> Dictionary:
	var snapshot := create_snapshot()
	snapshot["open_containers"] = {}
	snapshot["checksum"] = ""
	var snapshot_payload := snapshot.duplicate(true)
	snapshot_payload.erase("checksum")
	snapshot["checksum"] = Utils.payload_hash(snapshot_payload)
	var state: Dictionary = {"schema": DURABLE_SCHEMA, "snapshot": snapshot, "checksum": ""}
	state["checksum"] = _state_checksum(state)
	return state

func restore_durable_state(value: Dictionary) -> Dictionary:
	var validation := validate_durable_state(value)
	if not bool(validation.get("success", false)):
		return validation
	var snapshot: Dictionary = value.get("snapshot", {})
	var staged_items: Dictionary = {}
	for item_value in snapshot.get("items", []):
		var item: Dictionary = Dictionary(item_value).duplicate(true)
		staged_items[String(item.get("item_id", ""))] = item
	var staged_containers: Dictionary = {}
	for container_value in snapshot.get("containers", []):
		var container: Dictionary = Dictionary(container_value).duplicate(true)
		staged_containers[String(container.get("container_id", ""))] = container
	var staged_mounts: Dictionary = {}
	for mount_value in snapshot.get("mounts", []):
		var mount: Dictionary = Dictionary(mount_value).duplicate(true)
		staged_mounts[String(mount.get("mount_id", ""))] = mount
	_authority_owner_id = String(snapshot.get("authority_owner_id", ""))
	_authority_epoch = int(snapshot.get("authority_epoch", 0))
	_revision = int(snapshot.get("revision", 0))
	_tick = int(snapshot.get("tick", 0))
	_items = staged_items
	_inventories = Dictionary(snapshot.get("inventories", {})).duplicate(true)
	_containers = staged_containers
	_mounts = staged_mounts
	_open_containers.clear()
	_ledger.clear()
	_configured = true
	return _success({"revision": _revision, "tick": _tick, "item_count": _items.size()})

func validate_durable_state(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != DURABLE_SCHEMA or typeof(value.get("snapshot")) != TYPE_DICTIONARY:
		return _failure("INVALID_ITEM_GRAPH_DURABLE_STATE")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value.get("checksum", "")) != _state_checksum(value):
		return _failure("ITEM_GRAPH_DURABLE_CHECKSUM_MISMATCH")
	var snapshot: Dictionary = value.get("snapshot", {})
	for field in ["authority_owner_id", "authority_epoch", "revision", "tick", "items", "inventories", "containers", "mounts", "open_containers", "checksum"]:
		if not snapshot.has(field):
			return _failure("ITEM_GRAPH_DURABLE_FIELD_MISSING")
	if (
		typeof(snapshot.get("items")) != TYPE_ARRAY
		or typeof(snapshot.get("inventories")) != TYPE_DICTIONARY
		or typeof(snapshot.get("containers")) != TYPE_ARRAY
		or typeof(snapshot.get("mounts")) != TYPE_ARRAY
		or typeof(snapshot.get("open_containers")) != TYPE_DICTIONARY
	):
		return _failure("INVALID_ITEM_GRAPH_DURABLE_COLLECTIONS")
	var snapshot_validation := validate_snapshot(snapshot)
	if not bool(snapshot_validation.get("success", false)):
		return _failure("INVALID_ITEM_GRAPH_DURABLE_SNAPSHOT")
	if not Dictionary(snapshot.get("open_containers", {})).is_empty():
		return _failure("DURABLE_ITEM_GRAPH_ACCESS_STATE_MUST_BE_EMPTY")
	if String(snapshot.get("authority_owner_id", "")).strip_edges().is_empty():
		return _failure("INVALID_DURABLE_ITEM_AUTHORITY")
	if int(snapshot.get("authority_epoch", 0)) < 1 or int(snapshot.get("revision", -1)) < 0 or int(snapshot.get("tick", -1)) < 0:
		return _failure("INVALID_DURABLE_ITEM_REVISION")

	var item_records: Dictionary = {}
	for item_value in snapshot.get("items", []):
		if not item_value is Dictionary:
			return _failure("INVALID_DURABLE_ITEM_RECORD")
		var item: Dictionary = item_value
		var item_id := String(item.get("item_id", ""))
		var location_value = item.get("location", {})
		if (
			item_id.is_empty()
			or item_id != item_id.strip_edges().to_lower()
			or item_records.has(item_id)
			or String(item.get("definition_id", "")).is_empty()
			or int(item.get("quantity", 0)) < 1
			or typeof(item.get("mounted")) != TYPE_BOOL
			or not location_value is Dictionary
		):
			return _failure("INVALID_DURABLE_ITEM_RECORD")
		item_records[item_id] = item

	var referenced: Dictionary = {}
	var inventory_ids: Dictionary = {}
	var inventories_value = snapshot.get("inventories", {})
	if not inventories_value is Dictionary:
		return _failure("INVALID_DURABLE_INVENTORIES")
	for player_id_value in inventories_value.keys():
		var player_id := String(player_id_value)
		var inventory_value = inventories_value[player_id_value]
		if player_id.is_empty() or player_id != player_id.strip_edges().to_lower() or not inventory_value is Dictionary:
			return _failure("INVALID_DURABLE_INVENTORY")
		if inventory_ids.has(player_id):
			return _failure("DUPLICATE_DURABLE_INVENTORY")
		inventory_ids[player_id] = true
		var inventory_items_value = inventory_value.get("inventory", [])
		var hotbar_value = inventory_value.get("hotbar", [])
		if not inventory_items_value is Array or not hotbar_value is Array:
			return _failure("INVALID_DURABLE_INVENTORY")
		if int(inventory_value.get("selected_hotbar_index", -1)) < 0 or int(inventory_value.get("selected_hotbar_index", -1)) > 7:
			return _failure("INVALID_DURABLE_HOTBAR_SELECTION")
		var owned_items: Dictionary = {}
		for item_id_value in inventory_items_value:
			var item_id := String(item_id_value)
			if not item_records.has(item_id) or referenced.has(item_id) or owned_items.has(item_id):
				return _failure("INVALID_DURABLE_ITEM_REFERENCE")
			var location: Dictionary = Dictionary(item_records[item_id]).get("location", {})
			if String(location.get("kind", "")) != "INVENTORY" or String(location.get("player_id", "")) != player_id:
				return _failure("DURABLE_ITEM_LOCATION_MISMATCH")
			owned_items[item_id] = true
			referenced[item_id] = true
		if Array(hotbar_value).size() > 8:
			return _failure("INVALID_DURABLE_HOTBAR_SIZE")
		var hotbar_items: Dictionary = {}
		for hotbar_item_value in hotbar_value:
			var hotbar_item_id := String(hotbar_item_value)
			if hotbar_item_id.is_empty():
				continue
			if not owned_items.has(hotbar_item_id) or hotbar_items.has(hotbar_item_id):
				return _failure("INVALID_DURABLE_HOTBAR_REFERENCE")
			hotbar_items[hotbar_item_id] = true

	var container_ids: Dictionary = {}
	for container_value in snapshot.get("containers", []):
		if not container_value is Dictionary:
			return _failure("INVALID_DURABLE_CONTAINER")
		var container: Dictionary = container_value
		var container_id := String(container.get("container_id", ""))
		var slots_value = container.get("slots", [])
		if container_id.is_empty() or container_ids.has(container_id) or not slots_value is Array:
			return _failure("INVALID_DURABLE_CONTAINER")
		container_ids[container_id] = true
		var capacity := int(container.get("capacity", -1))
		if capacity < 0 or capacity < Array(slots_value).size():
			return _failure("DURABLE_CONTAINER_CAPACITY_EXCEEDED")
		var owner_item_id := String(container.get("owner_item_id", ""))
		if not owner_item_id.is_empty() and not item_records.has(owner_item_id):
			return _failure("DURABLE_CONTAINER_OWNER_MISSING")
		for item_id_value in slots_value:
			var item_id := String(item_id_value)
			if not item_records.has(item_id) or referenced.has(item_id):
				return _failure("INVALID_DURABLE_ITEM_REFERENCE")
			var location: Dictionary = Dictionary(item_records[item_id]).get("location", {})
			if String(location.get("kind", "")) != "CONTAINER" or String(location.get("container_id", "")) != container_id:
				return _failure("DURABLE_ITEM_LOCATION_MISMATCH")
			referenced[item_id] = true

	var mount_ids: Dictionary = {}
	for mount_value in snapshot.get("mounts", []):
		if not mount_value is Dictionary:
			return _failure("INVALID_DURABLE_MOUNT")
		var mount: Dictionary = mount_value
		var mount_id := String(mount.get("mount_id", ""))
		if mount_id.is_empty() or mount_ids.has(mount_id):
			return _failure("INVALID_DURABLE_MOUNT")
		mount_ids[mount_id] = true
		if typeof(mount.get("item_id")) != TYPE_STRING:
			return _failure("INVALID_DURABLE_MOUNT")
		var item_id := String(mount.get("item_id", ""))
		if item_id.is_empty():
			continue
		if not item_records.has(item_id) or referenced.has(item_id):
			return _failure("INVALID_DURABLE_ITEM_REFERENCE")
		var item: Dictionary = item_records[item_id]
		var location: Dictionary = item.get("location", {})
		if String(location.get("kind", "")) != "MOUNT" or String(location.get("mount_id", "")) != mount_id or not bool(item.get("mounted", false)):
			return _failure("DURABLE_ITEM_LOCATION_MISMATCH")
		var owner_player_id := String(location.get("owner_player_id", ""))
		if owner_player_id.is_empty() or not inventory_ids.has(owner_player_id):
			return _failure("DURABLE_MOUNT_OWNER_MISSING")
		referenced[item_id] = true

	for item_id_value in item_records.keys():
		var item_id := String(item_id_value)
		var item: Dictionary = item_records[item_id]
		var location: Dictionary = item.get("location", {})
		var kind := String(location.get("kind", ""))
		if kind == "WORLD":
			if referenced.has(item_id) or bool(item.get("mounted", false)):
				return _failure("DURABLE_WORLD_ITEM_REFERENCE_MISMATCH")
		elif kind in ["INVENTORY", "CONTAINER", "MOUNT"]:
			if not referenced.has(item_id):
				return _failure("DURABLE_ITEM_REFERENCE_MISSING")
			if kind != "MOUNT" and bool(item.get("mounted", false)):
				return _failure("DURABLE_ITEM_MOUNT_FLAG_MISMATCH")
		else:
			return _failure("INVALID_DURABLE_ITEM_LOCATION")

	var safe := Utils.canonicalize(value, "$.canonical_item_graph_state")
	if not bool(safe.get("success", false)):
		return _failure("ITEM_GRAPH_DURABLE_STATE_NOT_JSON_SAFE")
	return _success({"item_count": item_records.size(), "inventory_count": inventory_ids.size()})

func export_replay_state() -> Dictionary:
	var records: Dictionary = {}
	var operation_ids := _ledger.keys()
	operation_ids.sort()
	for operation_id_value in operation_ids:
		records[String(operation_id_value)] = Dictionary(_ledger[operation_id_value]).duplicate(true)
	var state: Dictionary = {"schema": REPLAY_SCHEMA, "records": records, "checksum": ""}
	state["checksum"] = _state_checksum(state)
	return state

func restore_replay_state(value: Dictionary) -> Dictionary:
	var validation := validate_replay_state(value)
	if not bool(validation.get("success", false)):
		return validation
	_ledger = Dictionary(value.get("records", {})).duplicate(true)
	return _success({"operation_count": _ledger.size()})

func validate_replay_state(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != REPLAY_SCHEMA or typeof(value.get("records")) != TYPE_DICTIONARY:
		return _failure("INVALID_ITEM_GRAPH_REPLAY_STATE")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value.get("checksum", "")) != _state_checksum(value):
		return _failure("ITEM_GRAPH_REPLAY_CHECKSUM_MISMATCH")
	for operation_id_value in value.get("records", {}).keys():
		var entry_value = value["records"][operation_id_value]
		if String(operation_id_value).is_empty() or not entry_value is Dictionary:
			return _failure("INVALID_ITEM_GRAPH_REPLAY_RECORD")
		var entry: Dictionary = entry_value
		if String(entry.get("fingerprint", "")).length() != 64 or typeof(entry.get("result")) != TYPE_DICTIONARY:
			return _failure("INVALID_ITEM_GRAPH_REPLAY_RECORD")
	var safe := Utils.canonicalize(value, "$.canonical_item_graph_replay")
	if not bool(safe.get("success", false)):
		return _failure("ITEM_GRAPH_REPLAY_NOT_JSON_SAFE")
	return _success({"operation_count": value.get("records", {}).size()})

func has_replay_operation(operation_id: String) -> bool:
	return not operation_id.is_empty() and _ledger.has(operation_id)


func get_replay_operation_count() -> int:
	return _ledger.size()

func _find_item(items: Array, item_id: String) -> Dictionary:
	for item_value in items:
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			return Dictionary(item_value)
	return {}

func _state_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("checksum")
	return Utils.payload_hash(payload)

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
