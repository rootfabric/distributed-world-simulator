extends SceneTree

## ECO.EVO7 FFF6 - bound-pinning ceiling calibration probe (NOTE-2 repair R2).
##
## Gathers the CROSS-SEED evidence behind the hard anti-runaway ceiling that
## eco_evo7_fff6_succession_lab_acceptance.gd enforces on its 108-cycle
## stability block: it replays run_zone_stability for BOTH gated stability
## zones (MESIC_LOAM, DRY_SAND) across the canonical seed and two fresh wave-2
## seeds, then prints per-zone/per-mode maxima of the 16-generation full run
## for context. Observability only: this probe gates nothing, changes no
## thresholds and writes no files; its printed table is transcribed into the
## checkpoint evidence document where the ceiling margin is justified.

const Simulation = preload("res://scripts/research/ecology/evo7_succession_simulation_v1.gd")

const SEEDS := [20260823, 20260824, 20260825]
const STABILITY_ZONES := ["MESIC_LOAM", "DRY_SAND"]

func _init() -> void:
	var started := Time.get_ticks_msec()
	for seed in SEEDS:
		var s := int(seed)
		for zone_name in STABILITY_ZONES:
			var run_started := Time.get_ticks_msec()
			var stability: Dictionary = Simulation.run_zone_stability(zone_name, s, Simulation.STABILITY_GENERATIONS)
			if stability.is_empty():
				print("STABILITY seed=%d zone=%s FAILED (empty result)" % [s, zone_name])
				continue
			print("STABILITY seed=%d zone=%s cycles=%d max_pinning=%.3f finite_means=%s means_bounded=%s fully_pinned=%s runtime_ms=%d" % [
				s, zone_name, int(stability["completed_cycles"]),
				float(stability["max_bound_pinning_fraction"]),
				str(bool(stability["finite_means"])), str(bool(stability["means_within_bounds"])),
				str(bool(stability["no_axis_fully_pinned"])),
				Time.get_ticks_msec() - run_started])
			var fractions: Dictionary = stability["bound_pinning_fractions"]
			var axis_keys := fractions.keys()
			axis_keys.sort()
			var axis_tokens := PackedStringArray()
			for axis_key in axis_keys:
				axis_tokens.append("%s=%.3f" % [String(axis_key), float(fractions[axis_key])])
			print("AXES seed=%d zone=%s %s" % [s, zone_name, "|".join(axis_tokens)])
		var full_started := Time.get_ticks_msec()
		var result: Dictionary = Simulation.run_all(s)
		if result.is_empty():
			print("FULLRUN seed=%d FAILED (empty result)" % s)
			continue
		var worst := 0.0
		var worst_token := "-"
		for zone_name in Simulation.ZONE_ORDER:
			var zone: Dictionary = result["zones"][zone_name]
			for mode_key in ["feedback_on", "feedback_off"]:
				var fraction := float(zone[mode_key]["max_bound_pinning_fraction"])
				if fraction > worst:
					worst = fraction
					worst_token = "%s/%s" % [zone_name, mode_key]
				print("FULLRUN seed=%d zone=%s mode=%s max_pinning=%.3f" % [s, zone_name, mode_key, fraction])
		print("FULLRUN seed=%d worst=%.3f at %s result_hash=%s runtime_ms=%d" % [
			s, worst, worst_token, String(result["result_hash"]).substr(0, 16),
			Time.get_ticks_msec() - full_started])
	print("total runtime_ms=%d" % (Time.get_ticks_msec() - started))
	print("ECO.EVO7 FFF6 pinning calibration probe: DONE")
	quit(0)
