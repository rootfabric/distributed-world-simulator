extends RefCounted
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const SCHEMA := "distributed_world_simulator.ecology.evo2_species_catalog.v1"
const ENTRY_SCHEMA := SCHEMA + ".entry"
const VERSION := "1.0.0"
const SPECIES_CONCEPT := "ECO_RESEARCH_LINEAGE_HYPOTHESIS_V1"
const PARENT_P2_7 := "7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe"
const BAKE_ID := "eco-evo2-bake/ff406486cc83bb8217d66213"
const SOURCE_RUN_HASH := "d44a160531d7f49cd0d0018a1fa8cb55d6be8ebf8157e5cb555232b8dd0fb337"
const ACCEPTED_HASH := "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219"
const CATALOG_FIELDS: Array[String] = ["schema","version","species_concept","parent_p2_7_accepted_aggregate","bake_id","source_run_hash","canonical_species_declared","entries","catalog_hash"]
const ENTRY_FIELDS: Array[String] = ["schema","version","research_species_id","lineage_id","ancestry_path","parent_lineage_id","split_year","genome","genome_checksum","recruitment_traits","recruitment_traits_checksum","observed_patch_ids","source_observation_hash","canonical_species_declared","entry_hash"]

static func build() -> Dictionary:
	var beta_g := PlantGenome.create("genome/e22-beta",0.8,0.72,0.6,0.70,0.28,0.28,360,28.0,3.0)
	var alpha_g := PlantGenome.create("genome/e22-alpha-late",1.5,0.54,1.7,0.34,0.25,0.65,130,16.0,8.5)
	var beta_r := RecruitmentTraits.create("recruit/e22-beta",0.18,1.8)
	var alpha_r := RecruitmentTraits.create("recruit/e22-alpha",0.38,4.5)
	if String(beta_g.get("checksum","")) != "a4c391bd696aea19075f7b7ff42122401db65644b038d7983d89f18102e9eff6" or String(alpha_g.get("checksum","")) != "ebed17aadaf721218d91af4c07bc1242700151fdad8d3f614b43e751de607383": return {}
	var entries: Array = [
		_entry("eco-lineage/e22-beta",1,beta_g,beta_r,"patch/beta","7bbbec07fb4199166147d7556ac2984156b4a5d24d3b922728e18652b884edf3","058efd7836bdceec9b39c6a2b5c46b013d4bafd14c7b0da92e3a75b406046ec2"),
		_entry("eco-lineage/e22-alpha",2,alpha_g,alpha_r,"patch/alpha","11bd55d59969080dd0c9809141b694851e7ba9b41d26c7545fdeadb4ff799b40","0b7485141737c5dea6bb86ba3fbbc0dc586ad2bc845584e018733eacf0f2b4fa"),
	]
	if Dictionary(entries[0]).is_empty() or Dictionary(entries[1]).is_empty(): return {}
	var c := {"schema":SCHEMA,"version":VERSION,"species_concept":SPECIES_CONCEPT,"parent_p2_7_accepted_aggregate":PARENT_P2_7,"bake_id":BAKE_ID,"source_run_hash":SOURCE_RUN_HASH,"canonical_species_declared":false,"entries":entries}
	c["catalog_hash"] = compute_catalog_hash(c)
	return c if String(c["catalog_hash"]) == ACCEPTED_HASH else {}

static func validate(c: Dictionary) -> bool:
	return _exact(c,CATALOG_FIELDS) and c == build() and String(c.get("catalog_hash","")) == ACCEPTED_HASH and compute_catalog_hash(c) == ACCEPTED_HASH

static func _entry(lineage: String, split: int, genome: Dictionary, traits: Dictionary, patch: String, obs_hash: String, expected_hash: String) -> Dictionary:
	if not bool(PlantGenome.validate(genome).get("success",false)) or not RecruitmentTraits.validate(traits): return {}
	var ancestry := ["eco-lineage/e22-root",lineage]
	var e := {"schema":ENTRY_SCHEMA,"version":VERSION,"research_species_id":research_species_id(lineage),"lineage_id":lineage,"ancestry_path":ancestry,"parent_lineage_id":"eco-lineage/e22-root","split_year":split,"genome":genome.duplicate(true),"genome_checksum":String(genome["checksum"]),"recruitment_traits":traits.duplicate(true),"recruitment_traits_checksum":String(traits["checksum"]),"observed_patch_ids":[patch],"source_observation_hash":obs_hash,"canonical_species_declared":false}
	e["entry_hash"] = compute_entry_hash(e)
	return e if String(e["entry_hash"]) == expected_hash else {}

static func research_species_id(lineage: String) -> String:
	return "eco-research-species/%s" % "|".join(PackedStringArray([SCHEMA,VERSION,SPECIES_CONCEPT,lineage])).sha256_text().substr(0,24)

static func compute_entry_hash(e: Dictionary) -> String:
	var t := PackedStringArray([ENTRY_SCHEMA,VERSION,String(e.get("research_species_id","")),String(e.get("lineage_id","")),String(e.get("parent_lineage_id","")),str(int(e.get("split_year",-1))),String(e.get("genome_checksum","")),String(e.get("recruitment_traits_checksum","")),String(e.get("source_observation_hash","")),"canonical_species_declared=false"])
	for v in Array(e.get("ancestry_path",[])): t.append("ancestor="+String(v))
	for v in Array(e.get("observed_patch_ids",[])): t.append("patch="+String(v))
	return "\n".join(t).sha256_text()

static func compute_catalog_hash(c: Dictionary) -> String:
	var t := PackedStringArray([SCHEMA,VERSION,SPECIES_CONCEPT,PARENT_P2_7,String(c.get("bake_id","")),String(c.get("source_run_hash","")),"canonical_species_declared=false"])
	for v in Array(c.get("entries",[])): t.append(String(Dictionary(v).get("entry_hash","")))
	return "\n".join(t).sha256_text()

static func _exact(v: Dictionary, fields: Array[String]) -> bool:
	if v.keys().size()!=fields.size(): return false
	for f in fields:
		if not v.has(f): return false
	for k in v.keys():
		if not String(k) in fields: return false
	return true
