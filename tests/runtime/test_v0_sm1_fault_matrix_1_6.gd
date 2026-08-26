extends SceneTree

const FaultDriver = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_7_fault_driver.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

const STATE_ACTIVE := "ACTIVE"
const STATE_SOURCE_FROZEN := "SOURCE_FROZEN"
const STATE_TARGET_WARM_VALIDATED := "TARGET_WARM_VALIDATED"
const STATE_OWNERSHIP_COMMITTED := "OWNERSHIP_COMMITTED"
const STATE_SOURCE_RETIRED := "SOURCE_RETIRED"

const POLL_MS := 20
const READY_TIMEOUT_MS := 15000
const MESSAGE_TIMEOUT_MS := 10000
const EXIT_TIMEOUT_MS := 5000

var assertions := 0
var failures: Array[String] = []
var subcases := 0
var trace_events: Array[Dictionary] = []
var child_pids: Array[int] = []


func _init() -> void:
	_run_7_1_source_death()
	_run_7_2_target_death()
	_run_7_3_ambiguous_commit_retry()
	_run_7_4_stale_source_fencing()
	_run_7_5_duplicate_and_reorder()
	_run_7_6_historical_resurrection()
	_finish()


func _run_7_1_source_death() -> void:
	# 7.1A: source dies before FREEZE is admitted. Canonical tuple remains A/1;
	# target may not promote itself.
	_begin_subcase("7.1A source death before FREEZE")
	var d1 := FaultDriver.new()
	var c1 = d1.fresh_coordinator()
	_assert_snapshot(c1.snapshot(), STATE_ACTIVE, Support.AUTHORITY_A, 1, "7.1A canonical tuple unchanged")
	_assert(not bool(c1.authorize_write(Support.AUTHORITY_B, 2).get("success", false)), "7.1A target cannot self-promote after source death")
	var source_kill: Dictionary = _probe_kill_authority_process(Support.AUTHORITY_A, true, 1)
	_assert(bool(source_kill.get("success", false)), "7.1A real source Authority A OS process is killable at pre-FREEZE boundary: %s" % str(source_kill))
	_assert(int(source_kill.get("process_id", 0)) > 0, "7.1A source death evidence carries a real OS pid")
	_collect(d1)

	# 7.1B: FREEZE has been admitted but no source result is available. This is
	# a deliberate zero-writer gap; COMMIT must remain impossible.
	_begin_subcase("7.1B source death after FREEZE sent before result")
	var d2 := FaultDriver.new()
	var c2 = d2.fresh_coordinator()
	var begun: Dictionary = c2.begin_transfer("t/7.1b", Support.AUTHORITY_A, Support.AUTHORITY_B, 1)
	d2.record("FREEZE_SENT_SOURCE_DIES", "t/7.1b", c2.snapshot(), begun)
	_assert(bool(begun.get("success", false)), "7.1B transfer enters frozen gap")
	_assert_snapshot(c2.snapshot(), STATE_SOURCE_FROZEN, Support.AUTHORITY_A, 1, "7.1B source remains canonical but no writer is admitted")
	_assert_zero_writer(c2, "7.1B")
	var premature: Dictionary = c2.commit_ownership("t/7.1b", Support.AUTHORITY_A, Support.AUTHORITY_B, 1, 2)
	_assert(not bool(premature.get("success", false)) and String(premature.get("error_code", "")) == "SM1_COMMIT_BEFORE_WARM_VALIDATION", "7.1B commit forbidden without WARM proof")
	_assert(int(c2.get_report().get("counters", {}).get("commits", -1)) == 0, "7.1B commit counter unchanged")
	_collect(d2)

	# 7.1C: once SOURCE_FROZEN evidence exists, source loss cannot create a
	# second writer; transfer may complete from validated derived WARM evidence.
	_begin_subcase("7.1C source death after frozen proof")
	var d3 := FaultDriver.new()
	var c3 = d3.fresh_coordinator()
	var done: Dictionary = d3.complete_transfer(c3, "t/7.1c", Support.AUTHORITY_A, Support.AUTHORITY_B, 1)
	_assert(bool(done.get("success", false)), "7.1C transfer completes from frozen/WARM proof")
	_assert_snapshot(c3.snapshot(), STATE_ACTIVE, Support.AUTHORITY_B, 2, "7.1C target becomes sole active authority")
	_assert(not bool(c3.authorize_write(Support.AUTHORITY_A, 1).get("success", false)), "7.1C dead/stale source permanently fenced")
	_assert(bool(c3.authorize_write(Support.AUTHORITY_B, 2).get("success", false)), "7.1C target writer admitted only after activation")
	_collect(d3)


func _run_7_2_target_death() -> void:
	_begin_subcase("7.2A target death before WARM")
	var d1 := FaultDriver.new()
	var c1 = d1.fresh_coordinator()
	var begun: Dictionary = c1.begin_transfer("t/7.2a", Support.AUTHORITY_A, Support.AUTHORITY_B, 1)
	d1.record("TARGET_DIES_BEFORE_WARM", "t/7.2a", c1.snapshot(), begun)
	_assert(bool(begun.get("success", false)), "7.2A freeze admitted")
	_assert_zero_writer(c1, "7.2A")
	var commit: Dictionary = c1.commit_ownership("t/7.2a", Support.AUTHORITY_A, Support.AUTHORITY_B, 1, 2)
	_assert(not bool(commit.get("success", false)), "7.2A target death cannot commit ownership")
	_assert_snapshot(c1.snapshot(), STATE_SOURCE_FROZEN, Support.AUTHORITY_A, 1, "7.2A ownership tuple not promoted")
	var target_kill: Dictionary = _probe_kill_authority_process(Support.AUTHORITY_B, false, 1)
	_assert(bool(target_kill.get("success", false)), "7.2A real WARM-target Authority B OS process is killable before WARM: %s" % str(target_kill))
	_assert(int(target_kill.get("process_id", 0)) > 0, "7.2A target death evidence carries a real OS pid")
	_collect(d1)

	_begin_subcase("7.2B target death during WARM before result")
	var d2 := FaultDriver.new()
	var c2 = d2.fresh_coordinator()
	var begun2: Dictionary = c2.begin_transfer("t/7.2b", Support.AUTHORITY_A, Support.AUTHORITY_B, 1)
	d2.record("WARM_SENT_TARGET_DIES", "t/7.2b", c2.snapshot(), begun2)
	_assert_zero_writer(c2, "7.2B")
	var commit2: Dictionary = c2.commit_ownership("t/7.2b", Support.AUTHORITY_A, Support.AUTHORITY_B, 1, 2)
	_assert(not bool(commit2.get("success", false)), "7.2B ambiguous WARM outcome cannot commit")
	_assert(int(c2.get_report().get("counters", {}).get("warm_validations", -1)) == 0, "7.2B no WARM validation recorded")
	_collect(d2)

	_begin_subcase("7.2C target death after WARM before COMMIT")
	var d3 := FaultDriver.new()
	var c3 = d3.fresh_coordinator()
	var warm: Dictionary = d3.begin_to_warm(c3, "t/7.2c", Support.AUTHORITY_A, Support.AUTHORITY_B, 1)
	_assert(bool(warm.get("success", false)), "7.2C WARM proof accepted before target loss")
	_assert_snapshot(c3.snapshot(), STATE_TARGET_WARM_VALIDATED, Support.AUTHORITY_A, 1, "7.2C no ownership commit occurred")
	_assert_zero_writer(c3, "7.2C")
	var replay_warm: Dictionary = c3.validate_warm_target("t/7.2c", Support.AUTHORITY_B, d3.warm_report("t/7.2c"))
	_assert(bool(replay_warm.get("success", false)) and String(replay_warm.get("details", {}).get("result", "")) == "WARM_ALREADY_VALIDATED", "7.2C restarted target may reuse exact current WARM evidence")
	var stale_warm: Dictionary = c3.validate_warm_target("t/old", Support.AUTHORITY_B, d3.warm_report("t/old"))
	_assert(not bool(stale_warm.get("success", false)), "7.2C stale/different transfer WARM evidence rejected")
	_assert(int(c3.get_report().get("counters", {}).get("commits", -1)) == 0, "7.2C target death leaves commit counter zero")
	_collect(d3)


func _run_7_3_ambiguous_commit_retry() -> void:
	_begin_subcase("7.3A COMMIT result lost then retried")
	var d1 := FaultDriver.new()
	var c1 = d1.fresh_coordinator()
	_assert(bool(d1.begin_to_warm(c1, "t/7.3a", Support.AUTHORITY_A, Support.AUTHORITY_B, 1).get("success", false)), "7.3A ready to commit")
	var first: Dictionary = c1.commit_ownership("t/7.3a", Support.AUTHORITY_A, Support.AUTHORITY_B, 1, 2)
	d1.record("COMMIT_RESULT_DROPPED", "t/7.3a", c1.snapshot(), first)
	var first_token := String(first.get("details", {}).get("commit_token", ""))
	_assert(bool(first.get("success", false)) and not first_token.is_empty(), "7.3A first COMMIT linearizes")
	var retry: Dictionary = c1.commit_ownership("t/7.3a", Support.AUTHORITY_A, Support.AUTHORITY_B, 1, 2)
	d1.record("COMMIT_RETRY", "t/7.3a", c1.snapshot(), retry)
	_assert(bool(retry.get("success", false)) and String(retry.get("details", {}).get("result", "")) == "ALREADY_COMMITTED", "7.3A retry converges to already committed")
	_assert(String(retry.get("details", {}).get("commit_token", "")) == first_token, "7.3A retry returns identical commit proof")
	_assert(not bool(retry.get("details", {}).get("linearized_now", true)), "7.3A retry does not linearize twice")
	var counters1: Dictionary = c1.get_report().get("counters", {})
	_assert(int(counters1.get("commits", -1)) == 1 and int(counters1.get("commit_replays", -1)) == 1, "7.3A exactly one commit plus one replay")
	_assert_zero_writer(c1, "7.3A post-commit/pre-retire")
	_collect(d1)

	_begin_subcase("7.3B ACTIVATE result lost then retried")
	var d2 := FaultDriver.new()
	var c2 = d2.fresh_coordinator()
	_assert(bool(d2.begin_to_warm(c2, "t/7.3b", Support.AUTHORITY_A, Support.AUTHORITY_B, 1).get("success", false)), "7.3B ready to commit")
	var committed: Dictionary = c2.commit_ownership("t/7.3b", Support.AUTHORITY_A, Support.AUTHORITY_B, 1, 2)
	var token := String(committed.get("details", {}).get("commit_token", ""))
	_assert(bool(c2.retire_source("t/7.3b", Support.AUTHORITY_A, token).get("success", false)), "7.3B source retired")
	var activate: Dictionary = c2.activate_target("t/7.3b", Support.AUTHORITY_B, 2, token)
	d2.record("ACTIVATE_RESULT_DROPPED", "t/7.3b", c2.snapshot(), activate)
	_assert(bool(activate.get("success", false)), "7.3B target activation linearizes once")
	var activate_retry: Dictionary = c2.activate_target("t/7.3b", Support.AUTHORITY_B, 2, token)
	d2.record("ACTIVATE_RETRY", "t/7.3b", c2.snapshot(), activate_retry)
	_assert(bool(activate_retry.get("success", false)) and String(activate_retry.get("details", {}).get("result", "")) == "ALREADY_ACTIVE", "7.3B activation retry converges")
	var counters2: Dictionary = c2.get_report().get("counters", {})
	_assert(int(counters2.get("activations", -1)) == 1 and int(counters2.get("activation_replays", -1)) == 1, "7.3B activation occurs once")
	_assert_snapshot(c2.snapshot(), STATE_ACTIVE, Support.AUTHORITY_B, 2, "7.3B B remains sole active authority")
	_collect(d2)


func _run_7_4_stale_source_fencing() -> void:
	_begin_subcase("7.4A stale source route rejected by coordinator")
	var d1 := FaultDriver.new()
	var c1 = d1.fresh_coordinator()
	_assert(bool(d1.complete_transfer(c1, "t/7.4a", Support.AUTHORITY_A, Support.AUTHORITY_B, 1).get("success", false)), "7.4A A->B complete")
	var before_epoch := int(c1.snapshot().get("authority_epoch", 0))
	var stale: Dictionary = c1.authorize_write(Support.AUTHORITY_A, 1)
	_assert(not bool(stale.get("success", false)) and String(stale.get("error_code", "")) == "SM1_STALE_AUTHORITY_EPOCH", "7.4A stale A/1 write fenced")
	_assert(int(c1.snapshot().get("authority_epoch", 0)) == before_epoch, "7.4A stale write cannot advance epoch")
	_assert(bool(c1.authorize_write(Support.AUTHORITY_B, 2).get("success", false)), "7.4A current B/2 write admitted")
	_collect(d1)

	_begin_subcase("7.4B direct retired authority worker rejects stale write")
	var direct: Dictionary = _probe_retired_authority_process()
	_assert(bool(direct.get("success", false)), "7.4B direct ENET probe reached real SM1.6 authority worker: %s" % str(direct))
	_assert(String(direct.get("error_code", "")) == "SM1_AUTHORITY_NOT_ACTIVE", "7.4B retired source rejects direct stale EXECUTE")
	_assert(int(direct.get("process_id", 0)) > 0, "7.4B direct probe used a separate OS authority process")


func _run_7_5_duplicate_and_reorder() -> void:
	_begin_subcase("7.5A duplicate transfer messages converge or reject safely")
	var d1 := FaultDriver.new()
	var c1 = d1.fresh_coordinator()
	var begin1: Dictionary = c1.begin_transfer("t/7.5a", Support.AUTHORITY_A, Support.AUTHORITY_B, 1)
	_assert(bool(begin1.get("success", false)), "7.5A first FREEZE admitted")
	var begin2: Dictionary = c1.begin_transfer("t/7.5a", Support.AUTHORITY_A, Support.AUTHORITY_B, 1)
	_assert(not bool(begin2.get("success", false)) and String(begin2.get("error_code", "")) == "SM1_TRANSFER_IN_PROGRESS", "7.5A duplicate FREEZE safely rejected")
	var warm1: Dictionary = c1.validate_warm_target("t/7.5a", Support.AUTHORITY_B, d1.warm_report("t/7.5a"))
	var warm2: Dictionary = c1.validate_warm_target("t/7.5a", Support.AUTHORITY_B, d1.warm_report("t/7.5a"))
	_assert(bool(warm1.get("success", false)) and bool(warm2.get("success", false)), "7.5A duplicate WARM converges")
	var commit1: Dictionary = c1.commit_ownership("t/7.5a", Support.AUTHORITY_A, Support.AUTHORITY_B, 1, 2)
	var token := String(commit1.get("details", {}).get("commit_token", ""))
	var commit2: Dictionary = c1.commit_ownership("t/7.5a", Support.AUTHORITY_A, Support.AUTHORITY_B, 1, 2)
	_assert(bool(commit1.get("success", false)) and bool(commit2.get("success", false)), "7.5A duplicate COMMIT converges")
	var retire1: Dictionary = c1.retire_source("t/7.5a", Support.AUTHORITY_A, token)
	var retire2: Dictionary = c1.retire_source("t/7.5a", Support.AUTHORITY_A, token)
	_assert(bool(retire1.get("success", false)) and bool(retire2.get("success", false)), "7.5A duplicate RETIRE converges")
	var activate1: Dictionary = c1.activate_target("t/7.5a", Support.AUTHORITY_B, 2, token)
	var activate2: Dictionary = c1.activate_target("t/7.5a", Support.AUTHORITY_B, 2, token)
	_assert(bool(activate1.get("success", false)) and bool(activate2.get("success", false)), "7.5A duplicate ACTIVATE converges")
	var counters: Dictionary = c1.get_report().get("counters", {})
	_assert(int(counters.get("commits", -1)) == 1 and int(counters.get("activations", -1)) == 1, "7.5A duplicate sequence mutates commit/activation exactly once")
	_collect(d1)

	_begin_subcase("7.5B invalid reorder is fail-closed")
	var d2 := FaultDriver.new()
	var c2 = d2.fresh_coordinator()
	_assert(bool(c2.begin_transfer("t/7.5b", Support.AUTHORITY_A, Support.AUTHORITY_B, 1).get("success", false)), "7.5B FREEZE admitted")
	var commit_before_warm: Dictionary = c2.commit_ownership("t/7.5b", Support.AUTHORITY_A, Support.AUTHORITY_B, 1, 2)
	_assert(not bool(commit_before_warm.get("success", false)), "7.5B COMMIT before WARM rejected")
	var retire_before_commit: Dictionary = c2.retire_source("t/7.5b", Support.AUTHORITY_A, "bogus")
	_assert(not bool(retire_before_commit.get("success", false)), "7.5B RETIRE before COMMIT rejected")
	var activate_before_commit: Dictionary = c2.activate_target("t/7.5b", Support.AUTHORITY_B, 2, "bogus")
	_assert(not bool(activate_before_commit.get("success", false)), "7.5B ACTIVATE before COMMIT rejected")
	_assert_snapshot(c2.snapshot(), STATE_SOURCE_FROZEN, Support.AUTHORITY_A, 1, "7.5B invalid early messages do not advance state")
	_assert(bool(c2.validate_warm_target("t/7.5b", Support.AUTHORITY_B, d2.warm_report("t/7.5b")).get("success", false)), "7.5B valid WARM accepted")
	var commit_ok: Dictionary = c2.commit_ownership("t/7.5b", Support.AUTHORITY_A, Support.AUTHORITY_B, 1, 2)
	var token2 := String(commit_ok.get("details", {}).get("commit_token", ""))
	var activate_before_retire: Dictionary = c2.activate_target("t/7.5b", Support.AUTHORITY_B, 2, token2)
	_assert(not bool(activate_before_retire.get("success", false)), "7.5B ACTIVATE before RETIRE rejected")
	_assert_snapshot(c2.snapshot(), STATE_OWNERSHIP_COMMITTED, Support.AUTHORITY_B, 2, "7.5B rejected activation cannot make target writable")
	_assert_zero_writer(c2, "7.5B post-commit/pre-retire")
	_collect(d2)

	_begin_subcase("7.5C completed-transfer FREEZE replay cannot reopen transfer")
	var d3 := FaultDriver.new()
	var c3 = d3.fresh_coordinator()
	_assert(bool(d3.complete_transfer(c3, "t/7.5c", Support.AUTHORITY_A, Support.AUTHORITY_B, 1).get("success", false)), "7.5C initial transfer completes")
	var replay: Dictionary = c3.begin_transfer("t/7.5c", Support.AUTHORITY_A, Support.AUTHORITY_B, 1)
	_assert(not bool(replay.get("success", false)) and String(replay.get("error_code", "")) == "SM1_TRANSFER_ALREADY_COMPLETED", "7.5C old FREEZE replay rejected")
	_assert_snapshot(c3.snapshot(), STATE_ACTIVE, Support.AUTHORITY_B, 2, "7.5C completed replay leaves current owner unchanged")
	_collect(d3)


func _run_7_6_historical_resurrection() -> void:
	_begin_subcase("7.6 replay old T1 after A->B->A")
	var d := FaultDriver.new()
	var c = d.fresh_coordinator()
	_assert(bool(d.complete_transfer(c, "t/7.6/t1", Support.AUTHORITY_A, Support.AUTHORITY_B, 1).get("success", false)), "7.6 T1 A->B complete")
	var t1: Dictionary = c.get_completed_transfer("t/7.6/t1")
	_assert(not t1.is_empty(), "7.6 T1 completion proof retained")
	_assert(bool(d.complete_transfer(c, "t/7.6/t2", Support.AUTHORITY_B, Support.AUTHORITY_A, 2).get("success", false)), "7.6 T2 B->A complete")
	_assert_snapshot(c.snapshot(), STATE_ACTIVE, Support.AUTHORITY_A, 3, "7.6 current owner A/3 before replay")
	var old_commit: Dictionary = c.commit_ownership("t/7.6/t1", Support.AUTHORITY_A, Support.AUTHORITY_B, 1, 2)
	_assert(bool(old_commit.get("success", false)) and String(old_commit.get("details", {}).get("result", "")) == "ALREADY_COMMITTED", "7.6 historical COMMIT returns proof only")
	_assert_snapshot(c.snapshot(), STATE_ACTIVE, Support.AUTHORITY_A, 3, "7.6 historical COMMIT cannot roll back owner")
	var old_activate: Dictionary = c.activate_target("t/7.6/t1", Support.AUTHORITY_B, 2, String(t1.get("commit_token", "")))
	_assert(bool(old_activate.get("success", false)) and String(old_activate.get("details", {}).get("result", "")) == "ALREADY_ACTIVATED", "7.6 historical ACTIVATE recognized")
	_assert(not bool(old_activate.get("details", {}).get("currently_active", true)), "7.6 historical target explicitly reported inactive")
	_assert(String(old_activate.get("details", {}).get("current_authority_id", "")) == Support.AUTHORITY_A and int(old_activate.get("details", {}).get("current_authority_epoch", 0)) == 3, "7.6 replay reports current A/3 tuple")
	_assert(not bool(c.authorize_write(Support.AUTHORITY_B, 2).get("success", false)), "7.6 resurrected B/2 write fenced")
	_assert(bool(c.authorize_write(Support.AUTHORITY_A, 3).get("success", false)), "7.6 current A/3 write remains admitted")
	_assert_snapshot(c.snapshot(), STATE_ACTIVE, Support.AUTHORITY_A, 3, "7.6 full T1 replay changes nothing")
	_collect(d)


func _probe_kill_authority_process(authority_id: String, initial_active: bool, epoch: int) -> Dictionary:
	var port := _allocate_port()
	if port <= 0:
		return {"success": false, "error_code": "NO_PORT"}
	var suffix := authority_id.replace("/", "-")
	var root := ProjectSettings.globalize_path("res://artifacts/test-results/sm1-fault-kill-%s-%d" % [suffix, OS.get_process_id()])
	DirAccess.make_dir_recursive_absolute(root)
	var result_path := root.path_join("authority.json")
	var log_path := root.path_join("authority.log")
	var exe := OS.get_executable_path()
	var args: Array = [
		"--log-file", log_path,
		"--headless", "--quiet", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_authority_worker.gd", "--",
		"--authority-id=%s" % authority_id,
		"--host=127.0.0.1", "--port=%d" % port,
		"--initial-active=%s" % ("true" if initial_active else "false"),
		"--initial-epoch=%d" % epoch,
		"--result-file=%s" % result_path,
	]
	var pid := OS.create_process(exe, args, false)
	if pid <= 0:
		return {"success": false, "error_code": "SPAWN_FAILED"}
	child_pids.append(pid)
	var ready: Dictionary = _wait_state(result_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	if String(ready.get("state", "")) != "LISTENING":
		OS.kill(pid)
		_wait_proc_gone(pid, EXIT_TIMEOUT_MS)
		child_pids.erase(pid)
		return {"success": false, "error_code": "AUTHORITY_NOT_READY", "details": ready, "process_id": pid}
	var killed := OS.kill(pid)
	var dead := _wait_proc_gone(pid, EXIT_TIMEOUT_MS)
	child_pids.erase(pid)
	return {
		"success": killed == OK and dead,
		"error_code": "" if killed == OK and dead else "PROCESS_STILL_RUNNING",
		"process_id": pid,
		"authority_id": authority_id,
		"initial_active": initial_active,
		"authority_epoch": epoch,
		"dead": dead,
	}


func _probe_retired_authority_process() -> Dictionary:
	var port := _allocate_port()
	if port <= 0:
		return {"success": false, "error_code": "NO_PORT"}
	var root := ProjectSettings.globalize_path("res://artifacts/test-results/sm1-fault-direct-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(root)
	var result_path := root.path_join("authority-a.json")
	var log_path := root.path_join("authority-a.log")
	var exe := OS.get_executable_path()
	var args: Array = [
		"--log-file", log_path,
		"--headless", "--quiet", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://scripts/runtime/networked_gameplay/sm1/sm1_6_authority_worker.gd", "--",
		"--authority-id=%s" % Support.AUTHORITY_A,
		"--host=127.0.0.1", "--port=%d" % port,
		"--initial-active=true", "--initial-epoch=1", "--result-file=%s" % result_path,
	]
	var pid := OS.create_process(exe, args, false)
	if pid <= 0:
		return {"success": false, "error_code": "SPAWN_FAILED"}
	child_pids.append(pid)
	var ready: Dictionary = _wait_state(result_path, ["LISTENING", "FAILED"], READY_TIMEOUT_MS)
	if String(ready.get("state", "")) != "LISTENING":
		return {"success": false, "error_code": "AUTHORITY_NOT_READY", "details": ready, "process_id": pid}
	var boundary = Support.make_boundary()
	if boundary == null:
		return {"success": false, "error_code": "BOUNDARY_FAILED", "process_id": pid}
	var peer_id := "peer/enet/sm1/fault-direct-a"
	var connected: Dictionary = boundary.connect_client(Support.endpoint("127.0.0.1", port), peer_id, "transport-session/sm1/fault-direct", "route/sm1/fault-direct", 1)
	if not bool(connected.get("success", false)):
		boundary.stop()
		return {"success": false, "error_code": "CONNECT_FAILED", "details": connected, "process_id": pid}
	if not _wait_peer_ready(boundary, peer_id, READY_TIMEOUT_MS):
		boundary.stop()
		return {"success": false, "error_code": "PEER_NOT_READY", "process_id": pid}
	var freeze: Dictionary = _request(boundary, peer_id, {"type": "FREEZE", "request_id": "fault/freeze", "source_epoch": 1}, "FREEZE_RESULT")
	if not bool(freeze.get("success", false)):
		boundary.stop()
		return {"success": false, "error_code": "FREEZE_FAILED", "details": freeze, "process_id": pid}
	var retire: Dictionary = _request(boundary, peer_id, {"type": "RETIRE", "request_id": "fault/retire"}, "RETIRE_RESULT")
	if not bool(retire.get("success", false)):
		boundary.stop()
		return {"success": false, "error_code": "RETIRE_FAILED", "details": retire, "process_id": pid}
	var stale: Dictionary = _request(boundary, peer_id, {
		"type": "EXECUTE", "request_id": "fault/stale-execute", "authority_epoch": 1,
		"operation_id": "operation/sm1/fault/stale", "input_sequence": 1,
		"command_kind": "ACTION", "delta_x": 0.0,
	}, "EXECUTE_RESULT")
	_request(boundary, peer_id, {"type": "SHUTDOWN", "request_id": "fault/shutdown"}, "__NO_RESPONSE__", 100)
	boundary.stop()
	_wait_exit(pid, EXIT_TIMEOUT_MS)
	return {
		"success": not bool(stale.get("success", true)),
		"error_code": String(stale.get("error_code", "")),
		"process_id": pid,
		"response": stale,
	}


func _request(boundary, peer_id: String, payload: Dictionary, expected_type: String, timeout_ms: int = MESSAGE_TIMEOUT_MS) -> Dictionary:
	var sent: Dictionary = Support.send(boundary, peer_id, payload)
	if not bool(sent.get("success", false)):
		return {"success": false, "error_code": String(sent.get("error_code", "SEND_FAILED"))}
	boundary.flush_outbound(128)
	if expected_type == "__NO_RESPONSE__":
		OS.delay_msec(timeout_ms)
		return {"success": true}
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		var polled: Dictionary = boundary.poll_events(128)
		for raw in polled.get("details", {}).get("events", []):
			var event: Dictionary = Dictionary(raw)
			if String(event.get("event_type", "")) == "PEER_CONNECTED":
				Support.mark_ready(boundary, String(event.get("peer_id", "")))
			elif String(event.get("event_type", "")) == "MESSAGE_RECEIVED":
				var response: Dictionary = Support.payload_from_event(event)
				if String(response.get("type", "")) == expected_type and String(response.get("request_id", "")) == String(payload.get("request_id", "")):
					return response
		boundary.flush_outbound(128)
		OS.delay_msec(POLL_MS)
	return {"success": false, "error_code": "RESPONSE_TIMEOUT", "expected_type": expected_type}


func _wait_peer_ready(boundary, peer_id: String, timeout_ms: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		var polled: Dictionary = boundary.poll_events(128)
		for raw in polled.get("details", {}).get("events", []):
			var event: Dictionary = Dictionary(raw)
			if String(event.get("event_type", "")) == "PEER_CONNECTED":
				Support.mark_ready(boundary, String(event.get("peer_id", "")))
		if Support.mark_ready(boundary, peer_id):
			return true
		boundary.flush_outbound(128)
		OS.delay_msec(POLL_MS)
	return false


func _assert_snapshot(snapshot: Dictionary, state: String, authority_id: String, epoch: int, message: String) -> void:
	_assert(String(snapshot.get("state", "")) == state, "%s: state=%s" % [message, state])
	_assert(String(snapshot.get("active_authority_id", "")) == authority_id, "%s: authority=%s" % [message, authority_id])
	_assert(int(snapshot.get("authority_epoch", 0)) == epoch, "%s: epoch=%d" % [message, epoch])
	_assert(not bool(snapshot.get("private_item_graph", true)), "%s: no private Item Graph" % message)
	_assert(not bool(snapshot.get("private_construction_truth", true)), "%s: no private Construction truth" % message)
	_assert(not bool(snapshot.get("private_persistence_owner", true)), "%s: no private persistence owner" % message)
	_assert(not bool(snapshot.get("private_replay_owner", true)), "%s: no private replay owner" % message)


func _assert_zero_writer(coordinator, label: String) -> void:
	var snapshot: Dictionary = coordinator.snapshot()
	var active_id := String(snapshot.get("active_authority_id", ""))
	var epoch := int(snapshot.get("authority_epoch", 0))
	var active_attempt: Dictionary = coordinator.authorize_write(active_id, epoch)
	_assert(not bool(active_attempt.get("success", false)), "%s transfer gap rejects canonical tuple writes" % label)
	var other := Support.AUTHORITY_B if active_id == Support.AUTHORITY_A else Support.AUTHORITY_A
	var other_attempt: Dictionary = coordinator.authorize_write(other, epoch + 1)
	_assert(not bool(other_attempt.get("success", false)), "%s transfer gap rejects target/other writes" % label)


func _begin_subcase(name: String) -> void:
	subcases += 1
	print("[sm1.7] SUBCASE %02d %s" % [subcases, name])


func _collect(driver) -> void:
	for value in driver.trace_report().get("events", []):
		trace_events.append(Dictionary(value).duplicate(true))


func _allocate_port() -> int:
	var start := 30000 + (OS.get_process_id() % 20000)
	for offset in range(1000):
		var port := 20000 + ((start + offset - 20000) % 40000)
		var probe := PacketPeerUDP.new()
		var error := probe.bind(port, "127.0.0.1")
		probe.close()
		if error == OK:
			return port
	return -1


func _wait_state(path: String, terminal_states: Array, timeout_ms: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started <= timeout_ms:
		var value := _read_json(path)
		if terminal_states.has(String(value.get("state", ""))):
			return value
		OS.delay_msec(POLL_MS)
	return _read_json(path)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return Dictionary(parsed) if parsed is Dictionary else {}


func _wait_proc_gone(pid: int, timeout_ms: int) -> bool:
	var started := Time.get_ticks_msec()
	var proc_path := "/proc/%d" % pid
	while DirAccess.dir_exists_absolute(proc_path) and Time.get_ticks_msec() - started <= timeout_ms:
		OS.delay_msec(POLL_MS)
	return not DirAccess.dir_exists_absolute(proc_path)


func _wait_exit(pid: int, timeout_ms: int) -> void:
	var started := Time.get_ticks_msec()
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() - started <= timeout_ms:
		OS.delay_msec(POLL_MS)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("[sm1.7] PASS: %s" % message)
	else:
		failures.append(message)
		print("[sm1.7][FAIL] %s" % message)


func _finish() -> void:
	for pid in child_pids.duplicate():
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	child_pids.clear()
	var root := ProjectSettings.globalize_path("res://artifacts/test-results")
	DirAccess.make_dir_recursive_absolute(root)
	Support.write_json(root.path_join("sm1-7-fault-trace-%d.json" % OS.get_process_id()), {
		"schema": "distributed_world_simulator.v0_sm1_7_fault_matrix_1_6.v1",
		"scenarios": 6,
		"subcases": subcases,
		"assertions": assertions,
		"failures": failures.duplicate(),
		"trace": trace_events.duplicate(true),
	})
	print("SM1.7.1-7.6 fault matrix: %d assertions, %d failures" % [assertions, failures.size()])
	if failures.is_empty() and subcases == 14:
		print("SM1_7_FAULT_MATRIX_1_6_PASS")
		print("scenarios=6")
		print("subcases=14")
		print("failures=0")
	quit(0 if failures.is_empty() and subcases == 14 else 1)
