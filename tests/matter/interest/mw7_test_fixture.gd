extends RefCounted

const BaseFixtureScript = preload(
	"res://tests/matter/interest/mw7_test_fixture_base.gd"
)

const AUTHORITY_OWNER_ID: String = "authority/mw7-matter-server"
const AUTHORITY_EPOCH: int = 1
const ENERGY_BUDGET_J: float = 9000000000000000.0
const CELL_LEVEL: int = 5

static var _live_interest_servers: Array = []


static func create_authority(root_path: String, max_replay_deltas: int = 64) -> Dictionary:
	var setup: Dictionary = BaseFixtureScript.create_authority(root_path, max_replay_deltas)
	if bool(setup.get("success", false)):
		var interest_server = setup.get("interest_server")
		if interest_server != null:
			_live_interest_servers.append(interest_server)
	return setup


static func create_replica(setup: Dictionary, client_id: String, presenter = null):
	return BaseFixtureScript.create_replica(setup, client_id, presenter)


static func connect_replica(
	setup: Dictionary,
	replica,
	peer_id: String,
	session_id: String,
	actor_id: String
) -> Dictionary:
	return BaseFixtureScript.connect_replica(
		setup,
		replica,
		peer_id,
		session_id,
		actor_id
	)


static func reconnect_replica(
	setup: Dictionary,
	replica,
	old_peer_id: String,
	new_peer_id: String,
	new_session_id: String,
	actor_id: String
) -> Dictionary:
	return BaseFixtureScript.reconnect_replica(
		setup,
		replica,
		old_peer_id,
		new_peer_id,
		new_session_id,
		actor_id
	)


static func request(
	setup: Dictionary,
	fixture_value: Dictionary,
	operation_id: String,
	actor_id: String
) -> Dictionary:
	return BaseFixtureScript.request(
		setup,
		fixture_value,
		operation_id,
		actor_id
	)


static func surface_fixtures(
	setup: Dictionary,
	axis: Vector3,
	maximum_count: int = 8
) -> Array[Dictionary]:
	return BaseFixtureScript.surface_fixtures(setup, axis, maximum_count)


static func nearby_fixtures(
	setup: Dictionary,
	axis: Vector3,
	radius_cells: int,
	maximum_count: int
) -> Array[Dictionary]:
	return BaseFixtureScript.nearby_fixtures(
		setup,
		axis,
		radius_cells,
		maximum_count
	)


static func shutdown_all() -> Dictionary:
	var servers: Array = _live_interest_servers.duplicate()
	_live_interest_servers.clear()
	var cleanup_failures: Array[Dictionary] = []
	for server in servers:
		if server == null or not server.has_method("shutdown"):
			cleanup_failures.append({"error_code": "MW7_INTEREST_SERVER_SHUTDOWN_MISSING"})
			continue
		var result_value = server.shutdown()
		if typeof(result_value) != TYPE_DICTIONARY \
				or not bool(Dictionary(result_value).get("success", false)):
			cleanup_failures.append({
				"error_code": (
					String(Dictionary(result_value).get("error_code", "MW7_INTEREST_SERVER_SHUTDOWN_FAILED"))
					if typeof(result_value) == TYPE_DICTIONARY
					else "MW7_INTEREST_SERVER_SHUTDOWN_INVALID_RESULT"
				),
			})
	return {
		"success": cleanup_failures.is_empty(),
		"server_count": servers.size(),
		"failures": cleanup_failures,
	}
