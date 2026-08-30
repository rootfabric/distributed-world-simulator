extends SceneTree

const WaterFitness = preload("res://scripts/research/ecology/evo6_water_fitness_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var flooded := {"features": {"in_water": true, "water_dist_m": 0.0}, "effective_conditions": {"soil_moisture_ppm": 1000000}}
	var riparian := {"features": {"water_dist_m": 1.5}, "effective_conditions": {"soil_moisture_ppm": 650000}}
	var mesic := {"features": {"water_dist_m": 8.0}, "effective_conditions": {"soil_moisture_ppm": 400000}}
	var dry := {"features": {"water_dist_m": 20.0}, "effective_conditions": {"soil_moisture_ppm": 180000}}
	var wet_genome := {"water_preference": 0.85, "water_tolerance_width": 0.30, "root_depth_m": 0.85}
	var dry_genome := {"water_preference": 0.20, "water_tolerance_width": 0.30, "root_depth_m": 2.5}
	var shallow_dry := {"water_preference": 0.20, "water_tolerance_width": 0.30, "root_depth_m": 0.45}

	_check(WaterFitness.water_availability(flooded) == 1.0, "submerged availability is 1")
	_check(
		WaterFitness.water_availability(riparian) > WaterFitness.water_availability(mesic)
		and WaterFitness.water_availability(mesic) > WaterFitness.water_availability(dry),
		"availability orders riparian > mesic > dry"
	)
	_check(
		float(WaterFitness.evaluate(wet_genome, flooded)["fitness"]) > float(WaterFitness.evaluate(dry_genome, flooded)["fitness"]) * 4.0,
		"wet genotype dominates flood"
	)
	_check(
		float(WaterFitness.evaluate(dry_genome, dry)["fitness"]) > float(WaterFitness.evaluate(wet_genome, dry)["fitness"]) * 2.0,
		"dry genotype dominates drought"
	)
	_check(
		float(WaterFitness.evaluate(dry_genome, dry)["fitness"]) > float(WaterFitness.evaluate(shallow_dry, dry)["fitness"]) * 1.5,
		"deep roots strongly help drought"
	)
	_finish()

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO6-WATER fitness: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO6-WATER FAIL: %s" % failure)
	print("ECO.EVO6-WATER fitness: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
