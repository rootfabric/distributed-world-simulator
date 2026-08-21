extends SceneTree

const Fixture = preload("res://tests/ecology/production/support/eco_p4_fixture_v1.gd")
const OfflineCatchup = preload("res://scripts/ecology/production/ecology_offline_catchup_v1.gd")
const ProductionPersistence = preload("res://scripts/ecology/production/ecology_region_persistence_v1.gd")
const Ownership = preload("res://scripts/ecology/production/ecology_region_ownership_v1.gd")
const ReadModel = preload("res://scripts/ecology/production/ecology_client_read_model_v1.gd")

const EXPECTED_PARENT := "c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419"

var assertions := 0
var failed := false

func _init() -> void:
	_check(ReadModel.PARENT_P4_5_AGGREGATE == EXPECTED_PARENT, "P4.5 accepted aggregate pinned")

	var completed := Fixture.completed_catchup()
	_check(bool(OfflineCatchup.validate_state(completed).get("success", false)), "real P4.3 completed catch-up validates")
	var snapshot := ProductionPersistence.create_snapshot(completed)
	_check(bool(ProductionPersistence.validate_snapshot(snapshot).get("success", false)), "real P4.4 snapshot validates")
	var source := Ownership.create_ownership(snapshot, "server-a", 0)
	_check(bool(Ownership.validate_ownership(source).get("success", false)), "real P4.5 source ownership validates")

	var source_summary := ReadModel.build_region_summary(source)
	_check(bool(ReadModel.validate_region_summary(source_summary).get("success", false)), "P4.6 summary from real ownership validates")
	_check(String(source_summary["region_id"]) == "planet-01:region_0007", "real region id projected")
	_check(String(source_summary["owner_server_id"]) == "server-a", "source owner projected")
	_check(int(source_summary["ownership_epoch"]) == 0, "source epoch projected")
	_check(String(source_summary["source_ownership_hash"]) == String(source["ownership_hash"]), "source ownership hash projected")
	_check(String(source_summary["source_snapshot_hash"]) == String(snapshot["snapshot_hash"]), "source snapshot hash projected")
	_check(int(source_summary["ecology_generation"]) == 5, "real ecology generation projected")
	_check(int(source_summary["patch_count"]) == 3, "real patch count projected")
	_check(Array(source_summary["lineage_biomass"]).size() == 2, "real lineage set projected")
	_check(float(source_summary["total_biomass_kg"]) > 0.0, "real biomass projected")

	var handoff := Ownership.prepare_handoff(source, "server-b")
	var target := Ownership.accept_handoff(source, handoff, "server-b")
	_check(bool(Ownership.validate_ownership(target).get("success", false)), "real handoff target validates")
	var target_summary := ReadModel.build_region_summary(target)
	_check(bool(ReadModel.validate_region_summary(target_summary).get("success", false)), "target summary validates")
	_check(int(target_summary["ownership_epoch"]) == 1, "handoff epoch reaches client cursor")
	_check(String(target_summary["owner_server_id"]) == "server-b", "handoff owner reaches client cursor")
	_check(String(target_summary["source_snapshot_hash"]) == String(source_summary["source_snapshot_hash"]), "handoff preserves ecological snapshot cursor")
	_check(float(target_summary["total_biomass_kg"]) == float(source_summary["total_biomass_kg"]), "handoff preserves projected biomass")
	_check(String(target_summary["summary_hash"]) != String(source_summary["summary_hash"]), "ownership change rotates summary identity")
	_check(String(ReadModel.accept_client_update(source_summary, target_summary)["summary_hash"]) == String(target_summary["summary_hash"]), "client cache accepts higher fencing epoch")
	_check(ReadModel.accept_client_update(target_summary, source_summary).is_empty(), "client cache rejects old owner epoch")

	var second_completed := Fixture.completed_catchup("planet-01:region_0008")
	var second_snapshot := ProductionPersistence.create_snapshot(second_completed)
	var second_owner := Ownership.create_ownership(second_snapshot, "server-c", 2)
	_check(bool(Ownership.validate_ownership(second_owner).get("success", false)), "second real region ownership validates")
	var interest := ReadModel.project_interest([target, second_owner], ["planet-01:region_0008", "planet-01:missing", "planet-01:region_0007", "planet-01:region_0008"])
	_check(bool(ReadModel.validate_interest_projection(interest).get("success", false)), "real multi-region interest projection validates")
	_check(int(interest["summary_count"]) == 2, "interest returns both present regions")
	_check(int(interest["missing_count"]) == 1, "interest keeps explicit missing region")
	_check(Array(interest["requested_region_ids"]) == ["planet-01:missing", "planet-01:region_0007", "planet-01:region_0008"], "interest request canonicalized sorted unique")
	_check(Array(interest["missing_region_ids"]) == ["planet-01:missing"], "interest missing set exact")

	var future_catchup := OfflineCatchup.extend_elapsed(completed, 2.0)
	future_catchup = OfflineCatchup.advance_batch(future_catchup, 10)
	_check(bool(OfflineCatchup.validate_state(future_catchup).get("success", false)), "future real catch-up validates")
	var future_snapshot := ProductionPersistence.create_snapshot(future_catchup)
	var target_advanced := Ownership.commit_snapshot(target, "server-b", 1, String(target["ownership_hash"]), future_snapshot)
	_check(bool(Ownership.validate_ownership(target_advanced).get("success", false)), "target owner commits future snapshot")
	var future_summary := ReadModel.build_region_summary(target_advanced)
	_check(bool(ReadModel.validate_region_summary(future_summary).get("success", false)), "future summary validates")
	_check(int(future_summary["ecology_generation"]) > int(target_summary["ecology_generation"]), "future generation advances client cursor")
	_check(String(ReadModel.accept_client_update(target_summary, future_summary)["summary_hash"]) == String(future_summary["summary_hash"]), "client cache accepts future generation")
	_check(ReadModel.accept_client_update(future_summary, target_summary).is_empty(), "client cache rejects generation rollback")

	var bytes := ProductionPersistence.serialize_snapshot(future_snapshot)
	_check(not bytes.is_empty(), "real future snapshot serializes")
	var decoded := ProductionPersistence.deserialize_snapshot(bytes)
	_check(bool(ProductionPersistence.validate_snapshot(decoded).get("success", false)), "real future snapshot deserializes")
	var restarted_owner := Ownership.create_ownership(decoded, "server-b", 1)
	_check(bool(Ownership.validate_ownership(restarted_owner).get("success", false)), "ownership reconstructed after persistence restart")
	_check(String(restarted_owner["ownership_hash"]) == String(target_advanced["ownership_hash"]), "restart reconstructs exact P4.5 ownership identity")
	var restarted_summary := ReadModel.build_region_summary(restarted_owner)
	_check(String(restarted_summary["summary_hash"]) == String(future_summary["summary_hash"]), "restart reconstructs exact P4.6 summary identity")

	var detached := source_summary.duplicate(true)
	Array(detached["lineage_biomass"])[0]["biomass_kg"] = 999999.0
	_check(String(Dictionary(source["snapshot"])["snapshot_hash"]) == String(snapshot["snapshot_hash"]), "client summary mutation cannot affect canonical ownership snapshot")

	seed(271828)
	var rng_before := [randi(), randi(), randi()]
	seed(271828)
	ReadModel.build_region_summary(source)
	ReadModel.project_interest([target, second_owner], ["planet-01:region_0007", "planet-01:region_0008"])
	ReadModel.accept_client_update(target_summary, future_summary)
	var rng_after := [randi(), randi(), randi()]
	_check(rng_before == rng_after, "real P4.5 to P4.6 integration consumes no global RNG")

	var integration_hash := (String(source_summary["summary_hash"]) + "\n" + String(target_summary["summary_hash"]) + "\n" + String(interest["interest_hash"]) + "\n" + String(future_summary["summary_hash"]) + "\n" + String(restarted_owner["ownership_hash"]) + "\n" + ReadModel.PARENT_P4_5_AGGREGATE).sha256_text()
	_check(integration_hash.length() == 64, "integration aggregate generated")

	if failed:
		quit(1)
		return
	print("ECO.P4.6 Real P4.5 -> Client Read Integration: PASS (%d assertions)" % assertions)
	print("integration_hash=" + integration_hash)
	print("source_summary_hash=" + String(source_summary["summary_hash"]))
	print("target_summary_hash=" + String(target_summary["summary_hash"]))
	print("interest_hash=" + String(interest["interest_hash"]))
	print("future_summary_hash=" + String(future_summary["summary_hash"]))
	print("restart_ownership_hash=" + String(restarted_owner["ownership_hash"]))
	print("parent_p4_5=" + ReadModel.PARENT_P4_5_AGGREGATE)
	quit(0)

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		return
	failed = true
	push_error("ECO.P4.6 INTEGRATION FAIL: " + message)
