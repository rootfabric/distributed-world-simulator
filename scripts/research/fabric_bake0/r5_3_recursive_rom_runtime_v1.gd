extends RefCounted
## Prepared recursive ROM hierarchy. Root steady execution evaluates only four
## reduced equations. Refresh re-prepares exactly the causal changed path.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/r5_3_recursive_rom_compiler_v1.gd")
var _sessions:Dictionary={}; var _bundles:Dictionary={}; var _hashes:Dictionary={}
var prepare_events:=0; var reuse_events:=0; var execute_events:=0; var ready:=false

func _walk(root:Dictionary,path:String,out:Dictionary)->void:
	out[path]=root; var children:Dictionary=root.get("children",{}); var keys:Array=children.keys(); keys.sort()
	for key in keys: _walk(children[key],path+"/"+String(key),out)

func _prepare_session(bundle:Dictionary)->Dictionary:
	var checked:=Compiler.validate_node(bundle); if not checked.success:return checked
	return U.success({"session":{"node_hash":String(bundle.node_hash),"schur_matrix":bundle.reduction.schur_matrix.duplicate(true),"reduced_rhs":bundle.reduction.reduced_rhs.duplicate(),"equation_count":int(bundle.reduction.reduced_equation_count)}})

func prepare(root:Dictionary)->Dictionary:
	_sessions.clear();_bundles.clear();_hashes.clear();prepare_events=0;reuse_events=0;execute_events=0;ready=false
	var nodes:Dictionary={};_walk(root,"root",nodes);var paths:Array=nodes.keys();paths.sort()
	for path in paths:
		var p:=_prepare_session(nodes[path]);if not p.success:return p
		_sessions[path]=p.details.session;_bundles[path]=nodes[path].duplicate(true);_hashes[path]=String(nodes[path].node_hash);prepare_events+=1
	ready=true;return U.success({"node_count":paths.size(),"prepared_sessions":prepare_events})

func execute(path:String,boundary_effort:Array,live_override:Dictionary={})->Dictionary:
	if not ready or not _sessions.has(path):return U.failure("R5_3_RUNTIME_PATH_NOT_PREPARED",{"path":path})
	var live:Dictionary=_bundles[path].live if live_override.is_empty() else live_override;var session:Dictionary=_sessions[path]
	if String(live.get("node_hash",""))!=String(session.node_hash):return U.failure("R5_3_RUNTIME_NODE_HASH_MISMATCH")
	var n:=int(session.equation_count);if boundary_effort.size()!=n:return U.failure("R5_3_RUNTIME_BOUNDARY_SIZE_MISMATCH")
	var flow:Array=[];flow.resize(n)
	for i in range(n):
		var value:float=-float(session.reduced_rhs[i])
		for j in range(n):
			if not U.is_finite_number(boundary_effort[j]):return U.failure("R5_3_RUNTIME_NONFINITE_BOUNDARY")
			value+=float(session.schur_matrix[i][j])*float(boundary_effort[j])
		flow[i]=value
	var power:=0.0;for i in range(n):power+=float(boundary_effort[i])*float(flow[i])
	execute_events+=1;return U.success({"path":path,"level":int(_bundles[path].level),"node_hash":String(_bundles[path].node_hash),"boundary_flow":flow,"boundary_power":power,"runtime_source_component_traversals":0,"executable_equation_count":n})

func execute_root(boundary_effort:Array)->Dictionary:return execute("root",boundary_effort)

func refresh(new_root:Dictionary,expected_changed_paths:Array)->Dictionary:
	if not ready:return U.failure("R5_3_RUNTIME_NOT_READY")
	var nodes:Dictionary={};_walk(new_root,"root",nodes);var paths:Array=nodes.keys();paths.sort();var old_paths:Array=_bundles.keys();old_paths.sort()
	if paths!=old_paths:return U.failure("R5_3_RUNTIME_TOPOLOGY_SHAPE_CHANGED")
	var actual:Array=[]
	for path in paths:
		# A reused hash is not proof that a mutable incoming node is unchanged.
		# Check every ROM identity before classifying changed/reused nodes. This
		# does not compile sources or re-prepare any unaffected session.
		var identity:=Compiler.validate_node_identity(nodes[path]);if not identity.success:return identity
		if String(nodes[path].node_hash)!=String(_hashes[path]):actual.append(String(path))
	var expected:=expected_changed_paths.duplicate();expected.sort();actual.sort();if actual!=expected:return U.failure("R5_3_RUNTIME_CHANGED_PATH_MISMATCH",{"expected":expected,"actual":actual})

	# PRE-FLIGHT: preparing one changed ancestor must not mutate the live registry
	# before every changed descendant has also validated and prepared successfully.
	# Reused sessions/bundles remain the exact previously prepared objects.
	var staged_sessions:Dictionary={}
	var staged_bundles:Dictionary={}
	var staged_hashes:Dictionary={}
	for path in actual:
		var p:=_prepare_session(nodes[path]);if not p.success:return p
		staged_sessions[path]=p.details.session
		staged_bundles[path]=nodes[path].duplicate(true)
		staged_hashes[path]=String(nodes[path].node_hash)

	# COMMIT: after this point there are no rejectable candidate operations.
	for path in actual:
		_sessions[path]=staged_sessions[path]
		_bundles[path]=staged_bundles[path]
		_hashes[path]=staged_hashes[path]
	var prepared:=actual.size();var reused:=paths.size()-prepared
	prepare_events+=prepared;reuse_events+=reused
	return U.success({"changed_paths":actual,"prepared_sessions":prepared,"reused_sessions":reused,"node_count":paths.size()})

func bundle(path:String)->Dictionary:return _bundles.get(path,{}).duplicate(true)
func stats()->Dictionary:return {"prepare_events":prepare_events,"reuse_events":reuse_events,"execute_events":execute_events,"node_count":_sessions.size()}
