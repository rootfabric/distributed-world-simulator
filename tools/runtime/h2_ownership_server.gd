extends SceneTree
const Support = preload("res://tools/runtime/h2_ownership_process_support.gd")
const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Port = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const Registry = preload("res://scripts/runtime/host_client/player_ownership_registry.gd")
var o: Dictionary; var boundary; var registry; var started:=0; var finished:=false
var joins:=0; var leaves:=0; var remote_entity:=""; var first_epoch:=0; var second_epoch:=0; var complete_since:=0
func _initialize() -> void:
	var p=Support.parse(OS.get_cmdline_user_args()); o=p.options
	if not p.success: _fail("INVALID_OPTIONS",{"errors":p.errors}); return
	registry=Registry.new(); if not registry.setup("simulation/h2/dedicated",2,1000).success: _fail("REGISTRY_SETUP_FAILED"); return
	var host=registry.join("host","transport-session/h2/host/1","operation/h2/host/join/1")
	if not host.success: _fail("HOST_JOIN_FAILED"); return
	boundary=Boundary.new(); var c=boundary.configure(Port.new(),262144,32,1048576)
	if not c.success: _fail(c.error_code); return
	var s=boundary.start_server(Support.endpoint(o,true)); if not s.success: _fail(s.error_code); return
	started=Time.get_ticks_msec(); Support.write(o.result_file,{"state":"LISTENING","passed":false,"port":o.port})
func _process(_d: float) -> bool:
	if finished:return false
	var polled=boundary.poll_events(64); if not polled.success:_fail(polled.error_code);return false
	for event in polled.details.events:
		var type:=String(event.event_type); var peer:=String(event.peer_id); var sid:=String(event.session_id)
		if type=="MESSAGE_RECEIVED": _message(peer,sid,event.frame.payload)
		elif type=="PEER_DISCONNECTED": registry.leave_transport_session(sid,"operation/h2/disconnect/%s"%sid.sha256_text().left(12))
	if joins==2 and leaves==1:
		var r=registry.get_report()
		if int(r.player_count)==2 and int(r.connected_count) >= 1 and second_epoch==2:
			if complete_since == 0: complete_since = Time.get_ticks_msec()
			if int(boundary.get_snapshot().get("outbound_pending_messages", 0)) == 0 and Time.get_ticks_msec() - complete_since >= 250: _success(); return false
	if Time.get_ticks_msec()-started>int(o.timeout_ms):_fail("SERVER_TIMEOUT",registry.get_report())
	return false
func _message(peer:String,sid:String,payload:Dictionary)->void:
	var kind:=String(payload.get("type","")); var op:=String(payload.get("operation_id",""))
	if kind=="JOIN":
		var result=registry.join(String(payload.get("logical_player_id","")),sid,op)
		if not result.success:_send(peer,"REJECT",{"error_code":result.error_code});return
		joins+=1; var player:Dictionary=result.details.player
		if remote_entity.is_empty(): remote_entity=player.player_entity_id; first_epoch=int(player.ownership_epoch)
		else: second_epoch=int(player.ownership_epoch)
		_send(peer,"OWNERSHIP_SNAPSHOT",{"snapshot":registry.create_snapshot(),"player":player})
	elif kind=="LEAVE":
		var result=registry.leave(String(payload.get("logical_player_id","")),sid,op)
		if not result.success:_send(peer,"REJECT",{"error_code":result.error_code});return
		leaves+=1; _send(peer,"LEAVE_ACK",{"snapshot":registry.create_snapshot()})
func _ready(peer:String)->bool:
	var state:=String(boundary.get_peer_snapshot(peer).get("state",""))
	if state=="READY":return true
	for method in ["mark_peer_handshaking","mark_peer_synchronizing","mark_peer_ready"]:
		var r=boundary.call(method,peer); if not r.success and String(r.error_code)!="INVALID_PEER_STATE_TRANSITION":return false
	return true
func _send(peer:String,kind:String,data:Dictionary)->void:
	if not _ready(peer):_fail("PEER_READY_FAILED");return
	var payload=data.duplicate(true);payload["type"] = kind
	var f=boundary.create_frame_for_peer(peer,"STATE","planet_simulator.h2.ownership_message.v1",payload)
	if not f.success:_fail(f.error_code);return
	var s=boundary.send_to_peer(peer,f.details.frame);if not s.success:_fail(s.error_code)
func _success()->void:
	var report={"schema":"planet_simulator.h2_ownership_server_report.v1","checkpoint":Support.CHECKPOINT,"build_id":Support.BUILD_ID,"state":"COMPLETE","passed":true,"joins":joins,"leaves":leaves,"remote_player_entity_id":remote_entity,"first_ownership_epoch":first_epoch,"second_ownership_epoch":second_epoch,"registry":registry.get_report()}
	Support.write(o.result_file,report);finished=true;print("H2_SERVER_RESULT %s"%JSON.stringify(report));quit(0)
func _fail(code:String,details:Dictionary={})->void:
	if finished:return
	var report={"state":"FAILED","passed":false,"failure_code":code,"details":details};if o!=null and not String(o.get("result_file","")).is_empty():Support.write(o.result_file,report)
	finished=true;push_error(code);quit(1)
func _finalize()->void:
	if boundary!=null:boundary.stop()
