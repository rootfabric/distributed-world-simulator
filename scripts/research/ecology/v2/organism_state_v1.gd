extends RefCounted
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const E = preload("res://scripts/research/ecology/v2/environment_fixture_v1.gd")
const SCHEMA := "dws.ecology.organism-state.v1"
const OUTCOMES := ["AGE_LIMIT", "RULE_COMPLETE", "WAIT_ENVIRONMENT", "DISABLED", "WAIT_RESOURCES", "WAIT_ATTACHMENT", "WAIT_ALLOCATION_ROLE", "RETIRED", "BRANCHED", "GENETIC_DEPTH_LIMIT", "MODULE_CREATED", "ALLOCATED"]

static func create(g: Dictionary, individual_id: String = "lab/ancestor", reserves: Dictionary = B.stock(100000000)) -> Dictionary:
	if not G.validate(g).is_empty() or not C.identifier(individual_id) or not B.valid_stock(reserves):
		return {}
	return {"schema": SCHEMA, "genome_hash": G.biological_hash(g), "individual_id": individual_id, "tick": 0, "grant_seq": 0, "modules": [B.root()], "tips": [{"id": "p000000", "module": "m000000", "rule": g.program.entry, "pc": 0, "depth": 0, "birth_tick": 0}], "next_tip": 1, "reserves": reserves.duplicate(), "received": reserves.duplicate(), "spent": B.stock(), "branch_energy_mj": 0, "attachments": [], "limits": {"modules": 256, "tips": 32}, "frame": {}, "last_events": []}

static func validate(s: Variant, g: Dictionary) -> String:
	if not G.validate(g).is_empty():
		return "STATE_GENOME"
	if not C.keys(s, ["schema", "genome_hash", "individual_id", "tick", "grant_seq", "modules", "tips", "next_tip", "reserves", "received", "spent", "branch_energy_mj", "attachments", "limits", "frame", "last_events"]):
		return "STATE_FIELDS"
	if s.schema != SCHEMA or s.genome_hash != G.biological_hash(g) or not C.identifier(s.individual_id):
		return "STATE_BINDING"
	if not C.integer(s.tick, 0, 1000000) or not C.integer(s.grant_seq, 0, 1000000) or not C.integer(s.next_tip, 1, 1000000) or not C.integer(s.branch_energy_mj, 0, B.MAX_STOCK):
		return "STATE_COUNTER"
	var body_error := B.validate(s.modules)
	if not body_error.is_empty():
		return body_error
	if not C.keys(s.limits, ["modules", "tips"]) or not C.integer(s.limits.modules, s.modules.size(), 256) or not C.integer(s.limits.tips, 1, 32):
		return "STATE_LIMITS"
	var ids := {}
	for module in s.modules:
		ids[module.id] = module
	var rules := {}
	for rule in g.program.rules:
		rules[rule.id] = rule
	if not s.tips is Array or s.tips.size() > s.limits.tips:
		return "STATE_TIPS"
	var seen := {}
	for tip in s.tips:
		if not C.keys(tip, ["id", "module", "rule", "pc", "depth", "birth_tick"]) or not C.identifier(tip.id) or seen.has(tip.id):
			return "TIP_ID"
		if not ids.has(tip.module) or not rules.has(tip.rule):
			return "TIP_REFERENCE"
		if not C.integer(tip.pc, 0, rules[tip.rule].actions.size()) or not C.integer(tip.depth, 0, g.program.max_depth) or not C.integer(tip.birth_tick, 0, s.tick + 1):
			return "TIP_COUNTER"
		if not tip.id.begins_with("p") or not tip.id.substr(1).is_valid_int() or (int(tip.id.substr(1)) < 0 or int(tip.id.substr(1)) >= s.next_tip) or tip.id != "p%06d" % int(tip.id.substr(1)):
			return "TIP_SEQUENCE"
		seen[tip.id] = true
	for name in ["reserves", "received", "spent"]:
		if not B.valid_stock(s[name]):
			return "STATE_RESOURCE"
	var costs := B.stock()
	for m in s.modules:
		for name in B.RESOURCES:
			costs[name] += m.cost[name]
	costs.energy_mj += s.branch_energy_mj
	for name in B.RESOURCES:
		if s.received[name] != s.reserves[name] + s.spent[name] or s.spent[name] != costs[name]:
			return "RESOURCE_CONSERVATION"
	if not s.attachments is Array or s.attachments.size() > s.modules.size():
		return "STATE_ATTACHMENTS"
	var attached := {}
	for a in s.attachments:
		if not C.keys(a, ["module", "support_id", "environment_hash"]) or not ids.has(a.module) or ids[a.module].role != "attachment" or attached.has(a.module):
			return "ATTACHMENT_REFERENCE"
		if not C.identifier(a.support_id) or not a.environment_hash is String or a.environment_hash.length() != 64:
			return "ATTACHMENT_SOURCE"
		attached[a.module] = true
	for m in s.modules:
		if m.role == "attachment" and m.id != "m000000" and not attached.has(m.id):
			return "MISSING_ATTACHMENT_SOURCE"
	if not _events_valid(s.last_events):
		return "STATE_EVENTS"
	if not s.frame is Dictionary:
		return "STATE_FRAME"
	if s.grant_seq != s.tick + (0 if s.frame.is_empty() else 1):
		return "STATE_GRANT_TICK"
	if not s.frame.is_empty():
		var f: Dictionary = s.frame
		if not C.keys(f, ["environment", "queue", "cursor", "events"]) or not E.validate(f.environment).is_empty():
			return "FRAME_ENVIRONMENT"
		if not f.queue is Array or f.queue.size() > 32 or not C.integer(f.cursor, 0, f.queue.size()) or not _events_valid(f.events):
			return "FRAME_QUEUE"
		var queued := {}
		for i in f.queue.size():
			var id: Variant = f.queue[i]
			if not C.identifier(id) or queued.has(id) or (i >= f.cursor and not seen.has(id)):
				return "FRAME_REFERENCE"
			queued[id] = true
	return "NONCANONICAL_STATE" if C.encode(s).is_empty() else ""

static func biological_hash(s: Dictionary) -> String:
	var value := s.duplicate(true)
	value.erase("individual_id")
	value.tips.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return C.digest(value)

static func serialize(s: Dictionary, g: Dictionary) -> String:
	if not validate(s, g).is_empty():
		return ""
	return C.encode({"schema": "dws.ecology.state-file.v1", "genome": g, "state": s, "state_hash": C.digest(s)})

static func deserialize(text: String) -> Dictionary:
	var decoded := C.decode(text)
	if not decoded.success:
		return {}
	var v: Variant = decoded.value
	if not C.keys(v, ["schema", "genome", "state", "state_hash"]) or v.schema != "dws.ecology.state-file.v1" or not v.genome is Dictionary:
		return {}
	if not validate(v.state, v.genome).is_empty() or C.digest(v.state) != v.state_hash:
		return {}
	return {"genome": v.genome, "state": v.state}

static func _events_valid(events: Variant) -> bool:
	if not events is Array or events.size() > 1024:
		return false
	for event in events:
		if not C.keys(event, ["tip", "rule", "outcome"]) or not C.identifier(event.tip) or not C.identifier(event.rule) or not event.outcome in OUTCOMES:
			return false
	return true
