extends RefCounted
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const KEY="construction/distributed-authority/v1"
static func save(storage,cluster)->Dictionary:
 if storage==null or not storage.has_method("save_state") or cluster==null or not cluster.has_method("export_state"):return P.failure("CONSTRUCTION_DISTRIBUTED_AUTHORITY_PERSISTENCE_DEPENDENCY_REQUIRED")
 return storage.save_state(KEY,cluster.export_state())
static func load(storage,cluster)->Dictionary:
 if storage==null or not storage.has_method("load_state") or cluster==null or not cluster.has_method("load_state"):return P.failure("CONSTRUCTION_DISTRIBUTED_AUTHORITY_PERSISTENCE_DEPENDENCY_REQUIRED")
 var loaded:Dictionary=storage.load_state(KEY);if not bool(loaded.get("success",false)):return loaded
 if typeof(loaded.get("state"))!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_DISTRIBUTED_AUTHORITY_PERSISTED_STATE")
 return cluster.load_state(loaded.state)
