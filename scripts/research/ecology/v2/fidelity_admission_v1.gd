extends SceneTree
## A9 consumes the accepted A8 owner and A6 accounting; it never advances biology itself.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const A8 = preload("res://scripts/research/ecology/v2/snapshot_seam_v1.gd")
const P = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")

func read_bounded(path: String, limit: int) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return ""
	if f.get_length() > limit:
		f.close()
		return ""
	var text := f.get_as_text()
	f.close()
	return text

func fail_run(message: String) -> void:
	print("A9_NATIVE_FAIL: " + message)
	quit(1)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		fail_run("REQUEST_AND_RESPONSE_PATHS_REQUIRED"); return
	var decoded := C.decode(read_bounded(args[0], 65536))
	if not decoded.success or not C.keys(decoded.value, ["operation", "input", "snapshot_hash", "origin_hash", "entity_id", "command", "received", "steps"]):
		fail_run("REQUEST_SCHEMA"); return
	var request: Dictionary = decoded.value
	for key in ["operation", "input", "snapshot_hash", "origin_hash", "entity_id", "received"]:
		if not request[key] is String:
			fail_run("REQUEST_TYPE"); return
	if not request.command is Dictionary or not C.integer(request.steps, 0, 16):
		fail_run("COMMAND_TYPE"); return
	var model = A8.new()
	if request.operation == "GENESIS":
		if not request.input.is_empty() or not request.snapshot_hash.is_empty() or not request.origin_hash.is_empty() or not request.command.is_empty() or not request.received.is_empty():
			fail_run("GENESIS_ARGS"); return
		if not model.start(P.treatment(), request.entity_id, "a9.region", "node.a"):
			fail_run(model.last_error); return
		for index in request.steps:
			var cur: Dictionary = model.cursor()
			var command := {"op_id": "a9.genesis.%d" % index, "kind": "ADVANCE", "actor": cur.owner_id,
				"epoch": cur.owner_epoch, "revision": cur.revision, "clock": cur.clock + 1, "args": {}}
			var applied: Dictionary = model.apply(command, model.snapshot_hash())
			if not applied.success: fail_run(String(applied.error)); return
	elif request.operation in ["ADMIT", "APPLY"]:
		if not request.entity_id.is_empty() or request.steps != 0:
			fail_run("RESTORE_ARGS"); return
		var text := read_bounded(request.input, C.MAX_BYTES)
		if text.is_empty() or not model.load_text(text, request.snapshot_hash, request.origin_hash):
			fail_run("A8_RESTORE:" + model.last_error); return
		if request.operation == "APPLY":
			var received := "" if request.received.is_empty() else read_bounded(request.received, C.MAX_BYTES)
			var applied: Dictionary = model.apply(request.command, model.snapshot_hash(), received)
			if not applied.success:
				fail_run("A8_APPLY:" + String(applied.error)); return
		elif not request.command.is_empty() or not request.received.is_empty():
			fail_run("ADMIT_ARGS"); return
	else:
		fail_run("OPERATION"); return
	var observed: Dictionary = model.observe()
	if not observed.get("success", false) or not observed.ecology.get("success", false):
		fail_run("NATIVE_OBSERVATION"); return
	var patches: Array = []
	for site in observed.ecology.sites:
		var counts := {"living": 0, "dead_provenance": 0, "corpses": site.corpses.size(), "pending_propagules": site.pending_propagules}
		var by_blueprint := {}
		for entry in site.entries:
			var key := C.digest(entry.blueprint)
			if not by_blueprint.has(key):
				by_blueprint[key] = {"blueprint_hash": key, "living": 0, "dead_provenance": 0}
			var category := "living" if entry.alive else "dead_provenance"
			counts[category] += 1
			by_blueprint[key][category] += 1
		var hashes: Array = by_blueprint.keys()
		hashes.sort()
		var cohorts: Array = []
		for hash in hashes: cohorts.append(by_blueprint[hash])
		var stocks := {"water_mg": 0, "organic_mg": 0, "nutrient_mg": 0}
		for cell in site.field.cells:
			for resource in stocks: stocks[resource] += cell.stocks[resource]
		patches.append({"id": site.id,
			"field": {"owner_token": site.field.owner_token, "owner_epoch": site.field.owner_epoch,
				"revision": site.field.revision, "tick": site.field.tick, "sha256": site.field.integrity_hash},
			"field_stocks": stocks, "accounts": site.balance, "counts": counts, "cohorts": cohorts})
	patches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	var cursor: Dictionary = model.cursor()
	var source := {"snapshot_sha256": model.snapshot_hash(), "origin_sha256": model.origin_hash(),
		"ecology_sha256": model.ecology_text().sha256_text(), "entity_id": cursor.entity_id,
		"region_id": cursor.region_id, "owner_id": cursor.owner_id, "owner_epoch": cursor.owner_epoch,
		"revision": cursor.revision, "clock": cursor.clock, "ecology_step": cursor.ecology_step,
		"ticket_state": model.ticket_snapshot().get("state", "NONE")}
	var response := C.encode({"schema": "dws.ecology.fidelity-admission.v1", "success": true,
		"source": source, "patches": patches})
	var snapshot: String = model.snapshot_text()
	if response.is_empty() or response.to_utf8_buffer().size() > 131072 or snapshot.is_empty():
		fail_run("OUTPUT_BUDGET"); return
	var f := FileAccess.open(args[1] + ".snapshot", FileAccess.WRITE)
	if f == null: fail_run("SNAPSHOT_OUTPUT"); return
	f.store_string(snapshot); f.close()
	f = FileAccess.open(args[1], FileAccess.WRITE)
	if f == null: fail_run("ADMISSION_OUTPUT"); return
	f.store_string(response); f.close()
	print("A9_NATIVE_PASS snapshot=" + model.snapshot_hash())
	quit(0)
