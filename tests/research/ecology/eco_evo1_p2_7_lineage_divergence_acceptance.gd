extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_lineage_divergence_experiment_v1.gd")
const Diagnostics = preload("res://scripts/research/ecology/plant_lineage_divergence_diagnostics_v1.gd")

var assertions := 0

func _init() -> void:
	var first := Experiment.run()
	var second := Experiment.run()
	_check(not first.is_empty(), "experiment result exists")
	_check(not second.is_empty(), "repeat result exists")
	if first.is_empty() or second.is_empty():
		_finish(false)
		return
	_check(String(first.get("aggregate_hash", "")) == String(second.get("aggregate_hash", "")), "same-process aggregate deterministic")
	_check(String(first.get("p2_6_parent_hash", "")) == Experiment.ACCEPTED_P2_6_HASH, "accepted P2.6 parent exact")
	_check(String(first.get("aggregate_hash", "")).length() == 64, "aggregate hash shape")

	_check(bool(first["candidate"]), "isolated + diverged pair is research speciation candidate")
	_check(not bool(first["connected_candidate"]), "continued connectivity blocks candidate despite same trait divergence")
	_check(not bool(first["similar_candidate"]), "isolation alone does not create candidate")
	_check(not bool(first["recent_candidate"]), "recent split alone does not create candidate")
	_check(bool(first["no_canonical_species_declaration"]), "candidate never declares canonical species")

	var candidate: Dictionary = first["isolated_diverged"]
	var connected: Dictionary = first["connected_diverged"]
	var similar: Dictionary = first["isolated_similar"]
	var recent: Dictionary = first["recent_diverged"]
	var candidate_evidence: Dictionary = candidate["evidence"]
	for key in ["shared_ancestry", "split_age_ok", "isolation_ok", "connectivity_ok", "genome_divergence_ok", "ecological_divergence_ok"]:
		_check(bool(candidate_evidence.get(key, false)), "candidate evidence gate true: " + key)
	_check(String(candidate["classification"]) == "SPECIATION_CANDIDATE", "candidate classification explicit")
	_check(not bool(candidate["canonical_species_declared"]), "candidate classification is not taxonomy")
	_check(int(candidate["split_age_years"]) >= Diagnostics.MIN_SPLIT_AGE_YEARS, "candidate split age passes policy")
	_check(float(candidate["isolation_fraction"]) >= Diagnostics.MIN_ISOLATION_FRACTION, "candidate isolation passes policy")
	_check(float(candidate["connection_fraction"]) <= Diagnostics.MAX_CONNECTION_FRACTION, "candidate connectivity passes policy")
	_check(float(candidate["genome_distance"]) >= Diagnostics.MIN_GENOME_DISTANCE, "candidate genome divergence passes policy")
	_check(float(candidate["ecological_history_distance"]) >= Diagnostics.MIN_ECOLOGICAL_HISTORY_DISTANCE, "candidate ecology divergence passes policy")
	_check(float(candidate["recruitment_trait_distance"]) > 0.0, "recruitment divergence reported independently")

	var connected_evidence: Dictionary = connected["evidence"]
	_check(bool(connected_evidence["genome_divergence_ok"]), "connected control retains genome divergence")
	_check(bool(connected_evidence["ecological_divergence_ok"]), "connected control retains ecological divergence")
	_check(not bool(connected_evidence["connectivity_ok"]), "connected control fails connectivity gate only")
	_check(float(connected["connection_fraction"]) > Diagnostics.MAX_CONNECTION_FRACTION, "connected control has high connection fraction")

	var similar_evidence: Dictionary = similar["evidence"]
	_check(bool(similar_evidence["isolation_ok"]), "similar control remains spatially isolated")
	_check(bool(similar_evidence["connectivity_ok"]), "similar control has low connectivity")
	_check(not bool(similar_evidence["genome_divergence_ok"]), "similar control fails genome divergence")
	_check(not bool(similar_evidence["ecological_divergence_ok"]), "similar control fails ecological divergence")
	_check(float(similar["genome_distance"]) < Diagnostics.MIN_GENOME_DISTANCE, "similar genome distance below gate")

	var recent_evidence: Dictionary = recent["evidence"]
	_check(not bool(recent_evidence["split_age_ok"]), "recent control fails split-age gate")
	_check(int(recent["split_age_years"]) < Diagnostics.MIN_SPLIT_AGE_YEARS, "recent split age below policy")
	_check(bool(recent_evidence["genome_divergence_ok"]), "recent control can already be genomically different")
	_check(bool(recent_evidence["isolation_ok"]), "recent control can already be geographically isolated")

	for run_name in ["isolated_diverged", "connected_diverged", "isolated_similar", "recent_diverged"]:
		var diagnostic: Dictionary = first[run_name]
		_check(String(diagnostic.get("result_hash", "")).length() == 64, run_name + " result hash shape")
		_check(float(diagnostic.get("isolation_fraction", -1.0)) >= 0.0 and float(diagnostic.get("isolation_fraction", 2.0)) <= 1.0, run_name + " isolation bounded")
		_check(float(diagnostic.get("connection_fraction", -1.0)) >= 0.0 and float(diagnostic.get("connection_fraction", 2.0)) <= 1.0, run_name + " connection bounded")
		_check(float(diagnostic.get("genome_distance", -1.0)) >= 0.0 and float(diagnostic.get("genome_distance", 2.0)) <= 1.0, run_name + " genome distance bounded")
		_check(float(diagnostic.get("ecological_history_distance", -1.0)) >= 0.0 and float(diagnostic.get("ecological_history_distance", 2.0)) <= 1.0, run_name + " ecology distance bounded")

	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_lineage_divergence_diagnostics_v1.gd")
	_check(source.find("species_id") == -1, "diagnostic kernel cannot assign species_id")
	_check(source.find("biome") == -1, "diagnostic kernel has no biome lookup")
	_check(source.find("fitness_score") == -1, "diagnostic kernel has no hidden combined fitness score")
	_check(source.find("MIN_ISOLATION_FRACTION") >= 0, "detection policy threshold is explicit")
	_check(source.find("MAX_CONNECTION_FRACTION") >= 0, "connectivity policy threshold is explicit")

	print("ECO.EVO1-P2.7 candidate=%s connected=%s similar=%s recent=%s" % [str(bool(first["candidate"])), str(bool(first["connected_candidate"])), str(bool(first["similar_candidate"])), str(bool(first["recent_candidate"]))])
	print("ECO.EVO1-P2.7 split_age=%d isolation=%.12f connection=%.12f genome=%.12f recruitment=%.12f ecology=%.12f" % [int(first["candidate_split_age"]), float(first["candidate_isolation"]), float(first["candidate_connection"]), float(first["candidate_genome_distance"]), float(first["candidate_recruitment_distance"]), float(first["candidate_ecology_distance"])])
	print("ECO.EVO1-P2.7 connected_connection=%.12f similar_genome=%.12f similar_ecology=%.12f recent_split_age=%d" % [float(first["connected_connection"]), float(first["similar_genome_distance"]), float(first["similar_ecology_distance"]), int(first["recent_split_age"])])
	print("ECO.EVO1-P2.7 Lineage Divergence / Speciation Candidate Diagnostics: PASS (%d assertions) aggregate_hash=%s p2_6=%s" % [assertions, String(first["aggregate_hash"]), String(first["p2_6_parent_hash"])])
	_finish(true)

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		push_error("ECO.EVO1-P2.7 assertion failed: " + message)
		quit(1)

func _finish(success: bool) -> void:
	quit(0 if success else 1)
