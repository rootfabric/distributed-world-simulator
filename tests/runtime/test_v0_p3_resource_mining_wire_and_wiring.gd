extends SceneTree

const CurrentManifest = preload(
	"res://scripts/network/observability/network_protocol_manifest.gd"
)
const P2Manifest = preload(
	"res://scripts/network/observability/network_protocol_manifest_p2.gd"
)
const ResourceSnapshot = preload(
	"res://scripts/runtime/networked_gameplay/p3/resource_mining_snapshot.gd"
)
const ResourceDelta = preload(
	"res://scripts/runtime/networked_gameplay/p3/resource_mining_delta.gd"
)
const ResourceTarget = preload(
	"res://scripts/runtime/networked_gameplay/p3/resource_mining_target.gd"
)
const EarthResolver = preload(
	"res://scripts/runtime/networked_gameplay/p3/earth_resource_spatial_resolver.gd"
)

const WORLD_CATALOG_PATH := "res://config/worlds/catalog.json"
const P3_APP_PATH := "res://scripts/app/earth_p3_resource_mining_app.gd"
const M3_SERVER_PATH := "res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd"
const M3_CLIENT_PATH := "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd"
const NODE_ID := "resource/earth/ore-demo/1"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_protocol_manifest_changes_for_resource_wire_contract()
	_test_resource_delta_round_trip()
	_test_m3_adapters_expose_resource_contract()
	_test_earth_product_routes_through_p3_presentation()
	_test_resource_target_reuses_existing_interaction_layer()
	_finish()


func _test_protocol_manifest_changes_for_resource_wire_contract() -> void:
	var current := CurrentManifest.create()
	var p2 := P2Manifest.create()
	_assert(bool(CurrentManifest.validate(current).get("success", false)), "P3 protocol manifest validates")
	_assert(String(current.get("protocol_hash", "")) != String(p2.get("protocol_hash", "")), "P3 resource wire contract changes protocol hash from P2")
	var contracts: Dictionary = Dictionary(current.get("contract_versions", {}))
	_assert(contracts.has("resource_mine_command"), "protocol manifest binds resource mine command")
	_assert(contracts.has("resource_mining_snapshot"), "protocol manifest binds resource snapshot")
	_assert(contracts.has("resource_mining_delta"), "protocol manifest binds resource delta")
	var policy: Dictionary = Dictionary(contracts.get("resource_mining_policy", {}))
	_assert(String(policy.get("command_channel", "")) == "CONTROL", "resource command uses existing reliable CONTROL channel")
	_assert(String(policy.get("delta_channel", "")) == "ITEM", "resource delta uses existing reliable ITEM channel")
	_assert(String(policy.get("snapshot_channel", "")) == "RESYNC", "resource snapshot uses existing reliable RESYNC channel")


func _test_resource_delta_round_trip() -> void:
	var before_node := _node_record(8)
	var after_node := _node_record(7)
	var before := ResourceSnapshot.create("authority/v0-p3/wire-test", 1, 4, [before_node])
	var after := ResourceSnapshot.create("authority/v0-p3/wire-test", 1, 5, [after_node])
	var created: Dictionary = ResourceDelta.create(before, after)
	_assert(bool(created.get("success", false)), "resource delta builds across one canonical generation")
	if not bool(created.get("success", false)):
		return
	var delta: Dictionary = Dictionary(created.get("details", {}).get("delta", {}))
	_assert(bool(ResourceDelta.validate(delta).get("success", false)), "resource delta validates")
	var applied: Dictionary = ResourceDelta.apply(before, delta)
	_assert(bool(applied.get("success", false)), "resource delta applies to exact base generation")
	if bool(applied.get("success", false)):
		_assert(Dictionary(applied.get("details", {}).get("snapshot", {})) == after, "resource delta reconstructs exact target snapshot")
	var stale_base := ResourceSnapshot.create("authority/v0-p3/wire-test", 1, 3, [before_node])
	var stale: Dictionary = ResourceDelta.apply(stale_base, delta)
	_assert(not bool(stale.get("success", false)) and String(stale.get("error_code", "")) == "RESOURCE_DELTA_BASE_MISMATCH", "resource delta rejects wrong base generation")
	var tampered := delta.duplicate(true)
	tampered["target_checksum"] = "0".repeat(64)
	tampered["checksum"] = ""
	_assert(not bool(ResourceDelta.validate(tampered).get("success", false)), "resource delta rejects tampered target checksum")


func _test_m3_adapters_expose_resource_contract() -> void:
	var server_script = load(M3_SERVER_PATH)
	var client_script = load(M3_CLIENT_PATH)
	_assert(server_script != null and server_script.can_instantiate(), "P3 M3 dedicated-server adapter loads")
	_assert(client_script != null and client_script.can_instantiate(), "P3 M3 graphical-client adapter loads")
	if server_script != null and server_script.can_instantiate():
		var server = server_script.new()
		_assert(server.has_method("_handle_resource_command"), "P3 M3 server exposes bounded resource command handler")
		_assert(server.has_method("_send_resource_snapshot"), "P3 M3 server exposes resource resync snapshot path")
		server.free()
	if client_script != null and client_script.can_instantiate():
		var client = client_script.new()
		_assert(client.has_method("execute_resource_mine_blocking"), "P3 M3 client exposes resource.mine intent submission")
		_assert(client.has_method("get_resource_mining_snapshot"), "P3 M3 client exposes read-only resource replica")
		_assert(client.has_signal("resource_mining_updated"), "P3 M3 client publishes resource replica updates")
		client.free()


func _test_earth_product_routes_through_p3_presentation() -> void:
	var runtime_script = load(P3_APP_PATH)
	_assert(runtime_script != null and runtime_script.can_instantiate(), "Earth P3 resource-mining runtime loads")
	if runtime_script != null and runtime_script.can_instantiate():
		var runtime = runtime_script.new()
		_assert(runtime.has_method("attach_m3_multiplayer_client"), "P3 Earth runtime preserves M3 attach contract")
		_assert(runtime.has_method("_mine_p3_resource"), "P3 Earth runtime routes interaction to resource.mine")
		_assert(runtime.has_method("create_m3_graphical_client_report"), "P3 Earth runtime extends graphical report contract")
		runtime.free()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(WORLD_CATALOG_PATH))
	_assert(parsed is Dictionary, "world catalog remains valid JSON after P3 routing")
	var earth_runtime := ""
	if parsed is Dictionary:
		for world_value in Dictionary(parsed).get("worlds", []):
			if world_value is Dictionary and String(world_value.get("id", "")) == "earth":
				earth_runtime = String(world_value.get("runtime_script", ""))
				break
	_assert(earth_runtime == P3_APP_PATH, "Earth product catalog routes through P3 resource-mining adapter")


func _test_resource_target_reuses_existing_interaction_layer() -> void:
	var target = ResourceTarget.new()
	_assert(target is Area3D, "resource presentation target is non-blocking Area3D")
	var setup_result: Dictionary = target.setup(
		_node_record(8),
		Callable(self, "_fake_mine")
	)
	_assert(bool(setup_result.get("success", false)), "resource presentation target configures")
	_assert(int(target.collision_layer) == (1 << 19), "resource target reuses isolated P1 interaction collision layer")
	var descriptor: Dictionary = target.get_interaction_descriptor()
	_assert(String(descriptor.get("type", "")) == "resource_node", "resource target exposes resource-node interaction type")
	_assert(String(descriptor.get("resource_node_id", "")) == NODE_ID, "resource target exposes canonical node identity")
	_assert(String(descriptor.get("prompt", "")) == "Добыть руду", "resource target exposes mining prompt")
	var mined: Dictionary = target.interact()
	_assert(bool(mined.get("success", false)), "resource target delegates interaction through injected mining callback")
	var depleted: Dictionary = _node_record(0)
	_assert(bool(target.apply_resource_record(depleted).get("success", false)), "resource target accepts authoritative depletion update")
	_assert(not target.visible and int(target.collision_layer) == 0, "fully depleted resource disappears from interaction presentation")
	target.free()

	var resolver = EarthResolver.new()
	_assert(bool(resolver.setup().get("success", false)), "Earth resource resolver configures for wiring test")
	var resolved: Dictionary = resolver.resolve_planar(Dictionary(_node_record(8).get("spatial", {})))
	_assert(bool(resolved.get("success", false)), "Earth-fixed demo resource resolves")
	if bool(resolved.get("success", false)):
		var planar: Dictionary = Dictionary(resolved.get("details", {}).get("planar_position", {}))
		var distance := Vector2(float(planar.get("x", 0.0)), float(planar.get("z", 0.0))).length()
		_assert(distance > 5.0 and distance < 10.0, "demo ore is visibly nearby but requires approaching before mining")


func _fake_mine(_resource_node_id: String) -> Dictionary:
	return {"success": true, "error_code": "", "details": {}}


func _node_record(remaining_units: int) -> Dictionary:
	return {
		"resource_node_id": NODE_ID,
		"resource_definition_id": "resource/ore",
		"output_definition_id": "item/ore",
		"remaining_units": remaining_units,
		"unit_item_quantity": 1,
		"spatial": {
			"frame": "earth-fixed",
			"latitude_deg": 45.0,
			"longitude_deg": 25.0001,
			"altitude_m": 450.0,
		},
	}


func _assert(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % label)
		return
	failures.append(label)
	push_error("FAIL: %s" % label)


func _finish() -> void:
	print("V0-P3 resource/mining wire+wiring: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
