extends SceneTree

const Contract = preload("res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_contract.gd")
const Topology = preload("res://scripts/runtime/seamless/sm0/sm0_p7_three_authority_topology.gd")
const Outer = preload("res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_outer_node.gd")
const Nested = preload("res://scripts/runtime/seamless/sm0/sm0_p8_nested_authority_node.gd")
const Observer = preload("res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_observer.gd")

const EXPECTED_ASSERTIONS := 96
var _assertions := 0
var _failed := false
var _nodes: Array[Node] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_contract_checks()
	if _failed: return _finish()

	var observer := Observer.new(); observer.name="Observer"; root.add_child(observer); _nodes.append(observer)
	_check_success(observer.setup({"listen_port":26414}), "observer setup")
	var nested := Nested.new(); nested.name="Nested"; root.add_child(nested); _nodes.append(nested)
	_check_success(nested.setup({"anchor_port":26413,"view_port":26414,"auto_local_motion":false}), "nested setup")
	var b := Outer.new(); b.name="OuterB"; root.add_child(b); _nodes.append(b)
	_check_success(b.setup({"authority_id":Topology.AUTHORITY_B,"listen_port":26411,"neighbor_endpoints":{Topology.AUTHORITY_A:{"host":"127.0.0.1","port":26410},Topology.AUTHORITY_C:{"host":"127.0.0.1","port":26412}},"initial_writer":false}), "B setup")
	var c := Outer.new(); c.name="OuterC"; root.add_child(c); _nodes.append(c)
	_check_success(c.setup({"authority_id":Topology.AUTHORITY_C,"listen_port":26412,"neighbor_endpoints":{Topology.AUTHORITY_B:{"host":"127.0.0.1","port":26411}},"anchor_port":26413,"initial_writer":false}), "C setup")
	var a := Outer.new(); a.name="OuterA"; root.add_child(a); _nodes.append(a)
	_check_success(a.setup({"authority_id":Topology.AUTHORITY_A,"listen_port":26410,"neighbor_endpoints":{Topology.AUTHORITY_B:{"host":"127.0.0.1","port":26411}},"anchor_port":26413,"initial_writer":true,"initial_world_position":{"x":-1.0,"y":0.0,"z":0.0},"linear_velocity":{"x":0.8,"y":0.0,"z":0.1},"angular_velocity_yaw":0.2}), "A setup")

	await process_frame; await process_frame; await process_frame
	var initial_a := a.status_for_tests(); var initial_s := nested.status_for_tests(); var initial_o := observer.status_for_tests()
	_check(int(initial_a.get("writer_count",0)) == 1, "A starts outer writer")
	_check(int(b.status_for_tests().get("writer_count",0)) == 0, "B never outer writer")
	_check(int(c.status_for_tests().get("writer_count",0)) == 0, "C starts nonwriter")
	_check(int(initial_s.get("writer_count",0)) == 1, "nested starts inner writer")
	_check(String(initial_s.get("island_authority_id","")) == Contract.ISLAND_AUTHORITY_ID, "nested authority id")
	_check(int(initial_s.get("inner_authority_epoch",0)) == 1, "nested epoch 1")
	_check(String(Dictionary(initial_s.get("player",{})).get("player_entity_id","")) == Contract.PLAYER_ENTITY_ID, "nested player identity")
	_check(not Dictionary(initial_s.get("anchor",{})).is_empty(), "nested receives initial anchor")
	_check(int(initial_o.get("writer_count",-1)) == 0, "observer read only")
	var ship_visual_id := int(initial_o.get("ship_visual_instance_id",0)); var player_visual_id := int(initial_o.get("player_visual_instance_id",0))
	_check(ship_visual_id > 0, "ship visual created")
	_check(player_visual_id > 0, "player visual created")

	var p0 := Dictionary(initial_s.get("player",{})); _check_success(nested.move_inner_for_tests(0.10,0.02), "nested move before handoff")
	var p1 := Dictionary(nested.status_for_tests().get("player",{}))
	_check(int(p1.get("last_input_sequence",0)) > int(p0.get("last_input_sequence",0)), "inner input sequence advances")
	_check(float(Dictionary(p1.get("position",{})).get("x",0.0)) > float(Dictionary(p0.get("position",{})).get("x",0.0)), "inner local x advances")

	var before_begin := Dictionary(a.status_for_tests().get("anchor",{})); var reservation_tick := int(before_begin.get("simulation_tick",0)); var before_x := float(Dictionary(before_begin.get("world_position",{})).get("x",0.0))
	_check_success(a.begin_transfer(Topology.AUTHORITY_C), "begin A to C")
	_check(int(a.status_for_tests().get("writer_count",0)) == 1, "A remains writer during PREPARE")
	_check(String(Dictionary(a.status_for_tests().get("transfer",{})).get("stage","")) == "PREPARE_SENT", "A prepare stage")
	_check_success(a.advance_for_tests(0.5), "A integrates during PREPARE")
	var during_prepare := Dictionary(a.status_for_tests().get("anchor",{}))
	_check(int(during_prepare.get("simulation_tick",0)) > reservation_tick, "ship tick advances during PREPARE")
	_check(float(Dictionary(during_prepare.get("world_position",{})).get("x",0.0)) > before_x, "ship position advances during PREPARE")
	_check(absf(float(Dictionary(during_prepare.get("linear_velocity",{})).get("x",0.0))) > 0.0, "linear velocity nonzero during PREPARE")
	_check(absf(float(during_prepare.get("angular_velocity_yaw",0.0))) > 0.0, "angular velocity nonzero during PREPARE")
	_check_success(nested.move_inner_for_tests(0.10,0.01), "nested move during A-C prepare")
	var seq_during_ac := int(Dictionary(nested.status_for_tests().get("player",{})).get("last_input_sequence",0))

	_check(await _wait_until(func(): return int(c.status_for_tests().get("writer_count",0)) == 1 and a.status_for_tests().get("transfer",{}).is_empty(), 240), "A-C completes")
	await process_frame; await process_frame
	var after_c := c.status_for_tests(); var after_a := a.status_for_tests(); var after_s := nested.status_for_tests(); var after_o := observer.status_for_tests(); var c_anchor := Dictionary(after_c.get("anchor",{}))
	_check(int(after_a.get("writer_count",0)) == 0, "A retired after A-C")
	_check(int(after_c.get("writer_count",0)) == 1, "C canonical after A-C")
	_check(int(c_anchor.get("outer_authority_epoch",0)) == 2, "outer epoch becomes 2")
	_check(String(c_anchor.get("outer_owner_authority_id","")) == Topology.AUTHORITY_C, "outer owner becomes C")
	_check(int(c_anchor.get("simulation_tick",0)) > reservation_tick, "commit uses freshest moving tick")
	_check(absf(float(Dictionary(c_anchor.get("linear_velocity",{})).get("x",0.0))) > 0.0, "commit preserves linear x velocity")
	_check(absf(float(c_anchor.get("angular_velocity_yaw",0.0))) > 0.0, "commit preserves angular velocity")
	_check(String(c_anchor.get("island_id","")) == Contract.ISLAND_ID, "commit preserves island id")
	_check(String(c_anchor.get("island_entity_id","")) == Contract.ISLAND_ENTITY_ID, "commit preserves ship entity id")
	_check(String(c_anchor.get("inner_authority_id","")) == Contract.ISLAND_AUTHORITY_ID, "commit preserves inner authority id")
	_check(int(after_s.get("writer_count",0)) == 1, "nested writer survives A-C")
	_check(int(after_s.get("inner_authority_epoch",0)) == 1, "nested epoch unchanged after A-C")
	_check(String(Dictionary(after_s.get("player",{})).get("player_entity_id","")) == Contract.PLAYER_ENTITY_ID, "player identity stable after A-C")
	_check(int(Dictionary(after_s.get("player",{})).get("last_input_sequence",0)) >= seq_during_ac, "inner sequence does not regress A-C")
	_check(int(after_s.get("owner_change_count",0)) >= 1, "nested observes C outer owner")
	_check(int(after_o.get("owner_change_count",0)) >= 1, "observer pivots outer owner to C")
	_check(int(after_o.get("ship_visual_instance_id",0)) == ship_visual_id, "ship visual persistent A-C")
	_check(int(after_o.get("player_visual_instance_id",0)) == player_visual_id, "player visual persistent A-C")

	var c_tick_before := int(c_anchor.get("simulation_tick",0))
	_check_success(c.advance_for_tests(0.4), "C integrates before return")
	_check_success(nested.move_inner_for_tests(0.12,-0.02), "nested move before return")
	var seq_before_return := int(Dictionary(nested.status_for_tests().get("player",{})).get("last_input_sequence",0))
	_check(int(Dictionary(c.status_for_tests().get("anchor",{})).get("simulation_tick",0)) > c_tick_before, "C ship tick continues")
	var return_reservation_tick := int(Dictionary(c.status_for_tests().get("anchor",{})).get("simulation_tick",0))
	_check_success(c.begin_transfer(Topology.AUTHORITY_A), "begin C to A")
	_check(int(c.status_for_tests().get("writer_count",0)) == 1, "C remains writer during PREPARE")
	_check_success(c.advance_for_tests(0.45), "C integrates during PREPARE")
	_check(int(Dictionary(c.status_for_tests().get("anchor",{})).get("simulation_tick",0)) > return_reservation_tick, "return tick advances during PREPARE")
	_check_success(nested.move_inner_for_tests(0.08,0.03), "nested move during C-A prepare")
	_check(await _wait_until(func(): return int(a.status_for_tests().get("writer_count",0)) == 1 and c.status_for_tests().get("transfer",{}).is_empty(), 240), "C-A completes")
	await process_frame; await process_frame
	var final_a := a.status_for_tests(); var final_c := c.status_for_tests(); var final_s := nested.status_for_tests(); var final_o := observer.status_for_tests(); var final_anchor := Dictionary(final_a.get("anchor",{})); var final_player := Dictionary(final_s.get("player",{}))
	_check(int(final_a.get("writer_count",0)) == 1, "A canonical after return")
	_check(int(final_c.get("writer_count",0)) == 0, "C retired after return")
	_check(int(b.status_for_tests().get("writer_count",0)) == 0, "B transit only final")
	_check(int(final_anchor.get("outer_authority_epoch",0)) == 3, "outer epoch becomes 3")
	_check(String(final_anchor.get("outer_owner_authority_id","")) == Topology.AUTHORITY_A, "outer owner returns A")
	_check(int(final_anchor.get("simulation_tick",0)) > return_reservation_tick, "return commit freshest tick")
	_check(absf(float(Dictionary(final_anchor.get("linear_velocity",{})).get("x",0.0))) > 0.0, "return preserves linear velocity")
	_check(absf(float(final_anchor.get("angular_velocity_yaw",0.0))) > 0.0, "return preserves angular velocity")
	_check(int(final_s.get("writer_count",0)) == 1, "nested remains writer final")
	_check(int(final_s.get("inner_authority_epoch",0)) == 1, "inner epoch remains 1 final")
	_check(String(final_player.get("player_entity_id","")) == Contract.PLAYER_ENTITY_ID, "player/a stable final")
	_check(int(final_player.get("last_input_sequence",0)) > seq_before_return, "player input continues through return")
	_check(int(final_s.get("owner_change_count",0)) >= 2, "nested observes two outer pivots")
	_check(int(final_o.get("owner_change_count",0)) >= 2, "observer sees two pivots")
	_check(int(final_o.get("frame_count",0)) >= 3, "observer receives multiple frames")
	_check(int(final_o.get("ship_visual_instance_id",0)) == ship_visual_id, "ship visual never respawns")
	_check(int(final_o.get("player_visual_instance_id",0)) == player_visual_id, "player visual never respawns")
	_check(int(b.status_for_tests().get("forwarded_count",0)) >= 8, "B forwards all handoff phases")
	_check(int(b.status_for_tests().get("rejected_count",0)) == 0, "B has no route rejection")

	var current_nested_anchor := Dictionary(nested.status_for_tests().get("anchor",{}))
	var current_nested_position := Dictionary(current_nested_anchor.get("world_position",{}))
	var same_tick_mutation := Contract.create_anchor(String(current_nested_anchor.get("outer_owner_authority_id",Topology.AUTHORITY_A)),int(current_nested_anchor.get("outer_authority_epoch",3)),int(current_nested_anchor.get("simulation_tick",0)),{"x":float(current_nested_position.get("x",0.0))+1.0,"y":float(current_nested_position.get("y",0.0)),"z":float(current_nested_position.get("z",0.0))},float(current_nested_anchor.get("world_yaw",0.0)),Dictionary(current_nested_anchor.get("linear_velocity",{})),float(current_nested_anchor.get("angular_velocity_yaw",0.0)))
	var mutation_result := nested.accept_anchor_for_tests(same_tick_mutation)
	_check(not bool(mutation_result.get("success",true)), "same-tick anchor mutation rejected")
	_check(String(mutation_result.get("error_code","")) == "SM0_P8_ANCHOR_SAME_TICK_MUTATION", "same-tick mutation exact error")
	var stale_anchor := Contract.create_anchor(Topology.AUTHORITY_A,2,int(current_nested_anchor.get("simulation_tick",0)),current_nested_position,float(current_nested_anchor.get("world_yaw",0.0)),Dictionary(current_nested_anchor.get("linear_velocity",{})),float(current_nested_anchor.get("angular_velocity_yaw",0.0)))
	var stale_result := nested.accept_anchor_for_tests(stale_anchor)
	_check(not bool(stale_result.get("success",true)), "stale outer epoch rejected")
	_check(String(stale_result.get("error_code","")) == "SM0_P8_ANCHOR_STALE", "stale anchor exact error")
	var final_view := Dictionary(final_o.get("last_view",{})); var mutated_player := Dictionary(final_view.get("player",{})).duplicate(true); mutated_player["position"]={"x":99.0,"y":0.0,"z":0.0}
	var same_sequence_view := Contract.create_view(int(final_view.get("view_sequence",1)),Dictionary(final_view.get("anchor",{})),1,mutated_player)
	var view_mutation_result := observer.accept_view_for_tests(same_sequence_view)
	_check(not bool(view_mutation_result.get("success",true)), "same-sequence visual mutation rejected")
	_check(String(view_mutation_result.get("error_code","")) == "SM0_P8_VIEW_SAME_SEQUENCE_MUTATION", "same-sequence exact error")

	_finish()

func _contract_checks() -> void:
	_check(Contract.ISLAND_ID == "island/ship/01", "island id constant")
	_check(Contract.ISLAND_ENTITY_ID == "ship/01", "island entity constant")
	_check(Contract.ISLAND_AUTHORITY_ID == "authority/island/ship/01", "nested authority constant")
	_check(Contract.PLAYER_ENTITY_ID == "player/a", "player entity constant")
	_check(Topology.plan_route(Topology.AUTHORITY_A,Topology.AUTHORITY_C) == [Topology.AUTHORITY_A,Topology.AUTHORITY_B,Topology.AUTHORITY_C], "A-C canonical route")
	_check(Topology.plan_route(Topology.AUTHORITY_C,Topology.AUTHORITY_A) == [Topology.AUTHORITY_C,Topology.AUTHORITY_B,Topology.AUTHORITY_A], "C-A canonical route")
	var anchor := Contract.create_anchor(Topology.AUTHORITY_A,1,10,{"x":1.0,"y":2.0,"z":3.0},0.25,{"x":0.8,"y":0.0,"z":0.1},0.2)
	_check_success(Contract.validate_anchor(anchor), "valid anchor")
	_check(absf(float(Dictionary(anchor.get("linear_velocity",{})).get("x",0.0))-0.8)<0.000001, "anchor linear velocity")
	_check(absf(float(anchor.get("angular_velocity_yaw",0.0))-0.2)<0.000001, "anchor angular velocity")
	var prepare := Contract.create_transfer("transfer/test",Contract.PHASE_PREPARE,Topology.AUTHORITY_A,Topology.AUTHORITY_C,Topology.AUTHORITY_A,Topology.AUTHORITY_C,1,2,10)
	_check_success(Contract.validate_transfer(prepare), "valid prepare")
	_check(Array(prepare.get("route_path",[])).size() == 3, "prepare has transit hop")
	_check(Contract.current_authority(prepare) == Topology.AUTHORITY_A, "prepare current A")
	var prepare_b := Contract.advance(prepare)
	var commit_anchor := Contract.create_anchor(Topology.AUTHORITY_C,2,12,{"x":1.2,"y":2.0,"z":3.0},0.3,{"x":0.8,"y":0.0,"z":0.1},0.2)
	var shell := Contract.create_transfer("transfer/test",Contract.PHASE_COMMIT,Topology.AUTHORITY_A,Topology.AUTHORITY_C,Topology.AUTHORITY_A,Topology.AUTHORITY_C,1,2,10,commit_anchor,"placeholder")
	var proof := Contract.retirement_proof_for(shell,commit_anchor)
	var commit := Contract.create_transfer("transfer/test",Contract.PHASE_COMMIT,Topology.AUTHORITY_A,Topology.AUTHORITY_C,Topology.AUTHORITY_A,Topology.AUTHORITY_C,1,2,10,commit_anchor,proof)
	_check_success(Contract.validate_transfer(commit), "valid commit with retirement proof")
	var bad_proof := commit.duplicate(true); bad_proof["retirement_proof"]="bad"; bad_proof["checksum"]="bad"
	_check(not bool(Contract.validate_transfer(bad_proof).get("success",true)), "bad commit proof rejected")
	var view_player := {"logical_player_id":"a","player_entity_id":"player/a","position":{"x":2.0,"y":0.0,"z":1.0},"last_input_sequence":5,"state_revision":7}
	var view := Contract.create_view(1,anchor,1,view_player)
	_check_success(Contract.validate_view(view), "valid composed view")

func _wait_until(predicate: Callable, max_frames: int) -> bool:
	for _index in range(max_frames):
		if bool(predicate.call()): return true
		await process_frame
	return bool(predicate.call())

func _check_success(result: Dictionary, label: String) -> void:
	_check(bool(result.get("success",false)), "%s: %s" % [label,String(result.get("error_code",""))])
func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if condition: return
	_failed = true; push_error("SM0 P8 assertion %d failed: %s" % [_assertions,label])
func _finish() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			if node.has_method("shutdown"): node.call("shutdown",0,"test-complete")
			node.queue_free()
	if not _failed and _assertions != EXPECTED_ASSERTIONS:
		_failed = true; push_error("SM0 P8 assertion count mismatch: expected %d got %d" % [EXPECTED_ASSERTIONS,_assertions])
	if _failed:
		print("SM0 P8 moving nested authority island: FAIL (%d assertions)" % _assertions); quit(1)
	else:
		print("SM0 P8 moving nested authority island: PASS (%d assertions)" % _assertions); quit(0)