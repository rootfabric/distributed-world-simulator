extends SceneTree
const X = preload("res://tests/research/ecology/v2/arch2_a6_fixtures.gd")
const A6 = X.A6
const C = X.C
const DIRECTORY := "res://artifacts/a6/restart"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() == 1 else ""
	if not mode in ["write", "read"]:
		push_error("FAIL:A6_RESTART_MODE"); quit(1); return
	var success := _write() if mode == "write" else _read()
	print("EVO_ARCH2_A6_RESTART phase=%s failed=%d" % [mode, 0 if success else 1])
	quit(0 if success else 1)

func _advance(state: Dictionary, count: int) -> Dictionary:
	var s := state
	for _i in count:
		var next := X.step(s)
		if not next.success: return {}
		s = next.state
	return s

func _write() -> bool:
	var p := A6.default_policy(); p.material_return_mg = 7; p.mineralization_per_cell_mg = 3
	var made := A6.create("cold.restart", X.field(), [X.root("donor", X.stock(80, 9, 20), true), X.recipient()], p)
	if not made.success: return false
	var prefix := _advance(made.state, 3)
	if prefix.is_empty(): return false
	var final := _advance(prefix, 2)
	if final.is_empty(): return false
	var text := A6.serialize(prefix)
	var manifest := C.encode({"genesis_hash": prefix.genesis_hash, "revision": prefix.frame.step, "expected_final_hash": final.integrity_hash})
	if text.is_empty() or manifest.is_empty(): return false
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY)) != OK: return false
	var snapshot := FileAccess.open(DIRECTORY + "/snapshot.json", FileAccess.WRITE)
	if snapshot == null: return false
	snapshot.store_string(text); snapshot.close()
	var anchor := FileAccess.open(DIRECTORY + "/manifest.json", FileAccess.WRITE)
	if anchor == null: return false
	anchor.store_string(manifest); anchor.close()
	return true

func _read() -> bool:
	var decoded := C.decode(FileAccess.get_file_as_string(DIRECTORY + "/manifest.json"))
	if not decoded.success: return false
	var m: Dictionary = decoded.value
	var restored := A6.deserialize(FileAccess.get_file_as_string(DIRECTORY + "/snapshot.json"), m.genesis_hash, m.revision)
	if restored.is_empty(): return false
	var final := _advance(restored, 2)
	if final.is_empty() or final.integrity_hash != m.expected_final_hash: return false
	print("A6_RESTART_FINAL_HASH=", final.integrity_hash)
	return true
