extends RefCounted
## R5.3 recursive exact-linear ROM composition.
## Leaves are accepted T1 capsules. Parent compilers consume child boundary ROMs
## only and use the same exact Schur reducer, without weakening T1's >=100 hidden
## variable acceptance floor. Hidden child source graphs are never traversed here.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/linear_conductance_component_graph_v1.gd")
const GraphCompiler = preload("res://scripts/research/fabric_bake0/linear_conductance_graph_compiler_v1.gd")
const Reducer = preload("res://scripts/research/fabric_bake0/exact_boundary_reducer_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/exact_boundary_reduction_descriptor_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const T1Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v1.gd")
const T1 = preload("res://scripts/research/fabric_bake0/r5_t1_boundary_network_capsule_compiler_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Boundary = preload("res://scripts/research/fabric_bake0/physical_boundary_contract_v1.gd")
const Dependencies = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const Validated = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")
const ErrorEnvelope = preload("res://scripts/research/fabric_bake0/error_envelope_v1.gd")
const Conservation = preload("res://scripts/research/fabric_bake0/conservation_envelope_v1.gd")

const SCHEMA := "planet_simulator.fabric_r5_3_recursive_rom_node.v1"
const CAPSULE_SCHEMA := "planet_simulator.fabric_r5_3_recursive_rom_capsule.v1"
const PORTS := 4
const BOUNDARY_PORT_IDS: Array[String] = ["port/electrical-a", "port/electrical-b", "port/electrical-c", "port/electrical-d"]
const ZERO_TOL := 2.0e-10
const VERSION := "FABRIC_R5_3_RECURSIVE_ROM_COMPILER_R1"
const CAPSULE_FIELDS: Array[String] = ["schema","node_id","level","graph_hash","descriptor_checksum","child_node_hashes","topology_revision","physical_source_components","compiled_input_components","executable_equation_count","runtime_source_traversals_per_execute","build_generation","source_anchor","checksum"]
const GRAPH_COMPILER := "FABRIC_R5_2_LINEAR_COMPONENT_GRAPH_COMPILER_R1"

static func _slug(value: String) -> String:
	return value.replace("/", "-").replace("_", "-")

static func _boundary_contract() -> Dictionary:
	var ports: Array = []
	for suffix in ["a", "b", "c", "d"]:
		ports.append({"port_id":"port/electrical-%s" % suffix, "physical_domain":"ELECTRICAL", "effort_quantity":"quantity/voltage", "flow_quantity":"quantity/current", "effort_dimension":[1,2,-3,-1,0,0,0], "flow_dimension":[0,0,0,1,0,0,0], "frame":"frame/electrical-reference", "orientation":"INTO_SUBSYSTEM", "conservation_group":"group/electrical-power", "event_observables":[]})
	return Boundary.create(ports)

static func _request(graph: Dictionary, node_id: String, child_checksums: Array, topology_revision: int, build_generation: int) -> Dictionary:
	var dependency_identity := {"version":VERSION, "children":child_checksums, "topology_revision":topology_revision}
	var dependency_hash := U.canonical_hash(dependency_identity)
	var source_id := "construct/r5-3-%s" % _slug(node_id)
	var construction := SourceRevision.create("CONSTRUCTION", source_id, 23, build_generation, String(graph.graph_hash), dependency_hash)
	if construction.is_empty(): return {}
	var frontier := Frontier.create([construction]); var source_key := U.source_key("CONSTRUCTION", source_id)
	var authority := Authority.create("server/fabric-r5", [{"source_domain":"CONSTRUCTION", "source_id":source_id, "authority_epoch":23, "owner_id":"server/fabric-r5"}], [source_key])
	var boundary := _boundary_contract()
	var deps: Array = [{"dependency_id":"dependency/r5-3-recursive-rom-compiler", "dependency_hash":U.canonical_hash({"version":VERSION})}]
	for index in range(child_checksums.size()): deps.append({"dependency_id":"dependency/r5-3-child-%02d" % index, "dependency_hash":String(child_checksums[index])})
	var dependency_set := Dependencies.create(deps)
	var validated := Validated.create(String(frontier.frontier_hash), String(graph.graph_hash), [], ["STEADY"], 0.0)
	var error := ErrorEnvelope.create(1.0e-10,1.0e-10,1.0e-9,1.0e-10,1.0e-8,1.0e-10,0.0,0.0,0.0,0.0,0.0,1.0,true)
	var conservation := Conservation.create(1.0e-8,0.0,0.0,0.0,0.0)
	if frontier.is_empty() or authority.is_empty() or boundary.is_empty() or dependency_set.is_empty() or validated.is_empty() or error.is_empty() or conservation.is_empty(): return {}
	return {"artifact_id":"bake/r5-3-%s" % _slug(node_id), "canonical_source_frontier":frontier, "authority_envelope":authority, "dependency_set":dependency_set, "fabric_graph_hash":String(graph.graph_hash), "fabric_compiler_version":GRAPH_COMPILER, "boundary_contract":boundary, "bake_policy_hash":U.canonical_hash({"policy":"r5-3-recursive-exact-linear", "topology_revision":topology_revision}), "validated_domain":validated, "error_envelope":error, "conservation_envelope":conservation, "build_generation":build_generation, "linear_system":{}, "pivot_relative_tolerance":1.0e-12, "symmetry_tolerance":2.0e-10, "passivity_tolerance":2.0e-10, "require_symmetric":true, "require_passive_laplacian":true}

static func _child_hashes(children: Dictionary) -> Dictionary:
	var out := {}; var keys: Array = children.keys(); keys.sort()
	for key in keys: out[String(key)] = String(children[key].node_hash)
	return out

static func _capsule(node_id: String, level: int, graph_hash: String, reduction: Dictionary, children: Dictionary, topology_revision: int, physical_components: int, compiled_input_components: int, build_generation: int, source_anchor: String) -> Dictionary:
	var value := {"schema":CAPSULE_SCHEMA, "node_id":node_id, "level":level, "graph_hash":graph_hash, "descriptor_checksum":String(reduction.checksum), "child_node_hashes":_child_hashes(children), "topology_revision":topology_revision, "physical_source_components":physical_components, "compiled_input_components":compiled_input_components, "executable_equation_count":int(reduction.reduced_equation_count), "runtime_source_traversals_per_execute":0, "build_generation":build_generation, "source_anchor":source_anchor, "checksum":""}
	value.checksum = U.compute_checksum(value)
	return value

static func _node_hash(capsule: Dictionary, reduction: Dictionary) -> String:
	return U.canonical_hash({"capsule_checksum":String(capsule.checksum), "reduction_checksum":String(reduction.checksum)})

static func validate_node(node: Dictionary) -> Dictionary:
	if node.get("schema") != SCHEMA or typeof(node.get("capsule")) != TYPE_DICTIONARY or typeof(node.get("reduction")) != TYPE_DICTIONARY or typeof(node.get("children")) != TYPE_DICTIONARY: return U.failure("R5_3_NODE_SHAPE_INVALID")
	if not U.is_json_integer(node.get("level")) or int(node.level) < 0 or int(node.level) > 3: return U.failure("R5_3_NODE_LEVEL_INVALID")
	var children: Dictionary = node.children
	if (int(node.level) == 0 and not children.is_empty()) or (int(node.level) > 0 and children.is_empty()): return U.failure("R5_3_NODE_HIERARCHY_SHAPE_INVALID")
	for raw_key in children.keys():
		var child = children[raw_key]
		if typeof(child) != TYPE_DICTIONARY: return U.failure("R5_3_CHILD_NODE_SHAPE_INVALID", {"child":String(raw_key)})
		if not U.is_json_integer(child.get("level")) or int(child.level) != int(node.level) - 1: return U.failure("R5_3_CHILD_LEVEL_MISMATCH", {"child":String(raw_key),"parent_level":int(node.level),"child_level":child.get("level")})
	var shape := U.validate_exact_fields(node.capsule, CAPSULE_FIELDS)
	if not shape.success or node.capsule.get("schema") != CAPSULE_SCHEMA or not U.validate_checksum(node.capsule).success: return U.failure("R5_3_CAPSULE_INVALID")
	var checked := Descriptor.validate(node.reduction); if not checked.success: return checked
	if String(node.capsule.descriptor_checksum) != String(node.reduction.checksum): return U.failure("R5_3_CAPSULE_DESCRIPTOR_MISMATCH")
	if not U.is_lower_hex_64(node.capsule.get("graph_hash")) or not U.is_lower_hex_64(node.capsule.get("source_anchor")): return U.failure("R5_3_CAPSULE_PROVENANCE_INVALID")
	if node.capsule.child_node_hashes != _child_hashes(node.children): return U.failure("R5_3_CAPSULE_CHILD_DEPENDENCY_MISMATCH")
	if int(node.capsule.level) != int(node.level) or int(node.capsule.topology_revision) != int(node.topology_revision) or int(node.capsule.build_generation) != int(node.build_generation): return U.failure("R5_3_CAPSULE_REVISION_MISMATCH")
	if int(node.capsule.physical_source_components) != int(node.physical_source_components) or int(node.capsule.compiled_input_components) != int(node.compiled_input_components): return U.failure("R5_3_CAPSULE_COMPLEXITY_ACCOUNTING_MISMATCH")
	if int(node.capsule.executable_equation_count) != PORTS or int(node.capsule.runtime_source_traversals_per_execute) != 0: return U.failure("R5_3_CAPSULE_EXECUTION_CONTRACT_INVALID")
	if typeof(node.get("compiled_graph")) != TYPE_DICTIONARY or String(node.compiled_graph.get("graph_hash", "")) != String(node.capsule.graph_hash): return U.failure("R5_3_CAPSULE_GRAPH_BINDING_MISMATCH")
	if String(node.get("node_hash", "")) != _node_hash(node.capsule, node.reduction): return U.failure("R5_3_NODE_HASH_MISMATCH")
	if typeof(node.get("live")) != TYPE_DICTIONARY or String(node.live.get("node_hash", "")) != String(node.node_hash) or int(node.live.get("build_generation", -1)) != int(node.build_generation): return U.failure("R5_3_NODE_LIVE_MISMATCH")
	return U.success()

static func _validate_t1_leaf_binding(graph: Dictionary, details: Dictionary) -> Dictionary:
	var graph_checked := Graph.validate(graph)
	if not graph_checked.success:
		return U.failure("R5_3_LEAF_SOURCE_GRAPH_INVALID", {"cause":graph_checked})
	for field in ["capsule", "artifact", "reduction", "graph_compile", "linear_system", "bake_request"]:
		if typeof(details.get(field)) != TYPE_DICTIONARY:
			return U.failure("R5_3_LEAF_T1_DETAILS_INCOMPLETE", {"field":field})
	var capsule: Dictionary = details.capsule
	var artifact: Dictionary = details.artifact
	var reduction: Dictionary = details.reduction
	var capsule_checked := T1Capsule.validate(capsule)
	if not capsule_checked.success:
		return U.failure("R5_3_LEAF_T1_CAPSULE_INVALID", {"cause":capsule_checked})
	var artifact_checked := Artifact.validate(artifact)
	if not artifact_checked.success:
		return U.failure("R5_3_LEAF_T1_ARTIFACT_INVALID", {"cause":artifact_checked})
	var reduction_checked := Descriptor.validate(reduction)
	if not reduction_checked.success:
		return U.failure("R5_3_LEAF_T1_REDUCTION_INVALID", {"cause":reduction_checked})
	var graph_hash := String(graph.graph_hash)
	if String(capsule.fabric_graph_hash) != graph_hash \
	or String(artifact.source_binding.fabric_graph_hash) != graph_hash \
	or String(details.graph_compile.get("graph_hash", "")) != graph_hash:
		return U.failure("R5_3_LEAF_T1_GRAPH_BINDING_MISMATCH")
	var exact_graph_compile := GraphCompiler.compile(graph)
	if not exact_graph_compile.success:
		return U.failure("R5_3_LEAF_SOURCE_GRAPH_COMPILE_FAILED", {"cause":exact_graph_compile})
	var exact_system_hash := String(exact_graph_compile.details.linear_system.system_hash)
	if String(details.linear_system.get("system_hash", "")) != exact_system_hash \
	or String(details.graph_compile.get("linear_system", {}).get("system_hash", "")) != exact_system_hash \
	or String(reduction.get("source_system_hash", "")) != exact_system_hash:
		return U.failure("R5_3_LEAF_T1_SYSTEM_BINDING_MISMATCH")
	# A checksum-repaired descriptor can lie about source_system_hash while retaining
	# a Schur matrix from another graph. Re-run the canonical T1 compiler on the
	# exact supplied source graph/request and require the complete derived bundle to
	# be byte-semantically identical. This also inherits T1's >=100 internal gate.
	var exact_t1 := T1.compile(graph, details.bake_request, String(capsule.capsule_id))
	if not bool(exact_t1.get("success", false)) or typeof(exact_t1.get("details")) != TYPE_DICTIONARY:
		return U.failure("R5_3_LEAF_T1_CANONICAL_RECOMPILE_FAILED", {"cause":exact_t1})
	var exact_details: Dictionary = exact_t1.details
	for field in ["linear_system", "graph_compile", "reduction", "artifact", "capsule"]:
		if U.canonical_hash(details[field]) != U.canonical_hash(exact_details[field]):
			return U.failure("R5_3_LEAF_T1_CANONICAL_RECOMPILE_MISMATCH", {"field":field})
	if int(details.graph_compile.get("component_count", -1)) != graph.components.size() \
	or int(capsule.source_component_count) != graph.components.size():
		return U.failure("R5_3_LEAF_T1_SOURCE_COUNT_MISMATCH")
	if String(capsule.physical_bake_artifact_checksum) != String(artifact.checksum) \
	or String(capsule.source_binding_checksum) != String(artifact.source_binding.checksum) \
	or String(capsule.source_frontier_hash) != String(artifact.source_binding.frontier_hash) \
	or String(capsule.boundary_contract_hash) != String(artifact.boundary_contract.contract_hash):
		return U.failure("R5_3_LEAF_T1_ARTIFACT_BINDING_MISMATCH")
	if String(capsule.executable_descriptor_hash) != String(reduction.checksum) \
	or String(artifact.reduced_model_descriptor_hash) != String(reduction.checksum):
		return U.failure("R5_3_LEAF_T1_DESCRIPTOR_BINDING_MISMATCH")
	if String(capsule.reduced_state_schema_hash) != String(artifact.reduced_state_schema_hash):
		return U.failure("R5_3_LEAF_T1_STATE_SCHEMA_BINDING_MISMATCH")
	if int(capsule.full_equation_count) != int(reduction.full_equation_count) \
	or int(capsule.executable_equation_count) != int(reduction.reduced_equation_count) \
	or int(capsule.executable_equation_count) != PORTS \
	or int(capsule.runtime_source_traversals_per_execute) != 0:
		return U.failure("R5_3_LEAF_T1_EXECUTION_CONTRACT_MISMATCH")
	if int(capsule.build_generation) != int(artifact.build_generation):
		return U.failure("R5_3_LEAF_T1_GENERATION_MISMATCH")
	return U.success()

static func leaf_from_t1(node_id: String, graph: Dictionary, compiled: Dictionary) -> Dictionary:
	if not bool(compiled.get("success", false)) or typeof(compiled.get("details")) != TYPE_DICTIONARY: return U.failure("R5_3_LEAF_T1_COMPILE_REQUIRED")
	var d: Dictionary = compiled.details
	var binding := _validate_t1_leaf_binding(graph, d)
	if not binding.success:
		return binding
	var physical := int(graph.components.size())
	var capsule := _capsule(node_id, 0, String(graph.graph_hash), d.reduction, {}, 0, physical, physical, int(d.artifact.build_generation), String(d.capsule.checksum))
	var node_hash := _node_hash(capsule, d.reduction)
	var node := {"schema":SCHEMA, "node_id":node_id, "level":0, "node_hash":node_hash, "capsule":capsule, "reduction":d.reduction.duplicate(true), "live":{"node_hash":node_hash,"build_generation":int(d.artifact.build_generation)}, "children":{}, "topology_revision":0, "topology_edges":[], "physical_source_components":physical, "compiled_input_components":physical, "build_generation":int(d.artifact.build_generation), "source_graph":graph.duplicate(true), "compiled_graph":graph.duplicate(true), "source_capsule_checksum":String(d.capsule.checksum), "compile_events":1, "child_rom_reads":0}
	var checked := validate_node(node); return U.success(node) if checked.success else checked

static func _child_rom_components(children: Dictionary, parent_level: int, nodes: Array, components: Array) -> Dictionary:
	var child_rom_reads := 0; var cid := components.size(); var keys: Array = children.keys(); keys.sort()
	for raw_key in keys:
		var key := String(raw_key); var child: Dictionary = children[key]
		var checked := validate_node(child); if not checked.success: return U.failure("R5_3_CHILD_NODE_INVALID", {"child":key,"cause":checked})
		if int(child.level) != parent_level - 1: return U.failure("R5_3_CHILD_LEVEL_MISMATCH", {"child":key,"parent_level":parent_level,"child_level":int(child.level)})
		var r: Dictionary = child.reduction
		if int(r.reduced_equation_count) != PORTS or r.boundary_port_ids.size() != PORTS: return U.failure("R5_3_CHILD_PORT_COUNT_UNSUPPORTED", {"child":key})
		if r.boundary_port_ids != BOUNDARY_PORT_IDS: return U.failure("R5_3_CHILD_PORT_CONTRACT_UNSUPPORTED", {"child":key,"ports":r.boundary_port_ids})
		if not bool(r.passivity_certified): return U.failure("R5_3_CHILD_ROM_PASSIVITY_UNCERTIFIED", {"child":key})
		for rhs in r.reduced_rhs:
			if not U.is_finite_number(rhs) or absf(float(rhs)) > ZERO_TOL: return U.failure("R5_3_CHILD_AFFINE_SOURCE_UNSUPPORTED", {"child":key})
		for i in range(PORTS):
			var row_sum := 0.0
			for j in range(PORTS): row_sum += float(r.schur_matrix[i][j])
			if float(r.schur_matrix[i][i]) < -ZERO_TOL or absf(row_sum) > ZERO_TOL:
				return U.failure("R5_3_CHILD_ROM_LAPLACIAN_MISMATCH", {"child":key,"row":i,"row_sum":row_sum})
		var prefix := "node/%s" % _slug(key)
		for p in range(PORTS): nodes.append("%s/p%02d" % [prefix,p])
		for i in range(PORTS):
			for j in range(i + 1, PORTS):
				child_rom_reads += 1; var a := float(r.schur_matrix[i][j]); var b := float(r.schur_matrix[j][i])
				if not is_finite(a) or not is_finite(b) or absf(a-b) > ZERO_TOL: return U.failure("R5_3_CHILD_ROM_NOT_SYMMETRIC", {"child":key})
				var g := -0.5*(a+b)
				if g < -ZERO_TOL: return U.failure("R5_3_CHILD_ROM_NOT_PASSIVE", {"child":key,"g":g})
				if g > ZERO_TOL:
					components.append({"component_id":"component/r53-%05d" % cid, "law_kind":Graph.LAW_KIND, "node_a":"%s/p%02d" % [prefix,i], "node_b":"%s/p%02d" % [prefix,j], "conductance":g, "material_tag":"material/derived-child-rom"}); cid += 1
	return U.success({"child_rom_reads":child_rom_reads})

static func _topology(children: Dictionary, topology_revision: int, nodes: Array, components: Array) -> Array:
	var edges: Array = []; var cid := components.size()
	for suffix in ["a","b","c","d"]: nodes.append("node/boundary-%s" % suffix)
	var keys: Array = children.keys(); keys.sort()
	for child_index in range(keys.size()):
		var key := String(keys[child_index]); var prefix := "node/%s" % _slug(key)
		for p in range(PORTS):
			var boundary := "node/boundary-%s" % ["a","b","c","d"][p]; var child_node := "%s/p%02d" % [prefix,p]
			var g := 1.2 + 0.11*float(p) + 0.07*float(child_index) + 0.013*float(topology_revision)
			components.append({"component_id":"component/r53-%05d" % cid, "law_kind":Graph.LAW_KIND, "node_a":boundary, "node_b":child_node, "conductance":g, "material_tag":"material/hierarchy-connector"}); cid += 1
			edges.append({"a":boundary,"b_child":key,"b_port":p,"conductance":g})
	for child_index in range(keys.size()-1):
		var akey := String(keys[child_index]); var bkey := String(keys[child_index+1])
		for p in range(PORTS):
			var an := "node/%s/p%02d" % [_slug(akey),p]; var bn := "node/%s/p%02d" % [_slug(bkey),p]
			var g := 0.55 + 0.09*float(p) + 0.05*float(child_index) + 0.007*float(topology_revision)
			components.append({"component_id":"component/r53-%05d" % cid, "law_kind":Graph.LAW_KIND, "node_a":an, "node_b":bn, "conductance":g, "material_tag":"material/hierarchy-connector"}); cid += 1
			edges.append({"a_child":akey,"a_port":p,"b_child":bkey,"b_port":p,"conductance":g})
	return edges

static func compose(node_id: String, level: int, children: Dictionary, topology_revision: int = 0, build_generation: int = 1) -> Dictionary:
	if level < 1 or level > 3 or children.is_empty(): return U.failure("R5_3_PARENT_SHAPE_INVALID")
	var nodes: Array=[]; var components: Array=[]; var child_components := _child_rom_components(children,level,nodes,components)
	if not child_components.success: return child_components
	var edges := _topology(children,topology_revision,nodes,components)
	var ports: Array=[]; for suffix in ["a","b","c","d"]: ports.append({"port_id":"port/electrical-%s" % suffix,"node_id":"node/boundary-%s" % suffix})
	var graph := Graph.create("graph/r5-3-%s" % _slug(node_id),nodes,ports,components); if graph.is_empty(): return U.failure("R5_3_PARENT_GRAPH_INVALID")
	var gc := GraphCompiler.compile(graph); if not gc.success: return gc
	var policy := {"pivot_relative_tolerance":1.0e-12,"symmetry_tolerance":2.0e-10,"passivity_tolerance":2.0e-10,"require_symmetric":true,"require_passive_laplacian":true}
	var reduced := Reducer.reduce(gc.details.linear_system,policy)
	if not bool(reduced.get("success",false)) or String(reduced.get("status","")) != Reducer.REDUCED: return reduced
	var reduction: Dictionary = reduced.descriptor; var physical := edges.size(); var keys: Array=children.keys(); keys.sort()
	for key in keys: physical += int(children[key].physical_source_components)
	var capsule := _capsule(node_id,level,String(graph.graph_hash),reduction,children,topology_revision,physical,components.size(),build_generation,U.canonical_hash(_child_hashes(children)))
	var node_hash := _node_hash(capsule,reduction)
	var node := {"schema":SCHEMA,"node_id":node_id,"level":level,"node_hash":node_hash,"capsule":capsule,"reduction":reduction.duplicate(true),"live":{"node_hash":node_hash,"build_generation":build_generation},"children":children.duplicate(true),"topology_revision":topology_revision,"topology_edges":edges.duplicate(true),"physical_source_components":physical,"compiled_input_components":components.size(),"build_generation":build_generation,"source_graph":{},"compiled_graph":graph.duplicate(true),"source_capsule_checksum":"","compile_events":1,"child_rom_reads":int(child_components.details.child_rom_reads)}
	var checked := validate_node(node); return U.success(node) if checked.success else checked

static func manifest(root: Dictionary, path: String="root", out: Dictionary={}) -> Dictionary:
	out[path]={"node_hash":String(root.get("node_hash","")),"capsule_checksum":String(root.get("capsule",{}).get("checksum","")),"level":int(root.get("level",-1))}
	var children: Dictionary=root.get("children",{}); var keys: Array=children.keys(); keys.sort()
	for key in keys: manifest(children[key],path+"/"+String(key),out)
	return out

static func changed_paths(old_root: Dictionary,new_root: Dictionary) -> Array:
	var a:=manifest(old_root); var b:=manifest(new_root); var keys:Array=a.keys(); keys.sort(); var bkeys:Array=b.keys(); bkeys.sort(); var changed:Array=[]
	if keys != bkeys: return ["<TOPOLOGY_SHAPE_CHANGED>"]
	for path in keys:
		if a[path].node_hash != b[path].node_hash: changed.append(String(path))
	return changed

static func rebuild_path(root: Dictionary,slots: Array,replacement: Dictionary) -> Dictionary:
	if slots.is_empty(): return U.success({"root":replacement.duplicate(true),"compile_events":0,"child_rom_reads":0})
	var slot:=String(slots[0]); var children:Dictionary=root.get("children",{}); if not children.has(slot): return U.failure("R5_3_REBUILD_PATH_UNKNOWN",{"slot":slot})
	var child_result:=rebuild_path(children[slot],slots.slice(1),replacement); if not child_result.success: return child_result
	var next_children:=children.duplicate(true); next_children[slot]=child_result.details.root
	var rebuilt:=compose(String(root.node_id),int(root.level),next_children,int(root.topology_revision),int(root.build_generation)+1); if not rebuilt.success: return rebuilt
	return U.success({"root":rebuilt.details,"compile_events":int(child_result.details.compile_events)+1,"child_rom_reads":int(child_result.details.child_rom_reads)+int(rebuilt.details.child_rom_reads)})
