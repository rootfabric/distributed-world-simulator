extends SceneTree
const Observer = preload("res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_observer.gd")
func _init()->void:
	var options:=_parse_args(OS.get_cmdline_user_args()); var observer:=Observer.new(); observer.name="Sm0P8Observer"; root.add_child(observer); observer.finished.connect(_on_finished)
	var result:Dictionary=observer.setup({"listen_host":String(options.get("listen-host","127.0.0.1")),"listen_port":int(options.get("listen-port","0")),"stop_file":String(options.get("stop-file",""))})
	if not bool(result.get("success",false)):print("[SM0_P8_VISUAL_BOOT] setup_failed=%s" % JSON.stringify(result,"",false,true));push_error("SM0 P8 observer setup failed: %s" % result);quit(2);return
	print("[SM0_P8_VISUAL_BOOT] setup_success listen_port=%s" % options.get("listen-port","0"))
func _on_finished(exit_code:int)->void:quit(exit_code)
func _parse_args(args:PackedStringArray)->Dictionary:
	var result:Dictionary={}
	for value in args:
		var arg:=String(value)
		if not arg.begins_with("--") or not arg.contains("="):continue
		var separator:=arg.find("=");result[arg.substr(2,separator-2)]=arg.substr(separator+1)
	return result
