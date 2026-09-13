extends SceneTree
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const P = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")
const A7 = preload("res://scripts/research/ecology/v2/observatory_session_v1.gd")
const A8 = preload("res://scripts/research/ecology/v2/snapshot_seam_v1.gd")
const Ticket = preload("res://scripts/network/contracts/handoff_ticket.gd")
const OUT := "res://artifacts/a8/checkpoints/"
var assertions := 0
var failed := 0
var checkpoints: Array = []
var receipts: Array = []

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failed += 1
		print("FAIL: ", label)

func fresh():
	var m = A8.new()
	check(m.start(P.treatment(), "eco.a8.partition", "eco.a8.region", "node.a"), "A8 start")
	return m

func cmd(m, kind: String, args: Dictionary = {}, actor: String = "", epoch: int = -1) -> Dictionary:
	var c: Dictionary = m.cursor()
	return {"op_id": "op.%03d" % int(c.revision), "kind": kind,
		"actor": c.owner_id if actor.is_empty() else actor,
		"epoch": c.owner_epoch if epoch < 0 else epoch, "revision": c.revision, "clock": c.clock + 1, "args": args}

func request(m, id: String, target: String) -> Dictionary:
	var c: Dictionary = m.cursor()
	var t := Ticket.create(id, c.entity_id, c.owner_id, target, c.owner_epoch, c.owner_epoch + 1,
		c.revision, c.region_id, c.clock + 1, c.clock + 100)
	return cmd(m, "BEGIN", {"ticket": t})

func transition(m, state: String) -> Dictionary:
	var t: Dictionary = m.ticket_snapshot()
	return cmd(m, "TRANSITION", {"ticket_id": t.ticket_id, "state": state,
		"payload_hash": t.snapshot_hash if state == "TARGET_PREPARED" else ""},
		t.target_node_id if state == "TARGET_PREPARED" else "", t.target_authority_epoch if state == "TARGET_PREPARED" else -1)

func execute(m, command: Dictionary, record: bool = false) -> Dictionary:
	var received: String = m.ecology_text() if command.kind == "TRANSITION" and command.args.state == "TARGET_PREPARED" else ""
	var result: Dictionary = m.apply(command, m.snapshot_hash(), received)
	check(result.success, "apply " + command.kind + " " + String(command.args.get("state", "")) + " " + String(result.get("error", "")))
	if record and result.success:
		receipts.append(result.receipt)
		checkpoint(m)
	return result

func reject(m, command: Dictionary, reason: String, payload: String = "") -> void:
	var before: String = m.snapshot_text()
	var hash_before: String = m.snapshot_hash()
	var result: Dictionary = m.apply(command, hash_before, payload)
	check(not result.success and reason in String(result.get("error", "")), "reject " + reason + ":" + str(result))
	check(m.snapshot_text() == before and m.snapshot_hash() == hash_before, "rejection atomic " + reason)

func checkpoint(m) -> void:
	var file: String = "%03d.json" % int(m.cursor().revision)
	var f := FileAccess.open(OUT + file, FileAccess.WRITE)
	check(f != null, "checkpoint file")
	if f == null: return
	f.store_string(m.snapshot_text()); f.close()
	check(FileAccess.get_file_as_string(OUT + file).sha256_text() == m.snapshot_hash(), "checkpoint byte seal")
	checkpoints.append({"file": file, "sha256": m.snapshot_hash(), "cursor": m.cursor()})

func cycle(m, id: String, target: String, record: bool = false) -> void:
	var biological: String = m.ecology_text()
	execute(m, request(m, id, target), record)
	for state in ["PREPARING", "FROZEN", "SNAPSHOT_READY", "TARGET_PREPARED", "COMMITTED"]:
		execute(m, transition(m, state), record)
		check(m.ecology_text() == biological, "handoff does not rebase or mutate biology " + state)

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var m = fresh()
	checkpoint(m)
	for i in 2: execute(m, cmd(m, "ADVANCE"), true)
	cycle(m, "ticket.ab", "node.b", true)
	check(m.cursor().owner_id == "node.b" and m.cursor().owner_epoch == 2, "A to B committed")
	reject(m, cmd(m, "ADVANCE", {}, "node.a", 1), "A8_STALE_OWNER")
	reject(m, cmd(m, "ADVANCE", {}, "node.b", 1), "A8_STALE_EPOCH")
	execute(m, cmd(m, "ADVANCE"), true)
	cycle(m, "ticket.ba", "node.a", true)
	check(m.cursor().owner_id == "node.a" and m.cursor().owner_epoch == 3, "B to A new epoch")
	execute(m, cmd(m, "ADVANCE"), true)
	var baseline = A7.new()
	check(baseline.start(P.treatment()), "uninterrupted baseline start")
	for i in 4: check(baseline.advance(), "uninterrupted advance")
	check(baseline.save_text() == m.ecology_text(), "seam slicing preserves complete organism+field bytes")
	var report: Dictionary = m.observe()
	check(report.success and report.ecology.success, "real A8 observed A7")
	check(C.encode(report.ecology) == C.encode(baseline.observe()), "functional and visual sources preserved")
	check(report.ecology.sites[0].corpses.size() > 0 and report.ecology.sites[0].returned.organic_mg > 0, "actual corpse/soil legacy present")
	var final: Dictionary = C.decode(m.snapshot_text()).value
	var manifest := {"schema": "dws.ecology.a8-restart-fixtures.v1", "origin_hash": m.origin_hash(),
		"final_sha256": m.snapshot_hash(), "final_ecology_sha256": m.ecology_text().sha256_text(),
		"commands": final.commands, "receipts": receipts, "checkpoints": checkpoints}
	var f := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	check(f != null, "fixture manifest")
	if f != null: f.store_string(C.encode(manifest)); f.close()
	_negative_commands()
	_negative_restore(m)
	_expiry_and_budgets()
	_paid_outbox()
	print("A8_FIXTURES count=%d final=%s origin=%s" % [checkpoints.size(), m.snapshot_hash(), m.origin_hash()])
	print("EVO_ARCH2_A8_EXACT assertions=%d failed=%d" % [assertions, failed])
	quit(1 if failed else 0)

func _negative_commands() -> void:
	var m = fresh()
	var command := cmd(m, "ADVANCE")
	var bad := command.duplicate(true); bad.extra = 1
	reject(m, bad, "A8_COMMAND_SCHEMA")
	bad = command.duplicate(true); bad.epoch = 1.0
	reject(m, bad, "A8_COMMAND_INTEGER")
	bad = command.duplicate(true); bad.revision = 1
	reject(m, bad, "A8_STALE_REVISION")
	bad = command.duplicate(true); bad.actor = "node.x"
	reject(m, bad, "A8_STALE_OWNER")
	bad = command.duplicate(true); bad.epoch = 2
	reject(m, bad, "A8_STALE_EPOCH")
	bad = command.duplicate(true); bad.kind = "UNKNOWN"
	reject(m, bad, "A8_COMMAND_KIND")
	bad = command.duplicate(true); bad.args = {"unused": true}
	reject(m, bad, "A8_ADVANCE_ARGS")
	bad = command.duplicate(true); bad.args = {"x": "x".repeat(9000)}
	reject(m, bad, "A8_COMMAND_BUDGET")
	var before: String = m.snapshot_text()
	check(not m.apply(command, "0".repeat(64)).success and m.snapshot_text() == before, "external snapshot cursor required")
	var result := execute(m, command)
	var after: String = m.snapshot_text()
	var replay: Dictionary = m.apply(command, "0".repeat(64))
	check(replay.success and replay.replay and replay.receipt == result.receipt and m.snapshot_text() == after, "idempotent retry no write")
	bad = command.duplicate(true); bad.clock += 1
	reject(m, bad, "A8_OPERATION_ID_CONFLICT")
	bad = cmd(m, "ADVANCE"); bad.clock = 0
	reject(m, bad, "A8_STALE_CLOCK")
	for field in ["entity_id", "region_id", "source_node_id", "expected_state_revision", "created_at_tick"]:
		bad = request(m, "bad.ticket", "node.b")
		if field in ["expected_state_revision", "created_at_tick"]: bad.args.ticket[field] += 1
		else: bad.args.ticket[field] = "foreign"
		reject(m, bad, "A8_TICKET_")
	bad = request(m, "bad.ticket", "node.b"); bad.args.ticket.target_authority_epoch = 1
	reject(m, bad, "INVALID_AUTHORITY_EPOCH")
	execute(m, request(m, "ticket.test", "node.b"))
	reject(m, cmd(m, "ADVANCE"), "A8_HANDOFF_FROZEN")
	reject(m, cmd(m, "ADVANCE", {}, "node.b", 2), "A8_STALE_OWNER")
	reject(m, request(m, "ticket.overlap", "node.c"), "A8_HANDOFF_ACTIVE")
	reject(m, transition(m, "COMMITTED"), "ILLEGAL_HANDOFF_TRANSITION")
	bad = transition(m, "PREPARING"); bad.args.ticket_id = "foreign"
	reject(m, bad, "A8_TICKET_MISMATCH")
	execute(m, transition(m, "PREPARING"))
	reject(m, transition(m, "PREPARING"), "A8_RETRY_REQUIRES_ORIGINAL_OPERATION_ID")
	for state in ["FROZEN", "SNAPSHOT_READY"]: execute(m, transition(m, state))
	bad = transition(m, "TARGET_PREPARED"); bad.args.payload_hash = "0".repeat(64)
	reject(m, bad, "A8_TARGET_HASH", m.ecology_text())
	reject(m, transition(m, "TARGET_PREPARED"), "A8_TARGET_PAYLOAD", "truncated")
	reject(m, transition(m, "TARGET_PREPARED"), "A8_TARGET_PAYLOAD")
	var acknowledgement := transition(m, "TARGET_PREPARED")
	execute(m, acknowledgement)
	reject(m, acknowledgement, "A8_RETRY_PAYLOAD_MISMATCH", "wrong retry bytes")
	execute(m, transition(m, "COMMITTED"))
	reject(m, transition(m, "ABORTED"), "A8_HANDOFF_TERMINAL")
	reject(m, request(m, "ticket.test", "node.a"), "A8_TICKET_ID_REUSED")

func _negative_restore(source) -> void:
	var m = fresh()
	var text: String = source.snapshot_text()
	var origin: String = source.origin_hash()
	var before: String = m.snapshot_text()
	check(not m.load_text(text, "0".repeat(64), origin), "wrong snapshot hash")
	check(not m.load_text(text, text.sha256_text(), "0".repeat(64)), "wrong origin")
	check(not m.load_text("{", "{".sha256_text(), origin), "broken encoding")
	var huge: String = "x".repeat(C.MAX_BYTES + 1)
	check(not m.load_text(huge, huge.sha256_text(), origin), "snapshot bytes bounded")
	var data: Dictionary = C.decode(text).value
	for key in ["owner_id", "owner_epoch", "ecology_step", "clock", "revision"]:
		var bad: Dictionary = data.duplicate(true)
		if key == "owner_id": bad.cut[key] = "attacker"
		else: bad.cut[key] += 1
		var bytes := C.encode(bad)
		check(not m.load_text(bytes, bytes.sha256_text(), origin), "rehashed forged cut " + key)
	var bad: Dictionary = data.duplicate(true); bad.cut.ticket.state = "ABORTED"
	var bytes := C.encode(bad)
	check(not m.load_text(bytes, bytes.sha256_text(), origin), "forged ticket")
	bad = data.duplicate(true); bad.commands.pop_back(); bytes = C.encode(bad)
	check(not m.load_text(bytes, bytes.sha256_text(), origin), "truncated command cursor")
	bad = data.duplicate(true); bad.commands.insert(1, bad.commands[0]); bytes = C.encode(bad)
	check(not m.load_text(bytes, bytes.sha256_text(), origin), "duplicate log event rejected")
	bad = data.duplicate(true); bad.commands.reverse(); bytes = C.encode(bad)
	check(not m.load_text(bytes, bytes.sha256_text(), origin), "reordered command log")
	bad = data.duplicate(true); bad.cut.ecology_payload = "{}"; bytes = C.encode(bad)
	check(not m.load_text(bytes, bytes.sha256_text(), origin), "missing organism/field payload")
	bad = data.duplicate(true); bad.extra = true; bytes = C.encode(bad)
	check(not m.load_text(bytes, bytes.sha256_text(), origin), "unknown snapshot field")
	check(m.snapshot_text() == before, "all failed restores atomic")
	check(m.load_text(text, text.sha256_text(), origin) and m.snapshot_text() == text, "whole anchored replay restore")
	var command: Dictionary = data.commands[0]
	var result: Dictionary = m.apply(command, "0".repeat(64))
	check(result.success and result.replay and result.receipt == receipts[0] and m.snapshot_text() == text, "historical operation receipt survives restart")

func _expiry_and_budgets() -> void:
	var m = fresh()
	var original: String = m.ecology_text()
	execute(m, request(m, "expire.1", "node.b"))
	reject(m, transition(m, "EXPIRED"), "HANDOFF_NOT_EXPIRED")
	var expire := transition(m, "EXPIRED"); expire.clock = m.ticket_snapshot().expires_at_tick
	execute(m, expire)
	check(m.cursor().owner_id == "node.a" and m.cursor().owner_epoch == 1 and m.ecology_text() == original, "expiry has one original owner")
	execute(m, cmd(m, "ADVANCE"))
	var n = fresh()
	for i in A8.MAX_TICKETS:
		execute(n, request(n, "abort.%d" % i, "node.b"))
		execute(n, transition(n, "ABORTED"))
	check(n.ecology_text() == original and n.cursor().owner_epoch == 1, "aborts preserve biology and owner")
	reject(n, request(n, "overflow", "node.b"), "A8_TICKET_BUDGET")
	var bad: Dictionary = C.decode(n.snapshot_text()).value
	while bad.commands.size() <= A8.MAX_COMMANDS: bad.commands.append({})
	var text := C.encode(bad)
	check(not n.load_text(text, text.sha256_text(), n.origin_hash()), "journal budget")
	var before: String = n.snapshot_text()
	check(not n.start({}, "e", "r", "a") and n.snapshot_text() == before, "invalid start atomic")

func _paid_outbox() -> void:
	var m = fresh()
	for i in 16: execute(m, cmd(m, "ADVANCE"))
	var view: Dictionary = m.observe()
	check(view.success and view.ecology.success and view.ecology.sites[0].pending_propagules > 0, "real paid propagules present")
	check(view.ecology.scope == "FOUNDER_CONTROLS_NOT_MULTI_GENERATION_EVOLUTION", "no free generations claim")
	var full: String = m.ecology_text()
	cycle(m, "paid.ab", "node.b")
	check(m.ecology_text() == full, "paid outbox+corpse+body+field transfer byte exact")
	reject(m, cmd(m, "ADVANCE"), "A7_HORIZON_BUDGET")
	var restored = A8.new()
	check(restored.load_text(m.snapshot_text(), m.snapshot_hash(), m.origin_hash()), "full horizon independent semantic restore")
	check(restored.ecology_text() == full and restored.cursor().owner_id == "node.b", "full restored cut and executor")
