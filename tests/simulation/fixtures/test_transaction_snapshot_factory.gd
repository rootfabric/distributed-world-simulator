extends RefCounted

const AdapterScript = preload("res://tests/simulation/fixtures/test_transaction_aggregate_adapter.gd")
const TypeReferenceScript = preload("res://scripts/simulation/aggregates/dynamic_type_reference.gd")
const IdentityScript = preload("res://scripts/simulation/aggregates/aggregate_identity.gd")
const AuthorityScript = preload("res://scripts/simulation/aggregates/aggregate_authority_state.gd")
const SpatialScopeScript = preload("res://scripts/simulation/aggregates/aggregate_spatial_scope.gd")
const DescriptorScript = preload("res://scripts/simulation/aggregates/aggregate_descriptor.gd")
const SnapshotScript = preload("res://scripts/network/contracts/aggregate_snapshot_envelope.gd")

const PACKAGE_HASH: String = "9d7a7c5aa89f9ce6354f7d4f7496c18f258917ab9658b98191cb52af72a2a4fe"


static func create_snapshot(aggregate_id: String, revision: int, tick: int, role: String, container_id: String, members_by_id: Dictionary, quantity: int, metadata: Dictionary = {}) -> Dictionary:
	var type_reference := TypeReferenceScript.create("core:test-transaction-aggregate", "1.0.0", PACKAGE_HASH, AdapterScript.STATE_SCHEMA)
	var identity := IdentityScript.create(aggregate_id, AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, type_reference)
	var authority := AuthorityScript.create("authority/test-main", 3, revision, tick)
	var scope := SpatialScopeScript.create(SpatialScopeScript.KIND_NONE, {})
	var descriptor := DescriptorScript.create(identity, authority, scope, {})
	var state := {
		"role": role,
		"container_id": container_id,
		"members_by_id": members_by_id.duplicate(true),
		"quantity": quantity,
		"metadata": metadata.duplicate(true),
	}
	return SnapshotScript.create("snapshot/%s/r%d" % [aggregate_id.trim_prefix("aggregate/"), revision], descriptor, state)
