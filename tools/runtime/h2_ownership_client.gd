extends SceneTree
const Support=preload("res://tools/runtime/h2_ownership_process_support.gd")
const Boundary=preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Port=preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const Replica=preload("res://scripts/runtime/host_client/player_ownership_replica_store.gd")
var o:Dictionary;var boundary;var replica;var phase:=1;var peer:="peer/enet/server";var sid:="";var started:=0;var sent:=false;var finished:=false;var entity:="";var epoch1:=0;var epoch2:=0
func _initialize()->void:
	var p=Support.parse(OS.get_cmdline_user_args());o=p.options
	if not p.success:_fail("INVALID_OPTIONS");return
	replica=Replica.new();started=Time.get_ticks_msec();_connect_phase()
func _connect_phase()->void:
	boundary=Boundary.new();var c=boundary.configure(Port.new(),262144,16,524288);if not c.success:_fail(c.error_code);return
	sid="transport-session/h2/remote/%d"%phase;var r=boundary.connect_client(Support.endpoint(o),peer,sid,"route/h2/server/%d"%phase,phase);if not r.success:_fail(r.error_code);return
	sent=false
func _process(_d:float)->bool:
	if finished:return false
	var p=boundary.poll_events(32);if not p.success:_fail(p.error_code);return false
	if not sent and String(boundary.get_peer_snapshot(peer).get("state",""))=="TRANSPORT_CONNECTED":
		for method in ["mark_peer_handshaking","mark_peer_synchronizing","mark_peer_ready"]:
			var r=boundary.call(method,peer);if not r.success:_fail(r.error_code);return false
		_send("JOIN",{"logical_player_id":"remote","operation_id":"operation/h2/remote/join/%d"%phase});sent=true
	for e in p.details.events:
		if String(e.event_type)!="MESSAGE_RECEIVED":continue
		var payload:Dictionary=e.frame.payload;var kind:=String(payload.type)
		if kind=="OWNERSHIP_SNAPSHOT":
			var a=replica.accept_snapshot(payload.snapshot);if not a.success:_fail(a.error_code);return false
			var player:Dictionary=payload.player
			if phase==1:
				entity=player.player_entity_id;epoch1=int(player.ownership_epoch);_send("LEAVE",{"logical_player_id":"remote","operation_id":"operation/h2/remote/leave/1"})
			else:
				epoch2=int(player.ownership_epoch);if String(player.player_entity_id)!=entity:_fail("PLAYER_ID_CHANGED");return false
				_success();return false
		elif kind=="LEAVE_ACK":
			boundary.stop();phase=2;_connect_phase()
		elif kind=="REJECT":_fail(String(payload.get("error_code","REJECTED")))
	if Time.get_ticks_msec()-started>int(o.timeout_ms):_fail("CLIENT_TIMEOUT")
	return false
func _send(kind:String,data:Dictionary)->void:
	var payload=data.duplicate(true);payload["type"] = kind
	var f=boundary.create_frame_for_peer(peer,"COMMAND","planet_simulator.h2.ownership_message.v1",payload);if not f.success:_fail(f.error_code);return
	var s=boundary.send_to_peer(peer,f.details.frame);if not s.success:_fail(s.error_code)
func _success()->void:
	var report={"schema":"planet_simulator.h2_ownership_client_report.v1","checkpoint":Support.CHECKPOINT,"build_id":Support.BUILD_ID,"state":"COMPLETE","passed":true,"player_entity_id":entity,"first_ownership_epoch":epoch1,"second_ownership_epoch":epoch2,"replica":replica.get_report()}
	Support.write(o.result_file,report);finished=true;print("H2_CLIENT_RESULT %s"%JSON.stringify(report));quit(0)
func _fail(code:String)->void:
	if finished:return
	var report={"state":"FAILED","passed":false,"failure_code":code};if o!=null and not String(o.get("result_file","")).is_empty():Support.write(o.result_file,report)
	finished=true;push_error(code);quit(1)
func _finalize()->void:
	if boundary!=null:boundary.stop()
