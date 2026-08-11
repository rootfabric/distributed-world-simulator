extends RefCounted

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const PH2Probes = preload("res://scripts/research/ecology/plant_environment_coupled_development_probes_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/plant_seed_lifecycle_v1.gd")

const LINEAGE_ID := "lineage/ph4-controlled"
const FOUNDER_EVENT := "founder/ph4-001"

static func founder_payload() -> Dictionary:
	return Lifecycle.create_founder_payload(
		Genome.create_default(),
		Traits.create_default(),
		LINEAGE_ID,
		FOUNDER_EVENT,
		0,
		1.0
	)

static func reference_run() -> Dictionary:
	return Lifecycle.run_to_first_reproduction(
		founder_payload(),
		PH2Probes.make_environment_samples()["REFERENCE"],
		0.10,
		3.0
	)

static func dormancy_then_recovery() -> Dictionary:
	var payload := founder_payload()
	var envs := PH2Probes.make_environment_samples()
	var state := Lifecycle.create_initial_state(payload)
	var dry_steps: Array = []
	for _i in range(10):
		var dry_result := Lifecycle.advance(state, payload, envs["DRY"], 0.10)
		if dry_result.is_empty():
			return {}
		state = dry_result["state"]
		dry_steps.append(state.duplicate(true))
	var recovery := Lifecycle.advance(state, payload, envs["REFERENCE"], 0.10)
	if recovery.is_empty():
		return {}
	return {
		"payload": payload,
		"dry_steps": dry_steps,
		"recovery": recovery,
	}

static func offspring_environment_pair() -> Dictionary:
	var run := reference_run()
	if run.is_empty() or run.get("offspring", []).is_empty():
		return {}
	var child: Dictionary = run["offspring"][0]
	var envs := PH2Probes.make_environment_samples()
	var shade_state := Lifecycle.create_initial_state(child)
	var sun_state := Lifecycle.create_initial_state(child)
	var shade := Lifecycle.advance(shade_state, child, envs["SHADE"], 0.10)
	var sun := Lifecycle.advance(sun_state, child, envs["SUN"], 0.10)
	return {
		"child": child,
		"shade": shade,
		"sun": sun,
	}
