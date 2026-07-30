extends SceneTree
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const ItemGraph = preload("res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd")
var failures:Array[String]=[]
var assertions:=0
func _init()->void:
	var service=Service.new()
	_assert(bool(service.setup("authority/m4",1,0,{"profile":Service.PROFILE_MULTIPLAYER_CORE,"topology_adapter":"ENET","region_id":"region/m4"}).get("success",false)),"service setup")
	_assert(bool(service.join("a","transport-session/m4/a/1","operation/m4/join/a").get("success",false)),"A join")
	_assert(bool(service.join("b","transport-session/m4/b/1","operation/m4/join/b").get("success",false)),"B join")
	var a=service.handle_canonical_item_command("a","transport-session/m4/a/1",1,"operation/m4/contention/a","item.pickup",{"item_id":"item/shared/beacon/1"})
	var b=service.handle_canonical_item_command("b","transport-session/m4/b/1",1,"operation/m4/contention/b","item.pickup",{"item_id":"item/shared/beacon/1"})
	_assert(bool(a.get("success",false)),"A wins canonical contention")
	_assert(String(b.get("error_code",""))=="ITEM_ALREADY_CLAIMED","B deterministic contention rejection")
	var snapshot:Dictionary=service.create_canonical_item_graph_snapshot()
	_assert(bool(service.validate_canonical_item_graph_snapshot(snapshot).get("success",false)),"snapshot checksum valid")
	_assert(_count_item(snapshot,"item/shared/beacon/1")==1,"canonical graph contains one beacon")
	_assert(_inventory_has(snapshot,"a","item/shared/beacon/1"),"winner inventory contains beacon")
	_assert(not _inventory_has(snapshot,"b","item/shared/beacon/1"),"loser inventory excludes beacon")
	var spoof=service.handle_canonical_item_command("b","transport-session/m4/b/1",1,"operation/m4/spoof","inventory.permission_probe",{"target_player_id":"a"})
	_assert(String(spoof.get("error_code",""))=="PLAYER_PERMISSION_DENIED","foreign inventory denied")
	var ore=service.handle_canonical_item_command("a","transport-session/m4/a/1",1,"operation/m4/ore","item.pickup",{"item_id":"item/shared/ore/1"})
	_assert(bool(ore.get("success",false)),"ore pickup")
	var split=service.handle_canonical_item_command("a","transport-session/m4/a/1",1,"operation/m4/split","item.split",{"item_id":"item/shared/ore/1","quantity":3})
	_assert(bool(split.get("success",false)),"stack split")
	var split_id=String(split.get("details",{}).get("item_id","")); _assert(not split_id.is_empty(),"split item identity")
	var stack=service.handle_canonical_item_command("a","transport-session/m4/a/1",1,"operation/m4/stack","item.stack",{"source_item_id":split_id,"target_item_id":"item/shared/ore/1"})
	_assert(bool(stack.get("success",false)),"stack merge")
	var drop=service.handle_canonical_item_command("a","transport-session/m4/a/1",1,"operation/m4/drop","item.drop",{"item_id":"item/shared/ore/1","quantity":2})
	_assert(bool(drop.get("success",false)),"partial drop")
	var dropped_id=String(drop.get("details",{}).get("item_id","")); _assert(not dropped_id.is_empty(),"dropped item identity")
	_assert(bool(service.handle_canonical_item_command("a","transport-session/m4/a/1",1,"operation/m4/repick","item.pickup",{"item_id":dropped_id}).get("success",false)),"repick dropped item")
	var mount=service.handle_canonical_item_command("a","transport-session/m4/a/1",1,"operation/m4/mount","item.mount",{"item_id":"item/shared/beacon/1","mount_id":"mount/shared/socket/1"})
	_assert(bool(mount.get("success",false)),"mount")
	_assert(bool(service.handle_canonical_item_command("a","transport-session/m4/a/1",1,"operation/m4/detach","item.detach",{"mount_id":"mount/shared/socket/1"}).get("success",false)),"detach")
	_assert(bool(service.handle_canonical_item_command("a","transport-session/m4/a/1",1,"operation/m4/open","container.open",{"container_id":"container/shared/crate/1"}).get("success",false)),"container open")
	_assert(bool(service.handle_canonical_item_command("a","transport-session/m4/a/1",1,"operation/m4/move-container","item.move_to_container",{"item_id":"item/shared/beacon/1","container_id":"container/shared/crate/1"}).get("success",false)),"move to external container")
	_assert(bool(service.handle_canonical_item_command("a","transport-session/m4/a/1",1,"operation/m4/close","container.close",{"container_id":"container/shared/crate/1"}).get("success",false)),"container close")
	var op="operation/m4/replay"
	var first=service.handle_canonical_item_command("a","transport-session/m4/a/1",1,op,"inventory.select_hotbar",{"selected_hotbar_index":2})
	var replay=service.handle_canonical_item_command("a","transport-session/m4/a/1",1,op,"inventory.select_hotbar",{"selected_hotbar_index":2})
	var conflict=service.handle_canonical_item_command("a","transport-session/m4/a/1",1,op,"inventory.select_hotbar",{"selected_hotbar_index":4})
	_assert(bool(first.get("success",false)),"first operation")
	_assert(bool(replay.get("replay",false)),"operation replay safe")
	_assert(String(conflict.get("error_code",""))=="OPERATION_REPLAY_CONFLICT","changed replay rejected")
	_assert(not bool(service.handle_canonical_item_command("a","transport-session/m4/b/1",1,"operation/m4/wrong-session","inventory.select_hotbar",{"selected_hotbar_index":1}).get("success",true)),"transport ownership fenced")
	service.shutdown(); _finish()
func _count_item(snapshot:Dictionary,id:String)->int:
	var n:=0
	for item in snapshot.get("items",[]):
		if String(item.get("item_id",""))==id:n+=1
	return n
func _inventory_has(snapshot:Dictionary,player:String,id:String)->bool:
	return id in Array(snapshot.get("inventories",{}).get(player,{}).get("inventory",[]))
func _assert(ok:bool,msg:String)->void:
	assertions+=1
	if ok: print("PASS: %s"%msg)
	else: failures.append(msg); push_error("FAIL: %s"%msg)
func _finish()->void:
	print("M4 canonical shared gameplay contracts: %d assertions, %d failures"%[assertions,failures.size()]); quit(0 if failures.is_empty() else 1)
