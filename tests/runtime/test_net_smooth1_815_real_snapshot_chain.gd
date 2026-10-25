extends SceneTree

# Actual immutable v1 contracts + separate un-routed v2 numeric candidate.
# Deterministic synthetic two-player Earth DTO states, NOT historical packets.
const Chain = preload("res://tests/runtime/support/r31_815_real_snapshot_chain.gd")
const V2 = preload("res://scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot_v2.gd")

var checks: int = 0
var failures: Array[String] = []
var old_failures: int = 0
var v2_failures: int = 0
var first_stages: Dictionary = {}
var witnesses: Array[Dictionary] = []
var max_packet_bytes: int = 0
var total_v1_bytes: int = 0
var total_v2_bytes: int = 0


func _init() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func v2_roundtrip(full: Dictionary, index: int) -> Dictionary:
	var before: String = Chain.Utils.canonical_json(full)
	var packed: Dictionary = V2.encode(full)
	check(bool(packed["success"]), "v2 packs validated FullSnapshot %d" % index)
	if not bool(packed["success"]):
		v2_failures += 1
		return {}
	var body: Dictionary = packed["details"]["snapshot"]
	check(body["c"] == full["checksum"], "no rewriting of original full c %d" % index)
	var frame: Dictionary = Chain.create_frame(body, index)
	var encoded: Dictionary = Chain.Frame.encode(frame)
	check(bool(encoded["success"]), "original Frame.encode accepts v2 %d" % index)
	if not bool(encoded["success"]):
		v2_failures += 1
		return {}
	var packet: PackedByteArray = encoded["details"]["packet"]
	total_v2_bytes += packet.size()
	max_packet_bytes = maxi(max_packet_bytes, packet.size())
	var received: Dictionary = Chain.Frame.decode(packet)
	check(bool(received["success"]), "original strict receiver accepts exact v2 bytes %d" % index)
	if not bool(received["success"]):
		v2_failures += 1
		return {}
	var decoded: Dictionary = V2.decode(received["details"]["frame"]["payload"]["snapshot"])
	check(bool(decoded["success"]), "v2 restores full source and validates original c %d" % index)
	if not bool(decoded["success"]):
		v2_failures += 1
		return {}
	var restored: Dictionary = decoded["details"]["snapshot"]
	check(Chain.first_numeric_change(full, restored).is_empty(), "all source f64 bits preserved %d" % index)
	check(Chain.Utils.canonical_json(restored) == before, "full checksum/authority/session/sequence preserved %d" % index)
	check(Chain.Utils.canonical_json(full) == before, "caller FullSnapshot unmodified %d" % index)
	check(Chain.Utils.canonical_json(received["details"]["frame"]).to_utf8_buffer() == packet,
		"exact canonical packet stays canonical after receiver parse %d" % index)
	return {"body": body, "packet": packet, "snapshot": restored}


func rehash_h(value: Dictionary) -> void:
	value.erase("h")
	value["h"] = Chain.Utils.payload_hash(value)


func negative_tests(full: Dictionary) -> void:
	var base: Dictionary = V2.encode(full)["details"]["snapshot"]
	check(not bool(Chain.Compact.decode(base)["success"]), "legacy v1 receiver refuses v2; never silent migration")
	var old: Dictionary = Chain.Compact.encode(full)["details"]["snapshot"]
	check(not bool(V2.decode(old)["success"]), "v2 decoder refuses legacy schema")
	var altered: Dictionary = base.duplicate(true)
	altered["p"][0]["p"][0] = "0000000000000040"
	check(String(V2.decode(altered)["error_code"]) == "COMPACT_GAMEPLAY_SNAPSHOT_CHECKSUM_MISMATCH",
		"unrehashed payload corruption rejects original h")
	altered = base.duplicate(true)
	altered["c"] = "0".repeat(64)
	rehash_h(altered) # Isolate NESTED c check; never done in product decoder.
	var inner: Dictionary = V2.decode(altered)
	check(String(inner["error_code"]) == "COMPACT_GAMEPLAY_SNAPSHOT_DECODE_FAILED"
		and String(inner.get("details", {}).get("cause", {}).get("error_code", "")) == "MULTIPLAYER_SNAPSHOT_CHECKSUM_MISMATCH",
		"even with valid outer h the original full c refuses corruption")
	for malformed in ["0", "000000000000F03F", "000000000000g03f", "000000000000f07f", "000000000000f87f"]:
		altered = base.duplicate(true)
		altered["p"][0]["y"] = malformed
		rehash_h(altered)
		check(not bool(V2.decode(altered)["success"]), "malformed/nonfinite float rejected: " + malformed)
	altered = base.duplicate(true)
	altered["nf"] = "UNNEGOTIATED_FORMAT"
	rehash_h(altered)
	check(String(V2.decode(altered)["error_code"]) == "UNSUPPORTED_COMPACT_NUMERIC_SCHEMA", "unknown representation denied")
	altered = base.duplicate(true)
	altered["p"][0]["s"] = "foreign-session"
	rehash_h(altered)
	check(not bool(V2.decode(altered)["success"]), "original FullSnapshot session validator still active")
	altered = base.duplicate(true)
	altered["e"] = 0
	rehash_h(altered)
	check(not bool(V2.decode(altered)["success"]), "zero authority epoch denied")
	altered = base.duplicate(true)
	altered["extra"] = 1
	rehash_h(altered)
	check(not bool(V2.decode(altered)["success"]), "unknown envelope field denied")
	var frame: Dictionary = Chain.create_frame(base, 3001)
	var encoded: Dictionary = Chain.Frame.encode(frame)
	var packet: PackedByteArray = encoded["details"]["packet"]
	var tampered: PackedByteArray = packet.duplicate()
	var offset: int = packet.get_string_from_utf8().find("MOVEMENT_NETWORK_TICK")
	check(offset > 0, "ASCII byte-tamper target found")
	if offset > 0:
		tampered[offset] = tampered[offset] ^ 1
		check(String(Chain.Frame.decode(tampered)["error_code"]) == "PAYLOAD_CHECKSUM_MISMATCH",
			"genuine raw byte tamper still rejected by original Frame.decode")
	check(String(Chain.Frame.encode(frame, 32)["error_code"]) == "PACKET_TOO_LARGE", "wire packet size limit untouched")
	for scalar_bits in ["0000000000000080", "0100000000000000", "0000000000001000", "391e0df76695bebc", "000000000000f03f"]:
		var x: float = Chain.from_bits(scalar_bits)
		var restored: Dictionary = V2._unpack64(V2._pack64(x))
		check(bool(restored["success"]) and Chain.bits(restored["details"]["value"]) == scalar_bits,
			"numeric representation exactly preserves signed-zero/subnormal/normal bits " + scalar_bits)
	check(checks > 20, "negative tests exercised native strict validators")


func _run() -> void:
	var start: int = Time.get_ticks_usec()
	check(V2._platform_supported(), "explicit f64le canary valid on pinned Godot double")
	var fixed: Dictionary = Chain.make_full(Chain.fixed_witness_players(), 84)
	var witness: Dictionary = Chain.inspect_v1(fixed, 84)
	check(not witness.has("fatal_stage"), "frozen witness traversed original real chain")
	check(witness.get("first_broken_stage") == "FRAME_CREATE_JSON", "first break occurs in Frame.create JSON-roundtrip")
	check(witness.get("first_broken_checksums") == ["h", "c"], "both inner checksums h and c first fail, not original Full.create")
	check(witness.get("receiver_error") == "PAYLOAD_CHECKSUM_MISMATCH", "outer packet rejected by original receiver")
	check(witness.get("first_frame_create_numeric_change", {}).get("path") == "$.payload.snapshot.p[0].v[1]",
		"exact first changed scalar is player A vertical velocity")
	check(witness.get("first_frame_create_numeric_change", {}).get("before_f64le") == "381e0df76695bebc"
		and witness.get("first_frame_create_numeric_change", {}).get("after_f64le") == "391e0df76695bebc",
		"exact one-bit float two-cycle recorded without rounding")
	witnesses.append(witness)
	v2_roundtrip(fixed, 84)
	var fixed_v2_bytes: int = total_v2_bytes
	total_v2_bytes = 0
	negative_tests(Chain.make_full([Chain.player("a", 1, Vector3(1, 2, 3), Vector3.ZERO, 0.0),
		Chain.player("b", 1, Vector3(4, 5, 6), Vector3.ZERO, 0.0)], 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = Chain.CORPUS_SEED
	for index in range(1, Chain.CORPUS_COUNT + 1):
		var players: Array = Chain.generated_players(rng, index)
		var original: String = Chain.Utils.canonical_json(players)
		var full: Dictionary = Chain.make_full(players, index)
		check(Chain.Utils.canonical_json(players) == original, "original authoritative input DTO not mutated %d" % index)
		var old: Dictionary = Chain.inspect_v1(full, index)
		check(not old.has("fatal_stage"), "original production chain traversal %d" % index)
		if old.has("fatal_stage"):
			continue
		total_v1_bytes += int(old["packet_bytes"])
		var stage: String = String(old["first_broken_stage"])
		first_stages[stage] = int(first_stages.get(stage, 0)) + 1
		if stage != "NONE":
			old_failures += 1
			if witnesses.size() < 32:
				witnesses.append(old)
		v2_roundtrip(full, index)
	check(old_failures > 0, "legacy RED reproduced in full two-player Earth-contract chain")
	check(v2_failures == 0, "candidate v2 GREEN on same complete deterministic corpus")
	var result: Dictionary = {
		"schema": "dws.net_smooth.815.real_snapshot_chain.v1",
		"engine": Engine.get_version_info().get("string", ""),
		"seed": Chain.CORPUS_SEED, "cases": Chain.CORPUS_COUNT,
		"original_sources": Chain.source_fingerprints(),
		"fixture_kind": "DETERMINISTIC_EARTH_LOCAL_DTO_NOT_LIVE_INCIDENT",
		"legacy_failures": old_failures, "v2_failures": v2_failures,
		"first_failure_stages": first_stages, "witnesses": witnesses,
		"assertions": checks, "failures": failures,
		"v1_packet_bytes_total_corpus": total_v1_bytes,
		"v2_packet_bytes_total_corpus": total_v2_bytes,
		"fixed_witness_v2_packet_bytes": fixed_v2_bytes,
		"v2_max_packet_bytes": max_packet_bytes,
		"elapsed_ms": float(Time.get_ticks_usec() - start) / 1000.0,
		"live_network_activation": false, "historical_incident_proven": false,
		"ready_for_merge": false,
	}
	var output: String = OS.get_environment("DWS_815_CHAIN_REPORT_PATH")
	if output.is_empty():
		output = "res://artifacts/net-smooth1/815-real-chain/report.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	check(file != null, "evidence output writable")
	result["assertions"] = checks
	result["failures"] = failures.duplicate()
	if file != null:
		file.store_string(JSON.stringify(result, "\t", true, true) + "\n")
		file.close()
	for failure in failures:
		push_error("NS1_815_REAL_CHAIN_FAIL:" + failure)
	print("NS1_815_REAL_CHAIN %s assertions=%d failures=%d legacy_red=%d v2_green=%d/%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(), old_failures,
		Chain.CORPUS_COUNT - v2_failures, Chain.CORPUS_COUNT])
	quit(0 if failures.is_empty() else 1)
