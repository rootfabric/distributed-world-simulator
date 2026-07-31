extends SceneTree
const TIMEOUT:=25000
var failures:Array[String]=[];var assertions:=0;var pids:Array[int]=[]
func _init()->void:
	var port=_port();_assert(port>0,"port allocation")
	var root=ProjectSettings.globalize_path("res://artifacts/test-results/h2-ownership-%d"%OS.get_process_id());DirAccess.make_dir_recursive_absolute(root)
	var server_path=root.path_join("server.json");var client_path=root.path_join("client.json")
	var exe=OS.get_executable_path();var project=ProjectSettings.globalize_path("res://")
	var spid=OS.create_process(exe,["--headless","--path",project,"--script","res://tools/runtime/h2_ownership_server.gd","--","--host=127.0.0.1","--port=%d"%port,"--result-file=%s"%server_path,"--timeout-ms=%d"%TIMEOUT],false);pids.append(spid);_assert(spid>0,"server launch")
	var listen=_wait(server_path,["LISTENING","FAILED"],5000);_assert(String(listen.get("state",""))=="LISTENING","server listening")
	var cpid=OS.create_process(exe,["--headless","--path",project,"--script","res://tools/runtime/h2_ownership_client.gd","--","--host=127.0.0.1","--port=%d"%port,"--result-file=%s"%client_path,"--timeout-ms=%d"%TIMEOUT],false);pids.append(cpid);_assert(cpid>0,"client launch")
	var server=_wait(server_path,["COMPLETE","FAILED"],TIMEOUT);var client=_wait(client_path,["COMPLETE","FAILED"],TIMEOUT)
	_assert(bool(server.get("passed",false)),"server result: %s"%server);_assert(bool(client.get("passed",false)),"client result: %s"%client)
	_assert(int(server.get("joins",0))==2,"two remote joins");_assert(int(server.get("leaves",0))==1,"one remote leave")
	_assert(int(server.get("registry",{}).get("player_count",0))==2,"host and remote identities")
	_assert(int(server.get("registry",{}).get("connected_count",0))>=1,"host remains connected after client lifecycle")
	_assert(String(server.get("remote_player_entity_id",""))==String(client.get("player_entity_id","")),"replicated player identity")
	_assert(int(client.get("first_ownership_epoch",0))==1 and int(client.get("second_ownership_epoch",0))==2,"ownership epoch replication")
	_finish()
func _port()->int:
	for i in range(300):
		var p=23000+((OS.get_process_id()+i)%25000);var probe=PacketPeerUDP.new();var e=probe.bind(p,"127.0.0.1");probe.close();if e==OK:return p
	return 0
func _wait(path: String, states: Array[String], timeout: int) -> Dictionary:
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at <= timeout:
		var result := _read_json_dictionary(path)
		if not result.is_empty() and String(result.get("state", "")) in states:
			return result
		OS.delay_msec(25)
	return {}


func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		# Another process may be replacing or still closing the result file.
		# Treat the transient sharing violation as "not ready" and retry.
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
func _assert(c:bool,m:String)->void:assertions+=1;if not c:failures.append(m)
func _finish()->void:
	for pid in pids:
		if pid>0 and OS.is_process_running(pid):OS.kill(pid)
	if failures.is_empty():print("H2 host/client ownership processes: PASS (%d assertions)"%assertions);quit(0);return
	for f in failures:push_error(f)
	print("H2 host/client ownership processes: FAIL (%d failures, %d assertions)"%[failures.size(),assertions]);quit(1)
