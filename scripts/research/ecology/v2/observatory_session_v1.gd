extends RefCounted
## A7 owns only a bounded experiment controller. All ecology transitions are unchanged A6.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const LS = preload("res://scripts/research/ecology/v2/organism_life_state_v1.gd")
const Phenotype = preload("res://scripts/research/ecology/v2/phenotype_snapshot_v1.gd")
const A6 = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")
const Protocol = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")
const SCHEMA := "dws.ecology.observatory-save.v1"
const SOURCE_A6 := "993271eb46880b77f0e7584f931131d4bd0a5125"
var _protocol: Dictionary = {}
var _treatment: Dictionary = {}
var _sessions: Dictionary = {}
var _genesis_hashes: Dictionary = {}
var _experiment_hash := ""
var last_error := "A7_NOT_STARTED"

func start(t: Dictionary) -> bool:
	var protocol := Protocol.manifest()
	if not Protocol.valid_treatment(t, protocol): return _fail("A7_TREATMENT")
	var sessions := {}
	var hashes := {}
	for site in Protocol.SITES:
		var result := Protocol.site_genesis(site, t, protocol)
		if not result.success: return _fail(String(result.get("error", "A7_GENESIS")))
		sessions[site] = result.state
		hashes[site] = result.state.genesis_hash
	_protocol = protocol
	_treatment = t.duplicate(true)
	_sessions = sessions
	_genesis_hashes = hashes
	_experiment_hash = C.digest({"protocol": C.digest(protocol), "treatment": t, "genesis": hashes, "source_a6": SOURCE_A6})
	last_error = ""
	return true

func step_index() -> int:
	return -1 if _sessions.is_empty() else int(_sessions.wet.frame.step)

func experiment_hash() -> String:
	return _experiment_hash

func treatment_snapshot() -> Dictionary:
	return _treatment.duplicate(true)

func _headers_match() -> bool:
	if _protocol.is_empty() or not C.keys(_sessions, Protocol.SITES) or not C.keys(_genesis_hashes, Protocol.SITES): return false
	if not Protocol.valid_treatment(_treatment, _protocol): return false
	if _experiment_hash != C.digest({"protocol": C.digest(_protocol), "treatment": _treatment, "genesis": _genesis_hashes, "source_a6": SOURCE_A6}): return false
	var step := -1
	for site in Protocol.SITES:
		var s: Variant = _sessions[site]
		if not s is Dictionary or not s.get("frame") is Dictionary or s.get("genesis_hash") != _genesis_hashes[site]: return false
		if not C.integer(s.frame.get("step"), 0, _protocol.horizon): return false
		if step < 0: step = s.frame.step
		if s.frame.step != step: return false
	return true

func advance() -> bool:
	if not _headers_match(): return _fail("A7_SESSION_BINDING")
	if step_index() >= int(_protocol.horizon): return _fail("A7_HORIZON_BUDGET")
	var candidate := {}
	for site in Protocol.SITES:
		var s: Dictionary = _sessions[site]
		if not s.frame.get("field") is Dictionary: return _fail("A7_FIELD")
		var f: Dictionary = s.frame.field
		var result := A6.advance(s, String(f.get("owner_token", "")), int(f.get("owner_epoch", -1)), s.frame.step)
		if not result.success: return _fail(site + ":" + String(result.error))
		candidate[site] = result.state
	# Commit only after all sites succeeded. A6 returns independent candidates.
	_sessions = candidate
	last_error = ""
	return true

func source_hashes() -> Dictionary:
	var result := {}
	for site in Protocol.SITES:
		if _sessions.has(site): result[site] = _sessions[site].get("integrity_hash", "")
	return result

func observe() -> Dictionary:
	if not _headers_match(): return {"success": false, "error": "A7_SESSION_BINDING"}
	var sites: Array = []
	for site in Protocol.SITES:
		var state: Dictionary = _sessions[site]
		var balance := A6.balance(state) # Includes replay admission before any derived report.
		if balance.has("error"): return {"success": false, "error": balance.error}
		var entries: Array = []
		var living := 0
		for text in state.frame.population:
			var e := LS.deserialize(text)
			if e.is_empty(): return {"success": false, "error": "A7_ENTRY"}
			if e.state.alive: living += 1
			var phenotype := Phenotype.compile(e.state.development, e.blueprint.genome)
			if phenotype.is_empty(): return {"success": false, "error": "A7_PHENOTYPE"}
			entries.append({"id": e.state.individual_id, "alive": e.state.alive, "age_ticks": e.state.age_ticks,
				"blueprint": e.blueprint.duplicate(true), "phenotype": phenotype,
				"reserves": e.state.metabolic_reserves.duplicate(true), "ledger": e.state.resource_ledger.duplicate(true),
				"reproduction_count": e.state.reproduction_count, "starvation_ticks": e.state.starvation_ticks,
				"body_semantics": "LIVE" if e.state.alive else "FROZEN_PROVENANCE_NOT_SPENDABLE"})
		sites.append({"id": site, "source_hash": state.integrity_hash, "genesis_hash": state.genesis_hash,
			"field": state.frame.field.duplicate(true), "living": living, "entries": entries,
			"corpses": state.frame.corpses.duplicate(true), "pending_propagules": state.frame.propagules.size(),
			"returned": state.frame.returned.duplicate(true), "mineralized_mg": state.frame.mineralized_mg,
			"dissipated_energy_mj": state.frame.dissipated_energy_mj, "balance": balance})
	return {"success": true, "schema": "dws.ecology.observatory-report.v1", "source_a6": SOURCE_A6,
		"protocol_hash": C.digest(_protocol), "experiment_hash": _experiment_hash, "step": step_index(),
		"horizon": _protocol.horizon, "treatment": _treatment.duplicate(true), "sites": sites,
		"founder_mutation": Protocol.founding_genome(_treatment, _protocol), "scope": _protocol.scope}

func export_report() -> String:
	var report := observe()
	if not report.success: return ""
	var text := C.encode(report)
	return text if text.to_utf8_buffer().size() <= C.MAX_BYTES else ""

func save_text() -> String:
	if not _headers_match(): return ""
	var sites := {}
	for site in Protocol.SITES:
		var text := A6.serialize(_sessions[site])
		if text.is_empty(): return ""
		sites[site] = text
	var text := C.encode({"schema": SCHEMA, "protocol_hash": C.digest(_protocol), "experiment_hash": _experiment_hash,
		"treatment": _treatment, "step": step_index(), "sessions": sites})
	return text if text.to_utf8_buffer().size() <= C.MAX_BYTES else ""

func load_text(text: String, expected_experiment: String, expected_step: int) -> bool:
	if not F.valid_hash(expected_experiment) or not C.integer(expected_step, 0, 16): return _fail("A7_EXTERNAL_ANCHOR")
	var decoded := C.decode(text)
	if not decoded.success: return _fail("A7_SAVE_ENCODING")
	var v: Variant = decoded.value
	if not C.keys(v, ["schema", "protocol_hash", "experiment_hash", "treatment", "step", "sessions"]) or v.schema != SCHEMA: return _fail("A7_SAVE_SCHEMA")
	if v.experiment_hash != expected_experiment or not C.integer(v.step, 0, 16) or v.step != expected_step: return _fail("A7_EXTERNAL_ANCHOR")
	if not C.keys(v.sessions, Protocol.SITES) or not v.treatment is Dictionary: return _fail("A7_SAVE_SITES")
	# Recreate trusted genesis from the code-owned protocol, not attacker-supplied hashes.
	var candidate = get_script().new()
	if not candidate.start(v.treatment): return _fail("A7_SAVE_TREATMENT")
	if C.digest(candidate._protocol) != v.protocol_hash or candidate.experiment_hash() != expected_experiment: return _fail("A7_PROTOCOL_BINDING")
	var sessions := {}
	for site in Protocol.SITES:
		if not v.sessions[site] is String: return _fail("A7_SITE_PAYLOAD")
		var s := A6.deserialize(v.sessions[site], candidate._genesis_hashes[site], expected_step)
		if s.is_empty(): return _fail("A7_SITE_RESTORE:" + site)
		sessions[site] = s
	_protocol = candidate._protocol.duplicate(true)
	_treatment = candidate._treatment.duplicate(true)
	_genesis_hashes = candidate._genesis_hashes.duplicate(true)
	_experiment_hash = expected_experiment
	_sessions = sessions
	last_error = ""
	return true

func _fail(error: String) -> bool:
	last_error = error
	return false
