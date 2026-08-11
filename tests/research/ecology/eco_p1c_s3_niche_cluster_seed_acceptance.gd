extends SceneTree

const Diagnostics = preload("res://scripts/research/ecology/plant_niche_cluster_diagnostics_v1.gd")

const EXPECTED_DYNAMIC := {
	"1138701|false": "3e52c4e93fcdefba64607dd2c935ccbddba78db3f400d6a6ea51b23db766982b",
	"1138702|false": "4706d80289b1fc9918f1758ccabdbb62a76053739f3c7bccadcd282e797d572b",
	"1138703|false": "a7f2713bc3a014d8bf440e9ecae36e37ef5bd67537358f985ad6a0442e5a3dfc",
	"1138701|true": "47f0e9c7573bf002151718a57c930d400682c3d86dbd3a8b96b8ddf48c4a01a2",
}
const EXPECTED_DIAGNOSTIC := {
	"1138701|false": "33de1af8e20e45eea88d9ddc20ee0664b6c53f20282995c593c1738e9105db2d",
	"1138702|false": "960ddf64b554e096e966796e6d614b75dfe2455259502310d75f700995d946a6",
	"1138703|false": "cfe5778cf188ce06b512ce77e35ec6675cdc65703b1c8f437dcaa70db93b1c92",
	"1138701|true": "b7a93ccdf4af05d92d2324a89331200a6957ce1433688dbe9ce70ded5e9c96f9",
}

var assertions := 0
var failures: Array[String] = []
var diagnostic: Dictionary
var founder_seed := 0
var uniform_control := false

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("ECO.P1C-S3 requires user args: <founder_seed> <true|false>")
		quit(2)
		return
	founder_seed = int(args[0])
	uniform_control = String(args[1]).to_lower() == "true"
	var key := "%d|%s" % [founder_seed, str(uniform_control)]
	if not EXPECTED_DYNAMIC.has(key):
		push_error("ECO.P1C-S3 unsupported test case: %s" % key)
		quit(2)
		return
	diagnostic = Diagnostics.run_seed(founder_seed, uniform_control)
	_test_contract(key)
	_test_cluster_partition()
	if uniform_control:
		_test_uniform_control()
	else:
		_test_heterogeneous_coexistence()
	_test_source_boundaries()
	_finish()

func _test_contract(key: String) -> void:
	_check(not diagnostic.is_empty(), "diagnostic result exists")
	_check(int(diagnostic.get("founder_seed", 0)) == founder_seed, "founder seed recorded")
	_check(bool(diagnostic.get("uniform_control", false)) == uniform_control, "control mode recorded")
	_check(String(diagnostic.get("dynamic_result_hash", "")) == EXPECTED_DYNAMIC[key], "accepted/new dynamic result hash exact")
	_check(String(diagnostic.get("diagnostic_hash", "")) == EXPECTED_DIAGNOSTIC[key], "diagnostic hash exact")
	_check(int(diagnostic.get("cluster_count", 0)) == 3, "anonymous three-cluster diagnostic resolution")
	_check(String(diagnostic.get("cluster_assignment_hash", "")).length() == 64, "assignment hash present")
	_check(Array(diagnostic.get("clusters", [])).size() == 3, "three cluster records present")

func _test_cluster_partition() -> void:
	var effective: Array = diagnostic["effective_founders"]
	var covered := {}
	var cluster_share_sum := 0.0
	for cluster in Array(diagnostic["clusters"]):
		_check(int(cluster["member_count"]) == Array(cluster["members"]).size(), "cluster member count exact")
		_check(int(cluster["member_count"]) >= 1, "cluster non-empty")
		_check(Dictionary(cluster["raw_trait_centroid"]).keys().size() == 8, "raw centroid covers eight traits")
		_check(Array(cluster["normalized_trait_centroid"]).size() == 8, "normalized centroid covers eight traits")
		_check(String(cluster["dominant_enrichment_region"]) in Diagnostics.REGION_NAMES, "region name is post-hoc diagnostic")
		cluster_share_sum += float(cluster["global_biomass_share"])
		for fi in Array(cluster["members"]):
			_check(not covered.has(int(fi)), "founder assigned to one cluster only")
			covered[int(fi)] = true
	_check(covered.size() == effective.size(), "all effective founders assigned")
	_check(cluster_share_sum > 0.95 and cluster_share_sum <= 1.000000001, "clusters explain nearly all global biomass")

func _test_heterogeneous_coexistence() -> void:
	_check(int(diagnostic["effective_founder_count"]) >= 18, "heterogeneous run retains at least eighteen founders above one percent")
	_check(float(diagnostic["top1_biomass_share"]) < 0.25, "no global biomass monopoly")
	_check(float(diagnostic["shannon_biomass_diversity"]) > 2.45, "high abundance diversity persists")
	_check(float(diagnostic["silhouette_score"]) > 0.12, "trait-space partition has nontrivial separation")
	_check(int(diagnostic["substantial_cluster_count"]) == 3, "all anonymous clusters exceed ten percent global biomass")
	_check(int(diagnostic["niche_enriched_cluster_count"]) >= 2, "at least two clusters show regional enrichment")
	var enriched := 0
	for cluster in Array(diagnostic["clusters"]):
		_check(float(cluster["global_biomass_share"]) >= 0.10, "each cluster is biomass-substantial")
		if float(cluster["niche_enrichment_span"]) >= Diagnostics.NICHE_ENRICHMENT_SPAN:
			enriched += 1
	_check(enriched >= 2, "regional enrichment appears in multiple anonymous clusters")

func _test_uniform_control() -> void:
	_check(int(diagnostic["effective_founder_count"]) >= 10, "uniform control retains enough founders for diagnostic clustering")
	_check(float(diagnostic["silhouette_score"]) > 0.0, "trait clusters can exist even without environmental niches")
	_check(int(diagnostic["niche_enriched_cluster_count"]) == 0, "uniform environment yields zero niche-enriched clusters")
	for cluster in Array(diagnostic["clusters"]):
		_check(float(cluster["niche_enrichment_span"]) < 0.000000001, "uniform cluster enrichment profile is flat")
		var first := float(cluster["regional_enrichment"][Diagnostics.REGION_NAMES[0]])
		for region_name in Diagnostics.REGION_NAMES:
			_check(absf(float(cluster["regional_enrichment"][region_name]) - first) < 0.000000001, "uniform regional enrichment is identical")

func _test_source_boundaries() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_niche_cluster_diagnostics_v1.gd").to_lower()
	_check(not source.contains("species"), "no predefined species labels")
	_check(not source.contains("biome"), "no biome rules")
	_check(not source.contains("fitness"), "no new fitness score")
	_check(not source.contains("migration"), "no migration")
	_check(not source.contains("camera"), "no presentation input")
	_check(not source.contains("authority"), "no authority input")
	_check(not source.contains("network"), "no network input")
	_check(source.contains("dynamic.run"), "diagnostics consume accepted S2 abundance dynamics")
	_check(source.contains("regional_enrichment"), "niche distinction is post-hoc enrichment")
	_check(source.contains("silhouette"), "trait separation metric is explicit")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	print("ECO.P1C-S3 seed=%d uniform=%s dynamic_hash=%s diagnostic_hash=%s silhouette=%.9f effective=%d substantial_clusters=%d niche_enriched_clusters=%d" % [
		founder_seed, str(uniform_control), String(diagnostic.get("dynamic_result_hash", "")), String(diagnostic.get("diagnostic_hash", "")),
		float(diagnostic.get("silhouette_score", 0.0)), int(diagnostic.get("effective_founder_count", 0)), int(diagnostic.get("substantial_cluster_count", 0)), int(diagnostic.get("niche_enriched_cluster_count", 0))
	])
	if failures.is_empty():
		print("ECO.P1C-S3 Niche/Cluster Seed Case: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.P1C-S3 FAIL: %s" % failure)
	print("ECO.P1C-S3 Niche/Cluster Seed Case: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
