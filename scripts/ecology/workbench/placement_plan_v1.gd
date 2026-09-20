# EcologyWorkbench PlacementPlan v1 (skeleton, P0).
# Role: deterministic placement of founders into environment zones (manual,
#   grid, seeded random, common-garden layouts) using CANONICAL spatial /
#   environment addressing — never a UI-only coordinate system.
# Layer: 2 (SIMULATION / ORCHESTRATION).
# Canonical API used (owner map rows 5,6):
#   - local_environment_field_v1.gd: create(owner_token, owner_epoch, origin_mm,
#     cell_size_mm, width, depth, ...) — canonical mm grid addressing  [A4]
#   - environment_field_contract_v1.gd: valid_footprint(), MAX_CELL bounds  [A4]
#   - resource_lifecycle_runtime_v1.gd: individual(blueprint, individual_id,
#     position_mm, endowment, origin_kind)  [A5]
#   - organism_life_state_v1.gd: create(..., position_mm, ...)  [A5]
#   - observatory_protocol_v1.gd: site_genesis(site_id, t, protocol)  [A7]
class_name EcoWorkbenchPlacementPlanV1
extends RefCounted

const SCHEMA := "dws.ecology.workbench.placement-plan.v1"

## Deterministic placement from plan + seed; positions in canonical mm.
static func resolve(plan: Dictionary, seed: int) -> Array:
	return []
