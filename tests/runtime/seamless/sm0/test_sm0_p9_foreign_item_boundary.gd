extends SceneTree

const Contract = preload("res://scripts/runtime/seamless/sm0/sm0_p9_foreign_item_boundary_contract.gd")
const AuthorityNode = preload("res://scripts/runtime/seamless/sm0/sm0_p9_item_authority_node.gd")
const Coordinator = preload("res://scripts/runtime/seamless/sm0/sm0_p9_boundary_coordinator.gd")

var _assertions := 0
var _failed := false
var _nodes: Array[Node] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var coordinator = Coordinator.new()
	var world_a = _new_authority("WorldA", Contract.AUTHORITY_A)
	var world_c = _new_authority("WorldC", Contract.AUTHORITY_C)
	var ship = _new_authority("Ship", Contract.SHIP_AUTHORITY)
	if _failed:
		return _finish()

	_check_success(coordinator.observe_outer_owner(Contract.AUTHORITY_A, 1), "observe initial outer A")
	_check(coordinator.current_outer_authority_id() == Contract.AUTHORITY_A, "outer starts A")
	_check(coordinator.outer_authority_epoch() == 1, "outer epoch starts 1")

	var foreign_world := Contract.create_item_envelope("item/p9/foreign/ore-01", Contract.AUTHORITY_A, Contract.SCOPE_WORLD, 1, 1, 0)
	var ship_native := Contract.create_item_envelope("item/p9/ship/tool-01", Contract.SHIP_AUTHORITY, Contract.SCOPE_SHIP, 1, 1, 0)
	_check_success(Contract.validate_item_envelope(foreign_world), "foreign envelope valid")
	_check_success(Contract.validate_item_envelope(ship_native), "ship envelope valid")
	_check_success(world_a.seed_item_for_tests(foreign_world), "seed foreign item on A")
	_check_success(ship.seed_item_for_tests(ship_native), "seed ship-native item")
	_check(world_a.has_item("item/p9/foreign/ore-01"), "A owns foreign item initially")
	_check(ship.has_item("item/p9/ship/tool-01"), "ship owns native item initially")
	_check(not ship.has_item("item/p9/foreign/ore-01"), "ship has no foreign item initially")

	var foreign_interaction := Contract.create_interaction_request("operation/p9/foreign/inspect/1", Contract.SHIP_AUTHORITY, foreign_world, Contract.INTERACTION_INSPECT)
	var illegal_direct: Dictionary = ship.apply_interaction(foreign_interaction)
	_check(not bool(illegal_direct.get("success", true)), "direct foreign mutation rejected")
	_check(String(illegal_direct.get("error_code", "")) == "SM0_P9_FOREIGN_DIRECT_MUTATION_FORBIDDEN", "direct foreign exact error")
	_check(int(world_a.get_item("item/p9/foreign/ore-01").get("item_revision", 0)) == 1, "direct rejection leaves owner revision unchanged")
	_check_success(coordinator.route_interaction(ship, world_a, foreign_interaction), "route foreign inspect to owner A")
	var inspected: Dictionary = world_a.get_item("item/p9/foreign/ore-01")
	_check(int(inspected.get("item_revision", 0)) == 2, "foreign interaction advances owner revision")
	_check(int(inspected.get("interaction_sequence", 0)) == 1, "foreign interaction sequence advances")
	_check(String(inspected.get("owner_authority_id", "")) == Contract.AUTHORITY_A, "interaction does not transfer authority")
	var routed_replay := coordinator.route_interaction(ship, world_a, foreign_interaction)
	_check_success(routed_replay, "exact foreign interaction replay accepted")
	_check(bool(Dictionary(routed_replay.get("details", {})).get("replay", false)), "foreign replay identified")
	_check(int(world_a.get_item("item/p9/foreign/ore-01").get("item_revision", 0)) == 2, "foreign replay mutation-free")

	var stale_interaction := Contract.create_interaction_request("operation/p9/foreign/stale/1", Contract.SHIP_AUTHORITY, foreign_world, Contract.INTERACTION_USE)
	var stale_result := coordinator.route_interaction(ship, world_a, stale_interaction)
	_check(not bool(stale_result.get("success", true)), "stale foreign interaction rejected")
	_check(String(stale_result.get("error_code", "")) == "SM0_P9_INTERACTION_REVISION_STALE", "stale interaction exact error")
	_check(int(world_a.get_item("item/p9/foreign/ore-01").get("item_revision", 0)) == 2, "stale interaction mutation-free")

	var freeze_request := Contract.create_transfer_request("operation/p9/import/freeze-probe/1", inspected, Contract.SHIP_AUTHORITY, Contract.SCOPE_SHIP)
	_check_success(world_a.prepare_send(freeze_request), "freeze probe source prepare")
	_check_success(ship.prepare_receive(freeze_request), "freeze probe target shadow prepare")
	var frozen_interaction_request := Contract.create_interaction_request("operation/p9/foreign/frozen/1", Contract.SHIP_AUTHORITY, inspected, Contract.INTERACTION_USE)
	var frozen_interaction: Dictionary = world_a.apply_interaction(frozen_interaction_request)
	_check(not bool(frozen_interaction.get("success", true)), "prepared source item rejects concurrent interaction")
	_check(String(frozen_interaction.get("error_code", "")) == "SM0_P9_ITEM_TRANSFER_FROZEN", "prepared source exact frozen error")
	_check(int(world_a.get_item("item/p9/foreign/ore-01").get("item_revision", 0)) == 2, "frozen rejection mutation-free")
	_check_success(world_a.cancel_send(freeze_request), "cancel freeze probe source")
	_check_success(ship.abort_receive(freeze_request), "abort freeze probe target shadow")

	var import_request := Contract.create_transfer_request("operation/p9/import/1", inspected, Contract.SHIP_AUTHORITY, Contract.SCOPE_SHIP)
	_check_success(Contract.validate_transfer_request(import_request), "import request valid")
	var import_result := coordinator.transfer(world_a, ship, import_request)
	_check_success(import_result, "world-to-ship import commits")
	var imported := Dictionary(Dictionary(import_result.get("details", {})).get("item", {}))
	_check(not world_a.has_item("item/p9/foreign/ore-01"), "source A retired imported item")
	_check(ship.has_item("item/p9/foreign/ore-01"), "ship activates imported item")
	_check(String(imported.get("item_id", "")) == "item/p9/foreign/ore-01", "import preserves item identity")
	_check(String(imported.get("owner_authority_id", "")) == Contract.SHIP_AUTHORITY, "import owner becomes ship")
	_check(String(imported.get("authority_scope", "")) == Contract.SCOPE_SHIP, "import scope becomes ship")
	_check(int(imported.get("ownership_epoch", 0)) == 2, "import increments ownership epoch exactly once")
	_check(int(imported.get("item_revision", 0)) == 3, "import increments item revision exactly once")
	_check(int(imported.get("interaction_sequence", 0)) == 1, "import preserves interaction sequence")
	var import_replay := coordinator.transfer(world_a, ship, import_request)
	_check_success(import_replay, "exact import replay accepted")
	_check(bool(Dictionary(import_replay.get("details", {})).get("replay", false)), "import replay identified")
	_check(int(ship.get_item("item/p9/foreign/ore-01").get("ownership_epoch", 0)) == 2, "import replay ownership mutation-free")
	_check(int(ship.get_item("item/p9/foreign/ore-01").get("item_revision", 0)) == 3, "import replay revision mutation-free")

	var imported_use_request := Contract.create_interaction_request("operation/p9/imported/use/1", Contract.SHIP_AUTHORITY, ship.get_item("item/p9/foreign/ore-01"), Contract.INTERACTION_USE)
	_check_success(ship.apply_interaction(imported_use_request), "imported item usable locally on ship")
	var used_imported: Dictionary = ship.get_item("item/p9/foreign/ore-01")
	_check(int(used_imported.get("interaction_sequence", 0)) == 2, "local ship use advances interaction sequence")
	_check(int(used_imported.get("item_revision", 0)) == 4, "local ship use advances revision")
	_check(String(used_imported.get("owner_authority_id", "")) == Contract.SHIP_AUTHORITY, "local use keeps ship authority")

	var native_before: Dictionary = ship.get_item("item/p9/ship/tool-01")
	var native_request := Contract.create_interaction_request("operation/p9/native/use/1", Contract.SHIP_AUTHORITY, native_before, Contract.INTERACTION_USE)
	_check_success(ship.apply_interaction(native_request), "ship-native interaction commits locally")
	var native_after: Dictionary = ship.get_item("item/p9/ship/tool-01")
	_check(int(native_after.get("item_revision", 0)) == 2, "ship-native revision advances")
	_check(int(native_after.get("ownership_epoch", 0)) == 1, "ship-native ownership epoch unchanged")

	_check_success(coordinator.observe_outer_owner(Contract.AUTHORITY_C, 2), "observe P8 outer pivot A to C")
	_check(coordinator.current_outer_authority_id() == Contract.AUTHORITY_C, "current outer owner becomes C")
	_check(coordinator.outer_authority_epoch() == 2, "outer epoch becomes 2")
	var stale_outer := coordinator.observe_outer_owner(Contract.AUTHORITY_A, 1)
	_check(not bool(stale_outer.get("success", true)), "stale outer observation rejected")
	_check(String(stale_outer.get("error_code", "")) == "SM0_P9_OUTER_OWNER_STALE", "stale outer exact error")
	var same_epoch_mutation := coordinator.observe_outer_owner(Contract.AUTHORITY_A, 2)
	_check(not bool(same_epoch_mutation.get("success", true)), "same-epoch owner mutation rejected")
	_check(String(same_epoch_mutation.get("error_code", "")) == "SM0_P9_OUTER_OWNER_SAME_EPOCH_MUTATION", "same-epoch outer exact error")

	var stale_export_to_a := Contract.create_transfer_request("operation/p9/export/stale-a/1", used_imported, Contract.AUTHORITY_A, Contract.SCOPE_WORLD)
	var stale_route_result := coordinator.transfer(ship, world_c, stale_export_to_a)
	_check(not bool(stale_route_result.get("success", true)), "wrong current-world target rejected")
	_check(String(stale_route_result.get("error_code", "")) == "SM0_P9_TRANSFER_TARGET_ROUTE_MISMATCH", "wrong current-world route exact error")
	_check(ship.has_item("item/p9/foreign/ore-01"), "wrong target leaves ship item active")
	_check(not world_c.has_item("item/p9/foreign/ore-01"), "wrong target does not activate C")

	var export_request := coordinator.create_export_request("operation/p9/export/1", ship.get_item("item/p9/foreign/ore-01"))
	_check(String(export_request.get("target_authority_id", "")) == Contract.AUTHORITY_C, "export resolves current outer C")
	_check_success(Contract.validate_transfer_request(export_request), "export request valid")
	var export_result := coordinator.transfer(ship, world_c, export_request)
	_check_success(export_result, "ship-to-world C export commits")
	var exported := Dictionary(Dictionary(export_result.get("details", {})).get("item", {}))
	_check(not ship.has_item("item/p9/foreign/ore-01"), "ship retires exported item")
	_check(world_c.has_item("item/p9/foreign/ore-01"), "C activates exported item")
	_check(String(exported.get("item_id", "")) == "item/p9/foreign/ore-01", "export preserves stable item identity")
	_check(String(exported.get("owner_authority_id", "")) == Contract.AUTHORITY_C, "export owner becomes current outer C")
	_check(String(exported.get("authority_scope", "")) == Contract.SCOPE_WORLD, "export scope becomes world")
	_check(int(exported.get("ownership_epoch", 0)) == 3, "export increments ownership epoch")
	_check(int(exported.get("item_revision", 0)) == 5, "export increments revision")
	_check(int(exported.get("interaction_sequence", 0)) == 2, "export preserves interactions")
	_check(ship.has_item("item/p9/ship/tool-01"), "ship-native item survives foreign export")
	_check(int(ship.get_item("item/p9/ship/tool-01").get("ownership_epoch", 0)) == 1, "ship-native ownership unaffected by outer pivot")

	var old_a_request := Contract.create_interaction_request("operation/p9/old-a/use/1", Contract.SHIP_AUTHORITY, exported, Contract.INTERACTION_USE)
	var old_a_route := coordinator.route_interaction(ship, world_a, old_a_request)
	_check(not bool(old_a_route.get("success", true)), "old A cannot service C-owned item")
	_check(String(old_a_route.get("error_code", "")) == "SM0_P9_INTERACTION_ROUTE_OWNER_MISMATCH", "old A route exact error")
	_check_success(coordinator.route_interaction(ship, world_c, old_a_request), "foreign interaction routes to current C owner")
	var world_after: Dictionary = world_c.get_item("item/p9/foreign/ore-01")
	_check(int(world_after.get("item_revision", 0)) == 6, "C-owned foreign interaction advances revision")
	_check(int(world_after.get("interaction_sequence", 0)) == 3, "C-owned foreign interaction advances sequence")

	var rollback_source_item := Contract.create_item_envelope("item/p9/foreign/rollback-01", Contract.AUTHORITY_C, Contract.SCOPE_WORLD, 1, 1, 0)
	_check_success(world_c.seed_item_for_tests(rollback_source_item), "seed rollback probe on C")
	var rollback_request := Contract.create_transfer_request("operation/p9/import/rollback/1", rollback_source_item, Contract.SHIP_AUTHORITY, Contract.SCOPE_SHIP)
	ship.fail_next_receive_commit_for_tests()
	var rollback_result := coordinator.transfer(world_c, ship, rollback_request)
	_check(not bool(rollback_result.get("success", true)), "target commit failure returned")
	_check(String(rollback_result.get("error_code", "")) == "SM0_P9_INJECTED_TARGET_COMMIT_FAILURE", "target failure exact error")
	_check(world_c.has_item("item/p9/foreign/rollback-01"), "source restored after target failure")
	_check(not ship.has_item("item/p9/foreign/rollback-01"), "target shadow aborted after failure")
	_check(int(world_c.get_item("item/p9/foreign/rollback-01").get("ownership_epoch", 0)) == 1, "rollback restores ownership epoch exactly")
	_check(int(world_c.get_item("item/p9/foreign/rollback-01").get("item_revision", 0)) == 1, "rollback restores revision exactly")
	var rollback_replay := coordinator.transfer(world_c, ship, rollback_request)
	_check(not bool(rollback_replay.get("success", true)), "failed transfer replay returns failure")
	_check(String(rollback_replay.get("error_code", "")) == "SM0_P9_INJECTED_TARGET_COMMIT_FAILURE", "failed transfer replay preserves error")
	_check(bool(Dictionary(rollback_replay.get("details", {})).get("replay", false)), "failed transfer replay identified")
	_check(world_c.has_item("item/p9/foreign/rollback-01") and not ship.has_item("item/p9/foreign/rollback-01"), "failed transfer replay mutation-free")

	var conflict_item := Contract.create_item_envelope("item/p9/foreign/conflict-01", Contract.AUTHORITY_A, Contract.SCOPE_WORLD, 1, 1, 0)
	_check_success(world_a.seed_item_for_tests(conflict_item), "seed replay-conflict probe on A")
	var conflicting_request := Contract.create_transfer_request("operation/p9/import/1", conflict_item, Contract.SHIP_AUTHORITY, Contract.SCOPE_SHIP)
	var conflicting_replay := coordinator.transfer(world_a, ship, conflicting_request)
	_check(not bool(conflicting_replay.get("success", true)), "same operation mutated replay rejected")
	_check(String(conflicting_replay.get("error_code", "")) == "SM0_P9_TRANSFER_REPLAY_CONFLICT", "mutated replay exact conflict")
	_check(world_a.has_item("item/p9/foreign/conflict-01"), "replay conflict leaves unrelated source item active")

	_check(int(coordinator.status_for_tests().get("operation_ledger_count", 0)) == 2, "only committed import/export in coordinator ledger")
	_check(int(coordinator.status_for_tests().get("failure_ledger_count", 0)) == 1, "failed rollback operation retained for deterministic replay")
	_check(int(world_a.status_for_tests().get("active_item_count", -1)) == 1, "A retains only replay-conflict probe")
	_check(int(world_c.status_for_tests().get("active_item_count", 0)) == 2, "C owns exported and rollback probe")
	_check(int(ship.status_for_tests().get("active_item_count", 0)) == 1, "ship retains only native item after export")

	_finish()

func _new_authority(node_name: String, authority_id: String):
	var node = AuthorityNode.new()
	node.name = node_name
	root.add_child(node)
	_nodes.append(node)
	_check_success(node.setup(authority_id), "%s setup" % node_name)
	return node

func _check_success(result: Dictionary, label: String) -> void:
	_check(bool(result.get("success", false)), "%s: %s" % [label, String(result.get("error_code", ""))])

func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		return
	_failed = true
	push_error("P9 assertion failed: %s" % label)

func _finish() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.queue_free()
	print("SM0 P9 foreign item boundary: %s (%d assertions)" % ["FAIL" if _failed else "PASS", _assertions])
	quit(1 if _failed else 0)