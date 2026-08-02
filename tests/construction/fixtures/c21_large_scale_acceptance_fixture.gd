extends RefCounted

const Profile = preload("res://scripts/construction/acceptance/construction_scale_profile.gd")

class MemoryStore:
	var values: Dictionary = {}
	func write(key: String, value: Dictionary) -> Dictionary:
		values[key] = value.duplicate(true)
		return {"success": true, "error_code": "", "message": ""}
	func read(key: String) -> Dictionary:
		if not values.has(key):
			return {"success": false, "error_code": "NOT_FOUND", "message": "NOT_FOUND"}
		return {"success": true, "error_code": "", "message": "", "value": Dictionary(values[key]).duplicate(true)}

static func acceptance_profile() -> Dictionary:
	return Profile.create("c21-acceptance", {
		"seed": 210021,
		"construct_count": 20000,
		"parts_per_construct": 64,
		"build_plan_count": 1000,
		"agent_count": 256,
		"fabrication_job_count": 3000,
		"procurement_order_count": 4000,
		"shipment_count": 4000,
		"damage_event_count": 2000,
		"collapse_event_count": 500,
		"repair_event_count": 1500,
		"warehouse_count": 32,
		"server_count": 16,
		"authority_migration_count": 1000,
		"reconnect_wave_count": 32,
		"soak_ticks": 2048,
		"commands_per_tick": 24,
		"presentation_budget": 512,
		"simulation_budget": 4096,
		"summary_budget": 12000,
		"persistence_checkpoint_tick": 1024,
		"max_wall_time_ms": 120000,
		"expected_min_operations": 50000,
	})

static func persistence_profile() -> Dictionary:
	return Profile.create("c21-persistence", {
		"seed": 210022,
		"construct_count": 5000,
		"parts_per_construct": 32,
		"build_plan_count": 250,
		"agent_count": 64,
		"fabrication_job_count": 500,
		"procurement_order_count": 600,
		"shipment_count": 600,
		"damage_event_count": 400,
		"collapse_event_count": 100,
		"repair_event_count": 300,
		"warehouse_count": 8,
		"server_count": 8,
		"authority_migration_count": 200,
		"reconnect_wave_count": 12,
		"soak_ticks": 512,
		"commands_per_tick": 24,
		"presentation_budget": 128,
		"simulation_budget": 1024,
		"summary_budget": 3500,
		"persistence_checkpoint_tick": 256,
		"max_wall_time_ms": 120000,
		"expected_min_operations": 12000,
	})

static func soak_profile() -> Dictionary:
	return Profile.create("c21-soak", {
		"seed": 210023,
		"construct_count": 30000,
		"parts_per_construct": 96,
		"build_plan_count": 2000,
		"agent_count": 512,
		"fabrication_job_count": 6000,
		"procurement_order_count": 8000,
		"shipment_count": 8000,
		"damage_event_count": 5000,
		"collapse_event_count": 1500,
		"repair_event_count": 3500,
		"warehouse_count": 64,
		"server_count": 32,
		"authority_migration_count": 2000,
		"reconnect_wave_count": 64,
		"soak_ticks": 8192,
		"commands_per_tick": 12,
		"presentation_budget": 1024,
		"simulation_budget": 8192,
		"summary_budget": 20000,
		"persistence_checkpoint_tick": 4096,
		"max_wall_time_ms": 180000,
		"expected_min_operations": 100000,
	})
