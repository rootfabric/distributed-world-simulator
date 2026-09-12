extends SceneTree
const P = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Model = preload("res://scripts/research/ecology/v2/observatory_session_v1.gd")
const Scene = preload("res://scenes/labs/ecology/arch2_a7_observatory.tscn")
var assertions := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failed += 1
		print("FAIL: ", label)
func _initialize() -> void: call_deferred("run")
func _write(text: String) -> bool:
	var file := FileAccess.open(P.PATH, FileAccess.WRITE)
	if file == null: return false
	file.store_string(text)
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	return ok
func run() -> void:
	var original := FileAccess.get_file_as_string(P.PATH)
	var protocol := P.manifest()
	check(not protocol.is_empty(), "canonical manifest")
	if protocol.is_empty(): quit(1); return
	check(C.digest(protocol) == P.PROTOCOL_SHA256, "complete pinned digest")
	check(P.decode_manifest(original) == protocol, "same decoder as file loader")
	check(P.decode_manifest("\n" + original + "\n") == protocol, "canonical whitespace does not alter identity")
	var cases: Array = []
	for resource in ["material_mg", "water_mg", "energy_mj"]:
		var v := protocol.duplicate(true); v.study_endowment[resource] += 1; cases.append(v)
	var donor := protocol.duplicate(true); donor.donor_material_mg += 1; cases.append(donor)
	for i in 3:
		for channel in ["water_mg", "light"]:
			var v := protocol.duplicate(true)
			v.sites[i][channel] -= 1
			cases.append(v)
	for field in ["coordinate_units", "resource_units", "scope", "schema", "id", "mutation_operator"]:
		var v := protocol.duplicate(true); v[field] += "-forged"; cases.append(v)
	for field in ["horizon", "field_capacity_mg"]:
		var v := protocol.duplicate(true); v[field] += 1; cases.append(v)
	var seed := protocol.duplicate(true); seed.seeds[0] += 1; cases.append(seed)
	var site := protocol.duplicate(true); site.sites[0].id = "dry"; cases.append(site)
	var unknown := protocol.duplicate(true); unknown["unknown"] = true; cases.append(unknown)
	var wrong_type := protocol.duplicate(true); wrong_type.study_endowment.water_mg = true; cases.append(wrong_type)
	for i in cases.size():
		var v: Dictionary = cases[i]
		check(P.decode_manifest(C.encode(v)).is_empty(), "changed full manifest rejected %d" % i)
		check(not P.valid_treatment(P.treatment(), v), "public treatment cannot substitute protocol %d" % i)
		check(not P.founding_genome(P.treatment(), v).success, "founder cannot substitute protocol %d" % i)
		check(not P.site_genesis("wet", P.treatment(), v).success, "site cannot substitute protocol %d" % i)
	check(P.decode_manifest("x".repeat(P.MAX_PROTOCOL_BYTES + 1)).is_empty(), "bounded protocol text")
	check(P.decode_manifest("not-json").is_empty(), "malformed protocol")
	check(not P.valid_treatment(P.treatment(), {}), "empty protocol")
	var model := Model.new()
	check(model.start(P.treatment()), "genuine model starts")
	var before := model.source_hashes()
	var ui = Scene.instantiate(); root.add_child(ui)
	await process_frame
	var ui_before: Dictionary = ui.model.source_hashes()
	# Exercise the actual file loader. Restore exact original bytes before exiting.
	check(_write(C.encode(cases[0])), "write coherent on-disk protocol mutation")
	check(P.manifest().is_empty(), "actual manifest loader rejects changed endowment")
	check(not model.start(P.treatment()), "actual model.start rejects file tamper")
	check(model.source_hashes() == before, "failed start preserves experiment")
	ui.reset_experiment()
	check(ui.status.text.begins_with("PROTOCOL REJECTED"), "GUI reset reports rejection")
	check(ui.model.source_hashes() == ui_before, "failed GUI reset preserves experiment")
	var rejected_ui = Scene.instantiate(); root.add_child(rejected_ui)
	check(rejected_ui.status.text.begins_with("PROTOCOL REJECTED"), "GUI startup rejects without dereferencing empty manifest")
	check(_write(original), "restore original protocol bytes")
	check(FileAccess.get_file_as_string(P.PATH) == original and P.manifest() == protocol, "post-test byte-exact protocol restored")
	check(model.start(P.treatment()), "genuine loader usable after repair control")
	ui.queue_free(); rejected_ui.queue_free()
	await process_frame
	print("EVO_ARCH2_A7_PROTOCOL assertions=%d failed=%d" % [assertions, failed])
	quit(1 if failed else 0)
