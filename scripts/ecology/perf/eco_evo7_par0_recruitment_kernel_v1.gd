extends RefCounted

## ECO.EVO7 PERF1-PAR0 — pure LS3.3 recruitment evaluation kernel.
##
## SINGLE IMPLEMENTATION of the per-candidate recruitment calculation, used
## both by the serial LS3.3 coordinator (oracle) and by PAR0 OS worker
## processes. The mathematical content is moved verbatim from
## eco_evo7_ls33_dispersal_recruitment_v1.gd; no formula, constant, rounding
## or hash input changes are allowed or made.
##
## The kernel is pure: no SceneTree, no Node, no renderer, no UI, no global
## RNG, no frame time, no worker index, no scheduler ordering, no PID and no
## system clock influence the result. Worker identity never reaches the
## simulation output.

const Shadow = preload("res://scripts/ecology/shadow/eco_evo7_live_world_shadow_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")

const KERNEL_SCHEMA := "distributed_world_simulator.ecology.evo7_par0_recruitment_kernel.v1"
const KERNEL_VERSION := "1.0.0"

## Deterministic context for a whole recruitment evaluation batch.
## Built by the coordinator from immutable LS3.3 state only.
static func build_context(
	schema: String,
	version: String,
	revision: String,
	environment_seed: int,
	environment_field_hash: String,
	environment_cells: Array
) -> Dictionary:
	return {
		"kernel_schema": KERNEL_SCHEMA,
		"kernel_version": KERNEL_VERSION,
		"schema": schema,
		"version": version,
		"revision": revision,
		"environment_seed": environment_seed,
		"environment_field_hash": environment_field_hash,
		"environment_cells": environment_cells,
	}

## Per-candidate recruitment evaluation. Returns the canonical recruitment
## event WITHOUT "recruitment_event_hash" (the caller/LS3.3 stamps it), or an
## empty Dictionary on a hard evaluation error (schema/observation failure).
## candidate: canonical LS3.3 candidate (candidate_hash, child_bundle, ...).
## route: canonical LS3.3 dispersal route for the same candidate_hash.
static func evaluate_recruitment_event(
	candidate: Dictionary,
	route: Dictionary,
	context: Dictionary
) -> Dictionary:
	var candidate_hash := String(candidate["candidate_hash"])
	var in_patch := bool(route["in_patch"])
	var destination_index := int(route["destination_cell_index"])
	var next_generation := int(route["generation"])
	if not in_patch:
		return {
			"candidate_hash": candidate_hash,
			"route_hash": String(route["route_hash"]),
			"generation": next_generation,
			"destination_cell_index": -1,
			"environment_cell_hash": "",
			"evaluation_hash": "",
			"shadow_fitness": -999.0,
			"establishment_capacity": 0.0,
			"establishment_probability": 0.0,
			"establishment_gate": 1.0,
			"eligible": false,
			"reason": "OUT_OF_PATCH",
		}
	var environment_cells: Array = context["environment_cells"]
	if destination_index < 0 or destination_index >= environment_cells.size():
		return {}
	var env_cell: Dictionary = environment_cells[destination_index]
	var observation := build_observation(env_cell, context, next_generation, candidate_hash)
	if observation.is_empty():
		return {}
	var evaluation_result := Shadow.evaluate_bundle_against_observation(candidate["child_bundle"], observation)
	if not bool(evaluation_result.get("success", false)):
		return {}
	var evaluation: Dictionary = evaluation_result["details"]
	var fitness := float(evaluation["shadow_fitness"])
	var establishment_capacity := float(evaluation["establishment_capacity"])
	var resource_open := clampf(1.0 - float(env_cell["surface_water_fraction"]), 0.0, 1.0)
	var probability := clampf(0.22 + 0.28 * fitness + 0.34 * establishment_capacity + 0.16 * resource_open, 0.02, 0.98)
	var gate := _unit01("%s|recruit|%d|%d" % [String(candidate["child_bundle_checksum"]), next_generation, destination_index])
	var eligible := float(env_cell["land_mask"]) >= 0.5 and gate < probability
	var reason := "ELIGIBLE" if eligible else ("NON_LAND" if float(env_cell["land_mask"]) < 0.5 else "ESTABLISHMENT_FAIL")
	return {
		"candidate_hash": candidate_hash,
		"route_hash": String(route["route_hash"]),
		"generation": next_generation,
		"destination_cell_index": destination_index,
		"environment_cell_hash": String(env_cell["cell_hash"]),
		"evaluation_hash": String(evaluation["shadow_result_hash"]),
		"shadow_fitness": snappedf(fitness, 1e-9),
		"establishment_capacity": snappedf(establishment_capacity, 1e-9),
		"establishment_probability": snappedf(probability, 1e-9),
		"establishment_gate": snappedf(gate, 1e-9),
		"eligible": eligible,
		"reason": reason,
	}

## Destination observation builder (verbatim LS3.3 _environment_observation).
static func build_observation(
	env_cell: Dictionary,
	context: Dictionary,
	next_generation: int,
	candidate_hash: String
) -> Dictionary:
	var sand := float(env_cell["soil_texture_sand"])
	var clay := float(env_cell["soil_texture_clay"])
	var texture := "sand" if sand >= 0.55 and sand >= clay else ("clay" if clay >= 0.38 else "loam")
	var revision := String(context["revision"])
	var environment_seed := int(context["environment_seed"])
	var environment_field_hash := String(context["environment_field_hash"])
	var env := EnvironmentSample.create(
		float(env_cell["east_m"]), float(env_cell["north_m"]),
		float(env_cell["temperature_c"]), float(env_cell["soil_moisture"]),
		float(env_cell["incident_light"]), 0.50,
		clampf(float(env_cell["surface_water_fraction"]), 0.0, 1.0),
		environment_seed,
		"%s|field=%s|cell=%s" % [revision, environment_field_hash, String(env_cell["cell_hash"])]
	)
	if not bool(EnvironmentSample.validate(env).get("success", false)):
		return {}
	var obs := {
		"schema": Shadow.SCHEMA,
		"version": Shadow.VERSION,
		"mode": Shadow.MODE,
		"observation_id": "ls33/%d/%d/%s" % [next_generation, int(env_cell["index"]), candidate_hash.substr(0, 12)],
		"world_time": float(next_generation),
		"live_state_hash": String(env_cell["cell_hash"]),
		"environment_sample": env,
		"shadow_texture_proxy": texture,
		"open_sunlight": float(env_cell["incident_light"]),
		"canopy_adjusted_sunlight": float(env_cell["incident_light"]),
	}
	obs["observation_hash"] = _shadow_observation_hash(obs)
	return obs

## Canonical recruitment event hash (verbatim LS3.3 _recruitment_event_hash).
static func recruitment_event_hash(event: Dictionary, schema: String, version: String) -> String:
	return "|".join(PackedStringArray([
		schema, version, "recruitment",
		String(event.get("candidate_hash", "")), String(event.get("route_hash", "")),
		str(int(event.get("generation", -1))), str(int(event.get("destination_cell_index", -1))),
		String(event.get("environment_cell_hash", "")), String(event.get("evaluation_hash", "")),
		"%.9f" % float(event.get("shadow_fitness", 0.0)),
		"%.9f" % float(event.get("establishment_capacity", 0.0)),
		"%.9f" % float(event.get("establishment_probability", 0.0)),
		"%.9f" % float(event.get("establishment_gate", 0.0)),
		"1" if bool(event.get("eligible", false)) else "0", String(event.get("reason", "")),
	])).sha256_text()

static func _shadow_observation_hash(observation: Dictionary) -> String:
	return "|".join(PackedStringArray([
		Shadow.SCHEMA, Shadow.VERSION, Shadow.MODE,
		String(observation.get("observation_id", "")),
		"%.9f" % float(observation.get("world_time", -1.0)),
		String(observation.get("live_state_hash", "")),
		String(Dictionary(observation.get("environment_sample", {})).get("checksum", "")),
		String(observation.get("shadow_texture_proxy", "")),
		"%.9f" % float(observation.get("open_sunlight", 0.0)),
		"%.9f" % float(observation.get("canopy_adjusted_sunlight", 0.0)),
	])).sha256_text()

static func _unit01(key: String) -> float:
	return float(key.sha256_text().substr(0, 12).hex_to_int()) / 281474976710655.0
