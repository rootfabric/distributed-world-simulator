class_name Fabric0AdaptiveMultiEventManifoldExperimentsV1
extends RefCounted

const Fabric = preload("res://scripts/research/fabric0/fabric0_adaptive_multievent_manifold_v1.gd")

static func run_tolerance(tolerance: float) -> Dictionary:
	var system := Fabric.new_corner_system(-0.3, 1.2, 4.0, 0.5, 0.3)
	Fabric.seed_warm_cache(system, 2.0, 3.0)
	var result := Fabric.advance_adaptive(system, 1.2, {
		"atol": tolerance,
		"rtol": tolerance,
		"initial_step": 0.2,
		"max_step": 0.3,
		"min_step": 1.0e-9,
	})
	assert(bool(result["ok"]))
	return {"system": system, "result": result}

static func parallel_tasks(scale: float = 1.0) -> Array:
	return [
		{
			"id":"alpha",
			"matrix":[
				{0:4.0*scale,1:1.0},
				{0:1.0,1:3.0*scale,2:1.0},
				{1:1.0,2:2.0*scale},
			],
			"rhs":[1.0,2.0,3.0],
		},
		{
			"id":"beta",
			"matrix":[
				{0:5.0*scale,2:1.0},
				{1:2.0*scale},
				{0:1.0,2:4.0*scale},
			],
			"rhs":[2.0,1.0,3.0],
		},
	]
