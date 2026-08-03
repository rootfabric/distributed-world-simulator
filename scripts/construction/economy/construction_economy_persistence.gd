extends RefCounted
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const KEY_COORDINATOR="construction/economy/coordinator/v1"
const KEY_LEDGER="construction/economy/ledger/v1"
const KEY_WAREHOUSES="construction/economy/warehouses/v1"
static func save(storage,coordinator,ledger,warehouses)->Dictionary:
	if storage==null or not storage.has_method("save_state"):return P.failure("CONSTRUCTION_ECONOMY_STORAGE_REQUIRED")
	for pair in [[KEY_COORDINATOR,coordinator.export_state()],[KEY_LEDGER,ledger.export_state()],[KEY_WAREHOUSES,warehouses.export_state()]]:
		var result=storage.save_state(pair[0],pair[1]);if not bool(result.get("success",false)):return result
	return P.success()
static func load(storage,coordinator,ledger,warehouses)->Dictionary:
	if storage==null or not storage.has_method("load_state"):return P.failure("CONSTRUCTION_ECONOMY_STORAGE_REQUIRED")
	for pair in [[KEY_LEDGER,ledger],[KEY_WAREHOUSES,warehouses],[KEY_COORDINATOR,coordinator]]:
		var result=storage.load_state(pair[0]);if not bool(result.get("success",false)):return result
		var loaded=pair[1].load_state(Dictionary(result.state));if not bool(loaded.get("success",false)):return loaded
	return P.success()
