extends SceneTree
const Gate = preload("res://scripts/research/ecology/plant_competition_robustness_gate_v1.gd")
const EXPECTED := {
	"1138701|18|false": {"dynamic":"57881819ca113ace9bec0ae8c5a66a9a45d4164069bbf506c462bb29cd82d20f","diagnostic":"e3202b0afd3fb746ee6bd36b76a88b22e1957e070f4c5f6728b9849eaeb39f94","case":"431c4b6c0683b692c9fe88fbc912f49c3659db122c8fdf2715f525ea712dc43b"},
	"1138702|18|false": {"dynamic":"383c1e8c93d723dfdbdc3e89a9244ae28b28a9590ffe8604f78e2338f56ac64e","diagnostic":"a1b23a2e1ff284b490a832087eadfb9489a93b7f8db3d5ff959de75ff0f7d6cc","case":"da7eaf61254bded7a52891abccbc2fb9130477bbde2c3fd6e440d83ebb3d42c0"},
	"1138703|18|false": {"dynamic":"c19e1e613501a7a95799da6cd2c96f218aeec137cd4c4740d4e925b32b0afd5a","diagnostic":"16badaab797f6aa2fef991ad86605afe54ed5e2d3781134afad1725f075c27c2","case":"def061b2da3e350f43138c7c8519436c0eee168b2bffd4a69eee40499b50d6c9"},
	"1138704|18|false": {"dynamic":"9eff83698d937df2b17ec7a62e941fdd017ca299894d29a696aede13f1001707","diagnostic":"9a8c7c80a16ebbd5a8cfdec2a76a3932652809eb69809d8db3d2782d1e67a0c5","case":"35801d690cb0f6fcbce63aa8abbcbdd85acadd7211b513855816325fea985cb5"},
	"1138705|18|false": {"dynamic":"5d8370d24d7c16643011328e8709a38e8500a17990fcb5607f158ff06b7d50a2","diagnostic":"d82b1ca0df3c84312f32d41566568f463dc57808bb56bf670ebd46d798246099","case":"9714233b780bd901187c9dc9e1a6881ee15f4b6bd95376fea74b70629efbd3bc"},
	"1138706|18|false": {"dynamic":"8ade6a6f622239d051acb3a06a9c9712f50fd7b9cbb1c683d68ada21851246c8","diagnostic":"a6686a7f07cdbe392361f0d964230346cd3c4e1baa21dfcaa9fb888e1371a286","case":"4da5daf6d51686de2d017500cf035aa9f91778d62592d27016a66fdf6f1dab9e"},
	"1138701|18|true": {"dynamic":"4fbae51d8c73b79f2e8c13883e0b801c8edad04473faa70642612dbd7d69485d","diagnostic":"4f4e26f3f5e10f40fa6d669b58d140dc72f36003248acf4e2b757af542e20371","case":"8f27fb89d87d7b92911efcb80ae461d2d0f32ff169ed8f3efbdf73a296d67d47"},
	"1138701|24|false": {"dynamic":"6f94f5118e2304258915c1d072c5296ea291347b3fe1a44d75a4c44d78c52cbc","diagnostic":"219de6b85725bfaaf747148c498cf6613adcebf549654286ce3d4fb5518c1ef4","case":"ca49a238f82303ac6ad7e36d10f849baff07442873ab3b20c22d2d32f9f34411"},
}
var assertions := 0
var failures: Array[String] = []
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("ECO.P1C-S4 requires <founder_seed> <cycles> <true|false>")
		quit(2); return
	var seed := int(args[0]); var cycles := int(args[1]); var uniform := String(args[2]).to_lower() == "true"
	var key := "%d|%d|%s" % [seed, cycles, str(uniform)]
	if not EXPECTED.has(key): push_error("Unsupported S4 case: %s" % key); quit(2); return
	var expected: Dictionary = EXPECTED[key]
	var r := Gate.run_case(seed, cycles, uniform)
	_check(not r.is_empty(), "case exists")
	_check(int(r.get("founder_seed",0)) == seed, "seed recorded")
	_check(int(r.get("cycles",0)) == cycles, "cycles recorded")
	_check(bool(r.get("uniform_control",false)) == uniform, "control recorded")
	_check(String(r.get("dynamic_result_hash","")).length() == 64, "dynamic hash present")
	_check(String(r.get("diagnostic_hash","")).length() == 64, "diagnostic hash present")
	_check(String(r.get("case_hash","")).length() == 64, "case hash present")
	_check(String(r.get("dynamic_result_hash","")) == String(expected["dynamic"]), "dynamic hash exact")
	_check(String(r.get("diagnostic_hash","")) == String(expected["diagnostic"]), "diagnostic hash exact")
	_check(String(r.get("case_hash","")) == String(expected["case"]), "case hash exact")
	_check(bool(r.get("founder_traits_bounded",false)), "founder traits remain bounded")
	var fm: Dictionary = r["failure_matrix"]
	_check(String(fm["GLOBAL_TAKEOVER"]) == "PASS", "no global takeover")
	_check(String(fm["RUNAWAY_TRAIT"]).begins_with("PASS"), "no runaway trait")
	if uniform:
		_check(String(fm["DIVERSITY_COLLAPSE"]).begins_with("NOT_APPLICABLE"), "uniform diversity is an expected negative control")
		_check(String(fm["FALSE_NICHE_UNIFORM"]) == "PASS", "uniform has no false niches")
		_check(int(r["niche_enriched_cluster_count"]) == 0, "uniform niche count zero")
		_check(float(r["max_niche_enrichment_span"]) <= Gate.UNIFORM_MAX_NICHE_SPAN, "uniform enrichment flat")
	else:
		_check(String(fm["DIVERSITY_COLLAPSE"]) == "PASS", "no diversity collapse")
		_check(String(fm["CLUSTER_COLLAPSE"]) == "PASS", "clusters persist")
		_check(int(r["effective_founders_1pct"]) >= Gate.MIN_EFFECTIVE_FOUNDERS_1PCT, "effective diversity retained")
		_check(float(r["top1_biomass_share"]) < Gate.MAX_TOP1_BIOMASS_SHARE, "leader below takeover threshold")
		_check(float(r["shannon_biomass_diversity"]) >= Gate.MIN_SHANNON_DIVERSITY, "Shannon diversity retained")
		_check(int(r["substantial_cluster_count"]) >= Gate.MIN_SUBSTANTIAL_CLUSTERS, "three substantial clusters")
		_check(int(r["niche_enriched_cluster_count"]) >= Gate.MIN_NICHE_ENRICHED_CLUSTERS, "multiple niche-enriched clusters")
	_test_source_boundaries()
	print("ECO.P1C-S4 seed=%d cycles=%d uniform=%s dynamic=%s diagnostic=%s case=%s eff1=%d top=%.6f shannon=%.6f clusters=%d niches=%d failures=%s" % [seed,cycles,str(uniform),String(r.get("dynamic_result_hash","")),String(r.get("diagnostic_hash","")),String(r.get("case_hash","")),int(r.get("effective_founders_1pct",0)),float(r.get("top1_biomass_share",0.0)),float(r.get("shannon_biomass_diversity",0.0)),int(r.get("substantial_cluster_count",0)),int(r.get("niche_enriched_cluster_count",0)),str(r.get("failure_matrix",{}))])
	_finish()
func _test_source_boundaries() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_competition_robustness_gate_v1.gd").to_lower()
	_check(not source.contains("species"), "no species rules")
	_check(not source.contains("biome"), "no biome rules")
	_check(not source.contains("migration"), "no migration")
	_check(not source.contains("camera"), "no presentation input")
	_check(not source.contains("authority"), "no authority input")
	_check(not source.contains("network"), "no network input")
	_check(source.contains("dynamic.run"), "uses accepted abundance dynamics")
	_check(source.contains("diagnostics.diagnose"), "uses accepted niche diagnostics")
	_check(source.contains("global_takeover"), "explicit takeover failure class")
	_check(source.contains("false_niche_uniform"), "explicit false-niche failure class")
func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition: failures.append(label)
func _finish() -> void:
	if failures.is_empty():
		print("ECO.P1C-S4 Robustness Seed Case: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error("ECO.P1C-S4 FAIL: %s" % failure)
	print("ECO.P1C-S4 Robustness Seed Case: FAIL (%d assertions, %d failures)" % [assertions, failures.size()]); quit(1)
