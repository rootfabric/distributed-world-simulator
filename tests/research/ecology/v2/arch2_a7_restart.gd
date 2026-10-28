extends SceneTree
const Model = preload("res://scripts/research/ecology/v2/observatory_session_v1.gd")
const P = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const DIR := "res://artifacts/a7/restart"
func _initialize() -> void:
 var args=OS.get_cmdline_user_args()
 var m=Model.new()
 if args.size()!=1: quit(2);return
 if args[0]=="write":
  if not m.start(P.treatment(104729,true)):quit(3);return
  for i in 3:
   if not m.advance():quit(4);return
  var text=m.save_text()
  var anchor={"experiment":m.experiment_hash(),"step":m.step_index(),"snapshot_hash":text.sha256_text()}
  if not m.advance():quit(5);return
  anchor["continued_sources"]=m.source_hashes()
  DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
  var f=FileAccess.open(DIR+"/snapshot.json",FileAccess.WRITE);f.store_string(text);f.close()
  f=FileAccess.open(DIR+"/manifest.json",FileAccess.WRITE);f.store_string(C.encode(anchor));f.close()
 elif args[0]=="read":
  var a=C.decode(FileAccess.get_file_as_string(DIR+"/manifest.json"))
  if not a.success:quit(6);return
  var text=FileAccess.get_file_as_string(DIR+"/snapshot.json")
  if text.sha256_text()!=a.value.snapshot_hash:quit(7);return
  if not m.load_text(text,a.value.experiment,a.value.step):quit(8);return
  if not m.advance() or m.source_hashes()!=a.value.continued_sources:quit(9);return
 else:quit(10);return
 print("EVO_ARCH2_A7_RESTART phase=%s failed=0" % args[0])
 quit()
