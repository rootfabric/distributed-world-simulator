extends SceneTree
const Diagnostics = preload("res://scripts/research/ecology/plant_niche_cluster_diagnostics_v1.gd")
const EXPECTED_AGGREGATE_HASH := "75512459aa4a7d97b7e9549842c41a5ebf4b5574575bac9fec3ee51fd92d44a9"
func _init() -> void:
	var runs := [
		{"founder_seed": 1138701, "diagnostic_hash": "33de1af8e20e45eea88d9ddc20ee0664b6c53f20282995c593c1738e9105db2d"},
		{"founder_seed": 1138702, "diagnostic_hash": "960ddf64b554e096e966796e6d614b75dfe2455259502310d75f700995d946a6"},
		{"founder_seed": 1138703, "diagnostic_hash": "cfe5778cf188ce06b512ce77e35ec6675cdc65703b1c8f437dcaa70db93b1c92"},
	]
	var uniform := {"diagnostic_hash": "b7a93ccdf4af05d92d2324a89331200a6957ce1433688dbe9ce70ded5e9c96f9"}
	var actual := Diagnostics.compute_aggregate_hash(runs, uniform)
	var assertions := 5
	var failures := 0
	if actual != EXPECTED_AGGREGATE_HASH: failures += 1
	if runs.size() != 3: failures += 1
	if int(runs[0]["founder_seed"]) != Diagnostics.DEFAULT_SEEDS[0]: failures += 1
	if int(runs[2]["founder_seed"]) != Diagnostics.THIRD_FOUNDER_SEED: failures += 1
	if String(uniform["diagnostic_hash"]).length() != 64: failures += 1
	if failures == 0:
		print("ECO.P1C-S3 Aggregate Contract: PASS (%d assertions) aggregate=%s" % [assertions, actual])
		quit(0)
	else:
		push_error("ECO.P1C-S3 Aggregate Contract: FAIL (%d/%d)" % [failures, assertions])
		quit(1)
