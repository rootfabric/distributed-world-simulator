extends Node3D

signal finished(exit_code: int)
const Contract = preload("res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_contract.gd")
const Topology = preload("res://scripts/runtime/seamless/sm0/sm0_p7_three_authority_topology.gd")
const STOP_POLL_INTERVAL_MS := 100

var _listen_host := "127.0.0.1"
var _listen_port := 0
var _stop_file := ""
var _socket: PacketPeerUDP
var _last_stop_poll_ms := 0
var _last_view: Dictionary = {}
var _frame_count := 0
var _owner_change_count := 0
var _reject_count := 0
var _ship: MeshInstance3D
var _player: MeshInstance3D
var _ship_visual_instance_id := 0
var _player_visual_instance_id := 0
var _label: Label

func setup(config: Dictionary) -> Dictionary:
	_listen_host = String(config.get("listen_host","127.0.0.1")).strip_edges(); _listen_port = int(config.get("listen_port",0)); _stop_file = String(config.get("stop_file","")).strip_edges()
	if _listen_host.is_empty() or _listen_port < 1: return _failure("SM0_P8_VISUAL_CONFIGURATION_INVALID")
	_socket = PacketPeerUDP.new(); var bind_result := _socket.bind(_listen_port,_listen_host)
	if bind_result != OK: return _failure("SM0_P8_VISUAL_BIND_FAILED", {"error":bind_result})
	_build_scene(); set_process(true)
	_event("SM0_P8_VISUAL_READY", {"listen_port":_listen_port,"command_channel":false,"ship_visual_instance_id":_ship_visual_instance_id,"player_visual_instance_id":_player_visual_instance_id})
	return _success()

func _build_scene() -> void:
	_ship = MeshInstance3D.new(); _ship.name="PersistentShip01"; var ship_mesh:=BoxMesh.new(); ship_mesh.size=Vector3(4.0,0.8,2.0); _ship.mesh=ship_mesh
	var ship_material:=StandardMaterial3D.new(); ship_material.albedo_color=Color(1.0,1.0,1.0); _ship.material_override=ship_material; add_child(_ship)
	_player = MeshInstance3D.new(); _player.name="PersistentPlayerA"; var player_mesh:=CapsuleMesh.new(); player_mesh.radius=0.25; player_mesh.height=1.0; _player.mesh=player_mesh
	var player_material:=StandardMaterial3D.new(); player_material.albedo_color=Color(1.0,0.8,0.15); _player.material_override=player_material; add_child(_player)
	_ship_visual_instance_id = _ship.get_instance_id(); _player_visual_instance_id = _player.get_instance_id()
	var camera:=Camera3D.new(); camera.position=Vector3(0.0,8.0,12.0); camera.look_at_from_position(camera.position,Vector3.ZERO,Vector3.UP); add_child(camera)
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-55.0,-25.0,0.0); add_child(light)
	_label=Label.new(); _label.position=Vector2(20,20); _label.text="P8 Moving Nested Authority Island"; add_child(_label)

func _process(_delta: float) -> void:
	_poll_socket(); var now:=Time.get_ticks_msec()
	if not _stop_file.is_empty() and now-_last_stop_poll_ms>=STOP_POLL_INTERVAL_MS:
		_last_stop_poll_ms=now
		if FileAccess.file_exists(_stop_file): shutdown(0,"stop-file")

func accept_view_for_tests(view: Dictionary) -> Dictionary: return _accept_view(view)
func _poll_socket() -> void:
	if _socket==null:return
	while _socket.get_available_packet_count()>0:
		var decoded=JSON.parse_string(_socket.get_packet().get_string_from_utf8())
		if not decoded is Dictionary: _reject("SM0_P8_VIEW_JSON_INVALID",{}); continue
		_accept_view(Dictionary(decoded))

func _accept_view(view: Dictionary) -> Dictionary:
	var validation:=Contract.validate_view(view)
	if not bool(validation.get("success",false)): return _reject(String(validation.get("error_code","SM0_P8_VIEW_INVALID")),view)
	if not _last_view.is_empty():
		var current_sequence:=int(_last_view.get("view_sequence",0)); var incoming_sequence:=int(view.get("view_sequence",0))
		if incoming_sequence<current_sequence:return _reject("SM0_P8_VIEW_STALE",view)
		if incoming_sequence==current_sequence:
			if String(view.get("checksum",""))!=String(_last_view.get("checksum","")):return _reject("SM0_P8_VIEW_SAME_SEQUENCE_MUTATION",view)
			return _success({"replay":true})
	var previous_owner:=String(Dictionary(_last_view.get("anchor",{})).get("outer_owner_authority_id","")); _last_view=view.duplicate(true); _frame_count+=1
	var anchor:=Dictionary(view.get("anchor",{})); var owner:=String(anchor.get("outer_owner_authority_id",""))
	if not previous_owner.is_empty() and owner!=previous_owner:
		_owner_change_count+=1; _event("SM0_P8_VISUAL_OUTER_OWNER_CHANGED", {"previous_outer_owner_authority_id":previous_owner,"outer_owner_authority_id":owner,"outer_authority_epoch":int(anchor.get("outer_authority_epoch",0)),"ship_visual_instance_id":_ship_visual_instance_id,"player_visual_instance_id":_player_visual_instance_id})
	_apply_view(view)
	_event("SM0_P8_VISUAL_FRAME", {"view_sequence":int(view.get("view_sequence",0)),"outer_owner_authority_id":owner,"outer_authority_epoch":int(anchor.get("outer_authority_epoch",0)),"ship_simulation_tick":int(anchor.get("simulation_tick",0)),"ship_world_position":anchor.get("world_position",{}),"ship_linear_velocity":anchor.get("linear_velocity",{}),"player_entity_id":String(Dictionary(view.get("player",{})).get("player_entity_id","")),"player_local_position":Dictionary(view.get("player",{})).get("position",{}),"player_world_position":view.get("player_world_position",{}),"inner_authority_id":String(view.get("inner_authority_id","")),"inner_authority_epoch":int(view.get("inner_authority_epoch",0)),"ship_visual_instance_id":_ship_visual_instance_id,"player_visual_instance_id":_player_visual_instance_id,"command_channel":false})
	return _success({"replay":false})

func _apply_view(view: Dictionary) -> void:
	if _ship==null or _player==null:return
	var anchor:=Dictionary(view.get("anchor",{})); var wp:=Dictionary(anchor.get("world_position",{})); var pp:=Dictionary(view.get("player_world_position",{}))
	_ship.position=Vector3(float(wp.get("x",0.0)),float(wp.get("y",0.0)),float(wp.get("z",0.0))); _ship.rotation.y=float(anchor.get("world_yaw",0.0))
	_player.position=Vector3(float(pp.get("x",0.0)),float(pp.get("y",0.0))+0.7,float(pp.get("z",0.0)))
	var material:=_ship.material_override as StandardMaterial3D
	if material!=null: material.albedo_color=Color(1.0,1.0,1.0) if String(anchor.get("outer_owner_authority_id",""))==Topology.AUTHORITY_A else Color(0.2,0.9,0.35)
	if _label!=null:_label.text="P8 Moving Nested Island\nOuter: %s epoch %d\nInner: %s epoch %d\nShip tick: %d\nplayer/a remains nested" % [String(anchor.get("outer_owner_authority_id","")),int(anchor.get("outer_authority_epoch",0)),String(view.get("inner_authority_id","")),int(view.get("inner_authority_epoch",0)),int(anchor.get("simulation_tick",0))]

func status_for_tests() -> Dictionary:
	return {"writer_count":0,"command_channel":false,"frame_count":_frame_count,"owner_change_count":_owner_change_count,"reject_count":_reject_count,"ship_visual_instance_id":_ship_visual_instance_id,"player_visual_instance_id":_player_visual_instance_id,"last_view":_last_view.duplicate(true)}
func shutdown(exit_code:int,reason:String)->void:
	_event("SM0_P8_VISUAL_EXIT",{"exit_code":exit_code,"reason":reason,"ship_visual_instance_id":_ship_visual_instance_id,"player_visual_instance_id":_player_visual_instance_id}); if _socket!=null:_socket.close(); set_process(false); finished.emit(exit_code)
func _reject(error_code:String,view:Dictionary)->Dictionary:
	_reject_count+=1; _event("SM0_P8_VISUAL_REJECTED",{"error_code":error_code,"view_sequence":int(view.get("view_sequence",0)),"ship_visual_instance_id":_ship_visual_instance_id,"player_visual_instance_id":_player_visual_instance_id}); return _failure(error_code)
func _event(event_name:String,details:Dictionary={})->void:
	var event={"schema":"distributed_world_simulator.sm0_event.v1","event":event_name,"severity":"INFO","process_role":"p8-observer","process_id":OS.get_process_id(),"time_msec":Time.get_ticks_msec(),"authority_id":"observer/sm0/p8","writer_count":0}
	for key in details.keys():event[key]=details[key]
	print("[SM0_EVENT] %s" % JSON.stringify(event,"",false,true))
static func _success(details:Dictionary={})->Dictionary:return {"success":true,"error_code":"","details":details.duplicate(true)}
static func _failure(error_code:String,details:Dictionary={})->Dictionary:return {"success":false,"error_code":error_code,"details":details.duplicate(true)}
