extends RefCounted

const RegistryScript = preload("res://scripts/simulation/aggregates/aggregate_adapter_registry.gd")
const RepositoryScript = preload("res://scripts/simulation/transactions/aggregate_transaction_repository.gd")
const InvariantRegistryScript = preload("res://scripts/simulation/transactions/transaction_invariant_registry.gd")
const CoordinatorScript = preload("res://scripts/simulation/transactions/aggregate_transaction_coordinator.gd")
const TranslatorScript = preload("res://scripts/construction/authoritative/construction_m0_batch_translator.gd")
const StateAdapterScript = preload("res://scripts/construction/authoritative/construction_m0_state_adapter.gd")

var _registry
var _repository
var _invariants
var _coordinator
var _configured: bool = false


func setup(repository_root: String) -> Dictionary:
	if repository_root.strip_edges().is_empty():
		return _failure("CONSTRUCTION_M0_REPOSITORY_ROOT_REQUIRED")
	_registry = RegistryScript.new()
	var registry_setup: Dictionary = _registry.setup()
	if not bool(registry_setup.get("success", false)):
		return registry_setup
	for row in [
		[TranslatorScript.ITEM_GRAPH_KIND, TranslatorScript.ITEM_GRAPH_STATE_SCHEMA],
		[TranslatorScript.LEDGER_KIND, TranslatorScript.LEDGER_STATE_SCHEMA],
		[TranslatorScript.CONSTRUCT_KIND, "planet_simulator.construct_snapshot.v1"],
	]:
		var registered: Dictionary = _registry.register_adapter(StateAdapterScript.new(String(row[0]), String(row[1])))
		if not bool(registered.get("success", false)):
			return registered
	_repository = RepositoryScript.new()
	var configured_repository: Dictionary = _repository.configure(repository_root)
	if not bool(configured_repository.get("success", false)):
		return configured_repository
	_invariants = InvariantRegistryScript.new()
	var invariant_setup: Dictionary = _invariants.setup()
	if not bool(invariant_setup.get("success", false)):
		return invariant_setup
	_coordinator = CoordinatorScript.new()
	var coordinator_setup: Dictionary = _coordinator.configure(_registry, _repository, _invariants)
	if not bool(coordinator_setup.get("success", false)):
		return coordinator_setup
	_configured = true
	return _success()


func bootstrap(snapshots: Array) -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_M0_BRIDGE_NOT_CONFIGURED")
	return _coordinator.bootstrap(snapshots)


func execute_batch(batch: Dictionary, options: Dictionary = {}) -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_M0_BRIDGE_NOT_CONFIGURED")
	return _coordinator.execute_batch(batch, options)


func get_snapshot(aggregate_id: String) -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_M0_BRIDGE_NOT_CONFIGURED")
	return _coordinator.get_snapshot(aggregate_id)


func get_state_report() -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_M0_BRIDGE_NOT_CONFIGURED")
	return _coordinator.get_state_report()


func get_committed_state() -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_M0_BRIDGE_NOT_CONFIGURED")
	var loaded: Dictionary = _repository.load_or_empty()
	if not bool(loaded.get("success", false)):
		return loaded
	return _success({"state": Dictionary(loaded.get("details", {}).get("state", {})).duplicate(true)})


func list_pending_files() -> Array:
	return _repository.list_pending_files() if _configured else []


func cleanup_pending_files() -> Dictionary:
	if not _configured:
		return _failure("CONSTRUCTION_M0_BRIDGE_NOT_CONFIGURED")
	return _repository.cleanup_pending_files()


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
