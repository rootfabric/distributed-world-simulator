# EcologyWorkbench ExperimentBranch v1 (skeleton, P0).
# Role: one branch of an experiment history: immutable source checkpoint,
#   subsequent ticks/commands, operator annotations; supports fork-from-checkpoint
#   and deterministic replay comparison. No second save format: linked to A8.
# Layer: 2 (SIMULATION / ORCHESTRATION).
# Canonical API used (owner map row 9):
#   - observatory_session_v1.gd: save_text()/load_text(text, expected_experiment,
#     expected_step)  [A8]
#   - snapshot_seam_v1.gd: snapshot_hash()/origin_hash()/cursor()  [A8]
#   - canonical_value_v1.gd: digest() for provenance links.
class_name EcoWorkbenchExperimentBranchV1
extends RefCounted

const SCHEMA := "dws.ecology.workbench.experiment-branch.v1"

## Identity: branch id + immutable parent checkpoint hash (A8).
static func create(source_checkpoint_hash: String, label: String) -> Dictionary:
	return {}

## Replay must reproduce identical results from identical source+seed+inputs.
func replay_hash() -> String:
	return ""
