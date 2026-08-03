extends RefCounted

const State = preload("res://scripts/construction/acceptance/construction_scale_state.gd")

static func check(state: Dictionary) -> Array:
	var failures: Array[String] = []
	var profile: Dictionary = state.profile
	var metrics: Dictionary = state.metrics
	if state.constructs.size() != int(profile.construct_count):
		failures.append("construct_count_mismatch")
	if state.plans.size() != int(profile.build_plan_count):
		failures.append("build_plan_count_mismatch")
	if state.agents.size() != int(profile.agent_count):
		failures.append("agent_count_mismatch")
	if state.warehouses.size() != int(profile.warehouse_count):
		failures.append("warehouse_count_mismatch")
	if int(metrics.duplicate_commits) != 0:
		failures.append("duplicate_authoritative_commits")
	if int(metrics.lost_item_identities) != 0:
		failures.append("lost_item_identities")
	if int(metrics.material_balance_delta) != 0:
		failures.append("material_balance_delta")
	if int(metrics.max_presented) > int(profile.presentation_budget):
		failures.append("presentation_budget_exceeded")
	if int(metrics.max_simulated) > int(profile.simulation_budget):
		failures.append("simulation_budget_exceeded")
	if int(metrics.max_summarized) > int(profile.summary_budget):
		failures.append("summary_budget_exceeded")
	if int(metrics.operations_attempted) < int(profile.expected_min_operations):
		failures.append("operation_volume_below_threshold")
	if int(metrics.wall_time_ms) > int(profile.max_wall_time_ms):
		failures.append("wall_time_budget_exceeded")
	if int(metrics.item_backed_parts_modeled) != int(profile.construct_count) * int(profile.parts_per_construct):
		failures.append("item_backed_part_count_mismatch")
	if int(metrics.damage_events_applied) != int(profile.damage_event_count):
		failures.append("damage_event_count_mismatch")
	if int(metrics.collapse_events_completed) != int(profile.collapse_event_count):
		failures.append("collapse_event_count_mismatch")
	if int(metrics.repair_events_completed) != int(profile.repair_event_count):
		failures.append("repair_event_count_mismatch")
	if int(metrics.authority_migrations_completed) != int(profile.authority_migration_count):
		failures.append("authority_migration_count_mismatch")
	if int(metrics.reconnect_waves_completed) != int(profile.reconnect_wave_count):
		failures.append("reconnect_wave_count_mismatch")
	if int(metrics.fabrication_jobs_completed) != int(profile.fabrication_job_count):
		failures.append("fabrication_job_count_mismatch")
	if int(metrics.procurement_orders_completed) != int(profile.procurement_order_count):
		failures.append("procurement_order_count_mismatch")
	if int(metrics.shipments_delivered) != int(profile.shipment_count):
		failures.append("shipment_count_mismatch")
	if int(metrics.build_plans_completed) != int(profile.build_plan_count):
		failures.append("build_plan_completion_mismatch")
	if int(metrics.agent_goals_completed) != int(profile.build_plan_count):
		failures.append("agent_goal_completion_mismatch")
	if int(state.tick) != int(profile.soak_ticks):
		failures.append("soak_tick_mismatch")
	var state_validation := State.validate(State.seal(state))
	if not bool(state_validation.get("success", false)):
		failures.append("state_contract_invalid")
	return failures
