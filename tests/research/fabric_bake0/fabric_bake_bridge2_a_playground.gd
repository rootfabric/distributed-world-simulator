extends SceneTree

const Contract = preload("res://scripts/research/fabric_bake0/mixed_representation_ownership_contract_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_a_fixture.gd")

func _initialize() -> void:
	var subject := Fixture.build()
	if not bool(subject.get("success", false)):
		printerr("BRIDGE-2-A playground fixture failed: %s" % str(subject))
		quit(1)
		return
	var contract: Dictionary = subject["contract"]
	var break_resolution := Contract.resolve_event(contract, Fixture.canonical_break_event())
	var hybrid_resolution := Contract.resolve_event(contract, Fixture.hybrid_jump_event())
	if not bool(break_resolution.get("success", false)) or not bool(hybrid_resolution.get("success", false)):
		printerr("BRIDGE-2-A playground event resolution failed")
		quit(1)
		return
	print("BRIDGE-2-A MIXED OWNERSHIP PLAYGROUND")
	print("contract_hash=%s" % contract["contract_hash"])
	for region_id in [Fixture.REGION_IMPACT, Fixture.REGION_STABLE, Fixture.REGION_CONTACT, Fixture.REGION_DYNAMIC, Fixture.REGION_HYBRID]:
		print("region=%s active_owner=%s" % [region_id, Contract.active_owner_for_region(contract, region_id)])
	var canonical: Dictionary = break_resolution["details"]["resolution"]
	var derived: Dictionary = hybrid_resolution["details"]["resolution"]
	print("canonical_event evaluator=%s commit_owner=%s observers=%s revision_policy=%s" % [
		canonical["evaluator_representation_id"], canonical["commit_owner"], str(canonical["observer_representation_ids"]), canonical["canonical_revision_policy"]
	])
	print("derived_event evaluator=%s commit_owner=%s observers=%s revision_policy=%s" % [
		derived["evaluator_representation_id"], derived["commit_owner"], str(derived["observer_representation_ids"]), derived["canonical_revision_policy"]
	])
	print("FABRIC-BAKE BRIDGE-2-A Playground: PASS")
	quit(0)
