extends SceneTree
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const A8 = preload("res://scripts/research/ecology/v2/snapshot_seam_v1.gd")
var assertions := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failed += 1
		print("FAIL: ", label)
func bounded_read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return ""
	if f.get_length() > C.MAX_BYTES:
		f.close()
		return ""
	var text := f.get_as_text(); f.close()
	return text
func finish() -> void:
	print("EVO_ARCH2_A8_RESTART assertions=%d failed=%d" % [assertions, failed])
	quit(1 if failed else 0)
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	check(args.size() == 5, "input sha origin manifest manifest-sha required")
	if failed: finish(); return
	var text := bounded_read(args[0])
	var manifest_text := bounded_read(args[3])
	check(not text.is_empty() and not manifest_text.is_empty() and manifest_text.sha256_text() == args[4], "bounded external fixture manifest")
	if failed: finish(); return
	var decoded := C.decode(manifest_text)
	check(decoded.success and decoded.value is Dictionary, "fixture encoding")
	if failed: finish(); return
	var manifest: Dictionary = decoded.value
	check(manifest.get("schema") == "dws.ecology.a8-restart-fixtures.v1" and manifest.get("origin_hash") == args[2], "fixture origin")
	if failed: finish(); return
	var m = A8.new()
	check(m.load_text(text, args[1], args[2]), "fresh semantic restore " + m.last_error)
	if failed: finish(); return
	var revision: int = m.cursor().revision
	if revision > 0:
		var before: String = m.snapshot_hash()
		var duplicate: Dictionary = m.apply(manifest.commands[revision - 1], "0".repeat(64))
		check(duplicate.success and duplicate.replay and duplicate.receipt == manifest.receipts[revision - 1], "exact persisted operation receipt")
		check(m.snapshot_hash() == before, "retry does not publish another transition")
	for i in range(revision, manifest.commands.size()):
		var command: Dictionary = manifest.commands[i]
		var received: String = m.ecology_text() if command.kind == "TRANSITION" and command.args.state == "TARGET_PREPARED" else ""
		var result: Dictionary = m.apply(command, m.snapshot_hash(), received)
		check(result.success and not result.replay, "continued operation " + str(i) + " " + String(result.get("error", "")))
		if not result.success: finish(); return
		check(result.receipt == manifest.receipts[i], "continued receipt exact " + str(i))
	check(m.snapshot_hash() == manifest.final_sha256, "restart seam final snapshot exact")
	check(m.ecology_text().sha256_text() == manifest.final_ecology_sha256, "full biological cut exact")
	check(m.cursor().owner_id == "node.a" and m.cursor().owner_epoch == 3 and m.cursor().ecology_step == 4, "one final executor and unchanged biological time")
	print("A8_RESTART revision=%d final=%s" % [revision, m.snapshot_hash()])
	finish()
