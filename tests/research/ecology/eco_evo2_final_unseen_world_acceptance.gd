extends SceneTree

const Challenge = preload("res://scripts/research/ecology/plant_evo2_unseen_world_challenge_v1.gd")
const Protocol = preload("res://scripts/research/ecology/plant_evo2_unseen_world_protocol_v1.gd")
const Persistence = preload("res://scripts/research/ecology/plant_catalog_persistence_v1.gd")
const TamperSupport = preload("res://tests/research/ecology/eco_evo2_e2_8_catalog_persistence_tamper_support.gd")

var assertions := 0
var failed := false

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_check(args.size() == 1, "one persisted E2.8 artifact path is required")
	if args.size() != 1:
		quit(1); return
	var path := String(args[0])
	_check(FileAccess.file_exists(path), "persisted E2.8 artifact exists")
	var bytes := FileAccess.get_file_as_bytes(path)
	_check(not bytes.is_empty(), "persisted artifact bytes load")
	_check(Persistence.transport_sha256(bytes) == Challenge.ACCEPTED_E2_8_TRANSPORT_SHA256, "input is exact accepted E2.8 transport")
	var restored := Persistence.restore(bytes)
	_check(not restored.is_empty(), "fresh process restores persisted artifact")
	_check(String(restored.get("content_hash", "")) == Challenge.ACCEPTED_E2_8_CONTENT_HASH, "E2.8 content identity restored")
	_check(String(restored.get("provenance_hash", "")) == Challenge.ACCEPTED_E2_8_PROVENANCE_HASH, "E2.8 provenance identity restored")
	_check(String(Dictionary(restored.get("species_catalog", {})).get("catalog_hash", "")) == Challenge.ACCEPTED_E2_2_CATALOG_HASH, "full frozen catalog identity restored")
	var protocol := Protocol.build()
	_check(Protocol.validate(protocol), "precommitted hidden-world protocol validates")
	_check(not bool(protocol["target_aware_species_filter_allowed"]), "target-aware species filtering is forbidden")
	_check(not bool(protocol["biome_species_table_allowed"]), "biome species table shortcut is forbidden")
	_check(not bool(protocol["rebake_allowed"]), "rebake is forbidden")
	_check(not bool(protocol["censor_null_reversal"]), "null/reversal outcomes cannot be censored")
	var catalog_before := Dictionary(restored["species_catalog"]).duplicate(true)
	var result := Challenge.run(bytes)
	_check(not result.is_empty(), "final unseen-world challenge executes")
	_check(Challenge.validate_result(bytes, result), "final result replays exactly")
	_check(Dictionary(restored["species_catalog"]) == catalog_before, "restored catalog is not mutated")
	_check(String(result["parent_e2_8_accepted_aggregate"]) == Challenge.PARENT_E2_8_ACCEPTED_AGGREGATE, "E2.8 accepted parent pinned")
	_check(String(result["parent_e2_8_code_under_test"]) == Challenge.PARENT_E2_8_CODE_UNDER_TEST, "E2.8 code-under-test pinned")
	_check(String(result["input_transport_sha256"]) == Challenge.ACCEPTED_E2_8_TRANSPORT_SHA256, "result binds exact persisted bytes")
	_check(String(result["restored_content_hash"]) == Challenge.ACCEPTED_E2_8_CONTENT_HASH, "result binds exact restored content")
	_check(String(result["restored_provenance_hash"]) == Challenge.ACCEPTED_E2_8_PROVENANCE_HASH, "result binds exact provenance")
	_check(String(result["catalog_hash"]) == Challenge.ACCEPTED_E2_2_CATALOG_HASH, "result binds exact catalog")
	_check(String(result["protocol_hash"]) == String(protocol["protocol_hash"]), "result binds precommitted protocol")
	_check(int(result["catalog_entry_count"]) == Array(Dictionary(restored["species_catalog"])["entries"]).size(), "all restored catalog entries remain in challenge input")
	_check(int(result["migration_count"]) == int(result["catalog_entry_count"]), "every restored catalog species receives one source-port migration event")
	_check(not bool(result["rebake_used"]), "no rebake used")
	_check(not bool(result["target_aware_species_filter_used"]), "no target-aware species filter used")
	_check(not bool(result["biome_species_table_used"]), "no biome species table used")
	_check(not bool(result["production_authority_claimed"]), "no production authority claimed")
	_check(not bool(result["null_reversal_censored"]), "all outcome classes retained")
	_check(int(result["reachable_colonized_patches"]) >= Protocol.MIN_REACHABLE_COLONIZED_PATCHES, "both predeclared reachable hidden patches colonize")
	_check(int(result["unique_recruited_species"]) >= Protocol.MIN_UNIQUE_RECRUITED_SPECIES, "at least two restored species recruit causally")
	_check(bool(result["isolated_no_colonization"]), "isolated control remains valid no-colonization")
	_check(int(result["sorting_observed_cells"]) >= Protocol.MIN_SORTING_OBSERVED_CELLS, "ecological sorting observed in predeclared cells")
	_check(int(result["adaptation_positive_cells"]) >= Protocol.MIN_ADAPTATION_POSITIVE_CELLS, "continued adaptation improves at least one predeclared cell")
	_check(bool(result["challenge_passed"]), "all precommitted final gates pass")
	var colonization: Array = result["colonization"]
	_check(colonization.size() == 3, "all three hidden-world target patches reported")
	for value in colonization:
		var record: Dictionary = value
		_check(Array(record["species"]).size() == int(result["catalog_entry_count"]), "colonization evidence retains every restored catalog species")
		_check(String(record["record_hash"]).length() == 64, "colonization record hash present")
	var cells: Array = result["cells"]
	_check(cells.size() == 2, "DRY and WET adaptation cells retained")
	var saw_nonpositive := false
	for value in cells:
		var cell: Dictionary = value
		_check(String(cell["classification"]) in ["ADAPTATION_POSITIVE", "ADAPTATION_NULL", "ADAPTATION_REVERSAL", "SORTING_ONLY", "NO_CHANGE", "VALID_NO_COLONIZATION"], "cell classification is explicit")
		if String(cell["classification"]) != "ADAPTATION_POSITIVE": saw_nonpositive = true
		if String(cell["classification"]) != "VALID_NO_COLONIZATION":
			_check(Dictionary(cell["control"])["adaptation_enabled"] == false, "control arm freezes mutation")
			_check(Dictionary(cell["treatment"])["adaptation_enabled"] == true, "treatment arm enables continued adaptation")
			_check(Dictionary(cell["control"])["initial"] == Dictionary(cell["treatment"])["initial"], "paired arms start from identical colonization-derived founders")
	_check(not bool(protocol["censor_null_reversal"]) or not saw_nonpositive, "non-positive outcomes are never post-hoc censored")
	seed(28082026)
	var expected_rng := [randi(), randi(), randi(), randi()]
	seed(28082026)
	Challenge.run(bytes)
	var actual_rng := [randi(), randi(), randi(), randi()]
	_check(actual_rng == expected_rng, "challenge consumes no global RNG")
	var tamper := TamperSupport.run(restored, bytes)
	for key in ["byte_corruption", "outer_hash", "genome_rehash", "identity_rehash", "provenance_rehash", "wrong_schema", "future_version", "reordered_entries"]:
		_check(bool(tamper.get(key, false)), "E2.8 semantic transport tamper remains fail-closed: " + key)
	var text := bytes.get_string_from_utf8()
	var cp := text.find(":", text.find("payload="))
	var corrupt := text.substr(0, cp - 64) + "0".repeat(64) + text.substr(cp)
	_check(Challenge.run(corrupt.to_utf8_buffer()).is_empty(), "final challenge rejects corrupted persisted input before ecology")
	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_evo2_unseen_world_challenge_v1.gd")
	_check(source.find("Catalog.build") < 0, "challenge has no Catalog.build bypass")
	_check(source.find("plant_accepted_e2_2_catalog_v1.gd") < 0, "challenge has no direct accepted-catalog reconstruction preload")
	_check(source.find("plant_evolution_bake_export_v1.gd") < 0, "challenge has no bake-export preload")
	_check(source.find("plant_species_catalog_v1.gd") < 0, "challenge has no direct SpeciesCatalog builder preload")
	_check(String(result["evidence_hash"]).length() == 64, "final evidence hash present")
	if failed:
		quit(1); return
	print("ECO.EVO2 FINAL Unseen World Challenge: PASS (%d assertions)" % assertions)
	print("evidence_hash=" + String(result["evidence_hash"]))
	print("protocol_hash=" + String(result["protocol_hash"]))
	print("transport_sha256=" + String(result["input_transport_sha256"]))
	print("catalog_hash=" + String(result["catalog_hash"]))
	print("reachable_colonized_patches=" + str(int(result["reachable_colonized_patches"])))
	print("unique_recruited_species=" + str(int(result["unique_recruited_species"])))
	print("isolated_no_colonization=" + str(bool(result["isolated_no_colonization"])))
	print("sorting_observed_cells=" + str(int(result["sorting_observed_cells"])))
	print("adaptation_positive_cells=" + str(int(result["adaptation_positive_cells"])))
	for value in cells:
		var cell: Dictionary = value
		print("cell_%s_classification=%s" % [String(cell["patch_id"]).get_file(), String(cell["classification"])])
		print("cell_%s_adaptation_gain=%.12f" % [String(cell["patch_id"]).get_file(), float(cell["adaptation_gain"])])
	quit(0)

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition: return
	failed = true
	push_error("ECO.EVO2 FINAL assertion failed: " + label)
