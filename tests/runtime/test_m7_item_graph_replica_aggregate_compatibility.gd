extends SceneTree

const AdapterScript = preload(
	"res://scripts/runtime/networked_gameplay/m7/m7_item_graph_replica_adapter.gd"
)

var _assertions := 0
var _failures := 0


func _initialize() -> void:
	var adapter = AdapterScript.new()
	_assert_success(adapter.setup("a"), "configure M7 adapter")

	var canonical: Dictionary = {
		"schema": "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1",
		"authority_owner_id": "authority/test",
		"authority_epoch": 1,
		"revision": 7,
		"checksum": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		"inventories": {
			"a": {
				"inventory": ["item/server-output/oversized-ore"],
				"hotbar": [],
				"selected_hotbar_index": 0,
			},
		},
		"items": [
			{
				"item_id": "item/server-output/oversized-ore",
				"definition_id": "item/ore",
				"quantity": 125,
				"location": {
					"kind": "INVENTORY",
					"player_id": "a",
					"slot_index": 0,
				},
				"mounted": false,
				"revision": 7,
			},
		],
		"containers": [],
		"mounts": [
			{
				"mount_id": "mount/shared/socket/1",
				"item_id": "",
			},
		],
	}

	var converted: Dictionary = adapter.create_replica_snapshot(canonical)
	_assert_success(converted, "project oversized canonical ore stack")
	var details: Dictionary = Dictionary(converted.get("details", {}))
	_assert_true(
		int(details.get("canonical_revision", -1)) == 7,
		"replica binds canonical revision"
	)
	_assert_true(
		String(details.get("canonical_checksum", ""))
			== String(canonical["checksum"]),
		"replica binds canonical checksum"
	)
	var encoded := JSON.stringify(details.get("graph_snapshot", {}))
	_assert_true(
		encoded.contains("\"quantity\":125"),
		"replica preserves canonical aggregate quantity above presentation default max_stack"
	)
	_finish()


func _assert_success(result: Dictionary, message: String) -> void:
	_assert_true(
		bool(result.get("success", false)),
		"%s: %s" % [message, String(result.get("error_code", ""))]
	)


func _assert_true(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("[M7-AGGREGATE-REPLICA] %s" % message)


func _finish() -> void:
	if _failures == 0:
		print("M7 aggregate replica compatibility: PASS (%d assertions, 0 failures)" % _assertions)
		quit(0)
		return
	print("M7 aggregate replica compatibility: FAIL (%d assertions, %d failures)" % [
		_assertions,
		_failures,
	])
	quit(1)
