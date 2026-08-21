extends SceneTree

const Persistence = preload("res://scripts/research/ecology/plant_catalog_persistence_v1.gd")
const Catalog = preload("res://scripts/research/ecology/plant_accepted_e2_2_catalog_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Tamper = preload("res://tests/research/ecology/eco_evo2_e2_8_catalog_persistence_tamper_support.gd")

var assertions := 0
var failed := false

func _init() -> void:
	var reconstructed_catalog_a := Catalog.build()
	var reconstructed_catalog_b := Catalog.build()
	_check(not reconstructed_catalog_a.is_empty(), "full accepted E2.2 SpeciesCatalog independently reconstructs")
	_check(Catalog.validate(reconstructed_catalog_a), "reconstructed full catalog validates against frozen fixture semantics")
	_check(reconstructed_catalog_a == reconstructed_catalog_b, "accepted full catalog reconstruction is deterministic")
	_check(String(reconstructed_catalog_a["catalog_hash"]) == Catalog.ACCEPTED_HASH, "independent reconstruction reproduces exact accepted E2.2 catalog hash")
	_check(String(reconstructed_catalog_a["bake_id"]) == "eco-evo2-bake/ff406486cc83bb8217d66213", "exact E2.2 deterministic bake id reconstructed")
	_check(String(reconstructed_catalog_a["source_run_hash"]) == Catalog.SOURCE_RUN_HASH, "catalog preserves exact E2.2 source run hash")
	_check(not bool(reconstructed_catalog_a["canonical_species_declared"]), "accepted catalog remains research taxonomy only")
	var reconstructed_entries: Array = reconstructed_catalog_a["entries"]
	_check(reconstructed_entries.size() == 2, "full catalog contains exactly two accepted entries")
	_check(Catalog._exact(Dictionary(reconstructed_entries[0]), Catalog.ENTRY_FIELDS), "first persisted entry retains full SpeciesCatalog entry shape")
	_check(Catalog._exact(Dictionary(reconstructed_entries[1]), Catalog.ENTRY_FIELDS), "second persisted entry retains full SpeciesCatalog entry shape")

	var artifact_a := Persistence.build_artifact()
	var artifact_b := Persistence.build_artifact()
	_check(not artifact_a.is_empty(), "artifact builds")
	_check(Persistence.validate_artifact(artifact_a), "artifact validates")
	_check(artifact_a == artifact_b, "same input yields identical semantic artifact")
	_check(String(artifact_a["schema"]) == Persistence.SCHEMA, "persistence schema pinned")
	_check(String(artifact_a["version"]) == Persistence.VERSION, "persistence version pinned")
	_check(String(artifact_a["encoding"]) == Persistence.ENCODING, "encoding pinned")
	_check(bool(artifact_a["research_only"]), "research-only boundary explicit")
	_check(not bool(artifact_a["production_save_authority_claimed"]), "no production save authority")
	_check(not bool(artifact_a["distributed_durability_claimed"]), "no distributed durability claim")
	_check(not bool(artifact_a["canonical_taxonomy_claimed"]), "no canonical taxonomy claim")
	_check(not bool(artifact_a["world_transaction_semantics_claimed"]), "no world transaction semantics claim")

	var catalog: Dictionary = artifact_a["species_catalog"]
	_check(catalog == reconstructed_catalog_a, "artifact persists the full exact reconstructed accepted SpeciesCatalog")
	_check(Catalog.validate(catalog), "persisted full SpeciesCatalog validates")
	_check(String(catalog["catalog_hash"]) == Catalog.ACCEPTED_HASH, "accepted E2.2 catalog hash retained")
	_check(String(catalog["bake_id"]) == "eco-evo2-bake/ff406486cc83bb8217d66213", "accepted deterministic bake id retained")
	var entries: Array = catalog["entries"]
	_check(String(entries[0]["research_species_id"]) == "eco-research-species/247a0b301db2781bfc317a13", "canonical first research species retained")
	_check(String(entries[0]["lineage_id"]) == "eco-lineage/e22-beta", "first source lineage retained")
	_check(String(entries[0]["genome_checksum"]) == "a4c391bd696aea19075f7b7ff42122401db65644b038d7983d89f18102e9eff6", "first frozen genome checksum retained")
	_check(String(entries[0]["source_observation_hash"]) == "7bbbec07fb4199166147d7556ac2984156b4a5d24d3b922728e18652b884edf3", "first source observation identity retained")
	_check(String(entries[0]["entry_hash"]) == "058efd7836bdceec9b39c6a2b5c46b013d4bafd14c7b0da92e3a75b406046ec2", "first full catalog entry hash retained")
	_check(String(entries[1]["research_species_id"]) == "eco-research-species/34b4de11b3cbb2eae9f73176", "canonical second research species retained")
	_check(String(entries[1]["lineage_id"]) == "eco-lineage/e22-alpha", "second source lineage retained")
	_check(String(entries[1]["genome_checksum"]) == "ebed17aadaf721218d91af4c07bc1242700151fdad8d3f614b43e751de607383", "second frozen genome checksum retained")
	_check(String(entries[1]["source_observation_hash"]) == "11bd55d59969080dd0c9809141b694851e7ba9b41d26c7545fdeadb4ff799b40", "second source observation identity retained")
	_check(String(entries[1]["entry_hash"]) == "0b7485141737c5dea6bb86ba3fbbc0dc586ad2bc845584e018733eacf0f2b4fa", "second full catalog entry hash retained")
	_check(bool(PlantGenome.validate(Dictionary(entries[0]["genome"])).get("success", false)), "first genome semantically valid")
	_check(bool(PlantGenome.validate(Dictionary(entries[1]["genome"])).get("success", false)), "second genome semantically valid")

	var provenance: Dictionary = artifact_a["provenance"]
	_check(provenance == Persistence.expected_provenance(), "full E2.1-E2.7 provenance is exact")
	_check(bool(provenance["e2_2_source_is_synthetic_contract_fixture"]), "synthetic E2.2 fixture provenance remains explicit")
	_check(not bool(provenance["e2_2_source_impersonates_accepted_evolution_result"]), "synthetic source never impersonates real evolved result")
	_check(String(provenance["e2_2_source_hash"]) == "c165964f710036287b9e8d310085a662d004b05eecc0c915ad1d3650a18dedb9", "E2.2 source hash pinned")
	_check(String(provenance["e2_7_accepted_aggregate"]) == "eb3b30919114cb9971b7413f416a3ae07eb50aebe81801454aaa310d6e879c7d", "E2.7 accepted parent pinned")
	_check(String(provenance["e2_7_code_under_test"]) == "52f31ca58a77296d63b1642954659edcbd12b8fe", "E2.7 code-under-test pinned")
	_check(String(provenance["e2_7_validation_blob"]) == "da445b41cf0d85ea83525eabba25e56380c7c87c", "E2.7 durable validation identity pinned")
	_check(String(artifact_a["provenance_hash"]) == Persistence.hash_variant(provenance), "provenance hash exact")
	_check(String(artifact_a["content_hash"]) == Persistence.compute_content_hash(artifact_a), "content hash exact")

	var bytes_a := Persistence.serialize(artifact_a)
	var bytes_b := Persistence.serialize(artifact_b)
	_check(not bytes_a.is_empty(), "canonical transport bytes produced")
	_check(bytes_a == bytes_b, "same input yields byte-identical transport")
	_check(Persistence.transport_sha256(bytes_a) == Persistence.transport_sha256(bytes_b), "same input yields identical transport hash")
	var restored := Persistence.restore(bytes_a)
	_check(not restored.is_empty(), "canonical transport restores")
	_check(restored == artifact_a, "restore yields exact semantic artifact identity")
	_check(Dictionary(restored["species_catalog"]) == catalog, "restore preserves full exact SpeciesCatalog identity")
	_check(Dictionary(restored["provenance"]) == provenance, "restore preserves exact provenance")
	_check(Persistence.serialize(restored) == bytes_a, "restore reserializes to byte-identical transport")

	_check(Persistence.classify_version(Persistence.SCHEMA, Persistence.VERSION) == "CURRENT_VERSION", "current persistence version accepted")
	_check(Persistence.KNOWN_COMPATIBLE_VERSIONS.is_empty(), "no compatibility version is invented")
	_check(Persistence.classify_version(Persistence.SCHEMA, "2.0.0") == "UNKNOWN_NEWER", "unknown newer version classified fail-closed")
	_check(Persistence.classify_version(Persistence.SCHEMA, "0.9.0") == "UNDECLARED_OLDER", "undeclared older version classified fail-closed")
	_check(Persistence.classify_version(Persistence.SCHEMA, "1.x.0") == "MALFORMED", "malformed version rejected")
	_check(Persistence.classify_version("wrong.schema", Persistence.VERSION) == "WRONG_SCHEMA", "wrong schema rejected")

	var tamper := Tamper.run(artifact_a, bytes_a)
	_check(bool(tamper.get("byte_corruption",false)), "byte corruption rejected before semantic decode")
	_check(bool(tamper.get("outer_hash",false)), "outer transport hash corruption rejected")
	_check(bool(tamper.get("content_hash",false)), "content hash corruption rejected")
	_check(bool(tamper.get("genome_rehash",false)), "genome mutation rejected after full nested and transport rehash")
	_check(bool(tamper.get("identity_rehash",false)), "species and lineage substitution rejected after full rehash")
	_check(bool(tamper.get("provenance_rehash",false)), "provenance substitution rejected after full rehash")
	_check(bool(tamper.get("extra_field",false)), "unexpected artifact field rejected")
	_check(bool(tamper.get("missing_field",false)), "missing artifact field rejected")
	_check(bool(tamper.get("entry_extra_field",false)), "unexpected SpeciesCatalog entry field rejected")
	_check(bool(tamper.get("wrong_schema",false)), "internal schema substitution rejected")
	_check(bool(tamper.get("future_version",false)), "unknown future internal version rejected")
	_check(bool(tamper.get("reordered_entries",false)), "reordered canonical catalog entries rejected after rehash")
	_check(bool(tamper.get("catalog_identity",false)), "accepted catalog identity substitution rejected")

	seed(28082026)
	var expected_rng := [randi(), randi(), randi(), randi()]
	seed(28082026)
	Persistence.serialize(Persistence.build_artifact())
	var actual_rng := [randi(), randi(), randi(), randi()]
	_check(actual_rng == expected_rng, "persistence build and serialization consume no global RNG")

	if failed:
		quit(1)
		return
	var aggregate := "\n".join(PackedStringArray([
		String(artifact_a["content_hash"]),
		String(artifact_a["provenance_hash"]),
		Persistence.transport_sha256(bytes_a),
		String(catalog["catalog_hash"]),
		String(provenance["e2_7_accepted_aggregate"]),
	])).sha256_text()
	print("ECO.EVO2 E2.8 Catalog Persistence & Provenance: PASS (%d assertions)" % assertions)
	print("aggregate_hash=" + aggregate)
	print("content_hash=" + String(artifact_a["content_hash"]))
	print("provenance_hash=" + String(artifact_a["provenance_hash"]))
	print("transport_sha256=" + Persistence.transport_sha256(bytes_a))
	print("catalog_hash=" + String(catalog["catalog_hash"]))
	print("bake_id=" + String(catalog["bake_id"]))
	print("artifact_bytes=" + str(bytes_a.size()))
	print("parent_e2_7=" + String(provenance["e2_7_accepted_aggregate"]))
	quit(0)

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		return
	failed = true
	push_error("ECO.EVO2 E2.8 assertion failed: " + label)
