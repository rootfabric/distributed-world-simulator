extends RefCounted
## Pure bounded interpreter. Synthetic grants are not production resource authority.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const E = preload("res://scripts/research/ecology/v2/environment_fixture_v1.gd")
const S = preload("res://scripts/research/ecology/v2/organism_state_v1.gd")

static func begin_tick(source: Dictionary, genome: Dictionary, environment: Dictionary, grant: Dictionary = B.stock(), sequence: int = -1) -> Dictionary:
	var error := S.validate(source, genome)
	if not error.is_empty():
		return _fail(error)
	if not source.frame.is_empty():
		return _fail("TICK_ALREADY_OPEN")
	if not E.validate(environment).is_empty() or not B.valid_stock(grant):
		return _fail("TICK_INPUT")
	if source.tick >= 1000000 or sequence != source.grant_seq + 1:
		return _fail("GRANT_SEQUENCE")
	for name in B.RESOURCES:
		if source.received[name] > B.MAX_STOCK - grant[name]:
			return _fail("RESOURCE_OVERFLOW")
	var s := source.duplicate(true)
	for name in B.RESOURCES:
		s.received[name] += grant[name]
		s.reserves[name] += grant[name]
	s.grant_seq = sequence
	s.tips.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	var rule_map := {}
	for r in genome.program.rules: rule_map[r.id] = r
	# Fixed semantic scheduling: expiring/terminal growth points first, then branching.
	# This is independent of CPU slice size and permits ordinary bud retirement before allocation.
	var scheduled: Array = s.tips.duplicate()
	scheduled.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := _priority(a, rule_map[a.rule], s.tick, genome.program)
		var pb := _priority(b, rule_map[b.rule], s.tick, genome.program)
		return pa < pb if pa != pb else a.id < b.id)
	var queue: Array = []
	for tip in scheduled:
		if tip.birth_tick <= s.tick:
			queue.append(tip.id)
	var env := environment.duplicate(true)
	env.supports.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	s.frame = {"environment": env, "queue": queue, "cursor": 0, "events": []}
	return {"success": true, "state": s, "status": "RUNNING"}

static func advance(source: Dictionary, genome: Dictionary, operation_budget: int = 4096) -> Dictionary:
	var error := S.validate(source, genome)
	if not error.is_empty():
		return _fail(error)
	if source.frame.is_empty() or operation_budget < 1 or operation_budget > 4096:
		return _fail("SLICE_INPUT")
	var s := source.duplicate(true)
	var rules := {}
	for rule in genome.program.rules:
		rules[rule.id] = rule
	var operations := 0
	while s.frame.cursor < s.frame.queue.size() and operations < operation_budget:
		var index := _tip_index(s, s.frame.queue[s.frame.cursor])
		if index < 0:
			return _fail("MISSING_SCHEDULED_TIP")
		var tip: Dictionary = s.tips[index]
		var rule: Dictionary = rules[tip.rule]
		var outcome := ""
		operations += 1
		if s.tick - tip.birth_tick >= genome.program.max_age:
			outcome = "AGE_LIMIT"
			s.tips.remove_at(index)
			s.frame.cursor += 1
		elif tip.pc >= rule.actions.size():
			outcome = "RULE_COMPLETE"
			if rule.next.is_empty():
				s.tips.remove_at(index)
			else:
				tip.rule = rule.next
				tip.pc = 0
			s.frame.cursor += 1
		elif not _guard(rule.guard, s.frame.environment):
			outcome = "WAIT_ENVIRONMENT"
			s.frame.cursor += 1
		else:
			var a: Dictionary = rule.actions[tip.pc]
			if not a.enabled:
				outcome = "DISABLED"
			else:
				outcome = _execute(s, genome, tip, a)
			if outcome in ["MODULE_CAPACITY", "TIP_CAPACITY", "DIMENSION_CAPACITY", "COUNTER_CAPACITY"]:
				return {"success": true, "state": s, "status": "BUDGET_BLOCKED", "reason": outcome, "operations": operations}
			if outcome.begins_with("WAIT_"):
				s.frame.cursor += 1
			elif a.op == "retire" and a.enabled:
				s.tips.remove_at(index)
				s.frame.cursor += 1
			else:
				tip.pc += 1
		s.frame.events.append({"tip": tip.id, "rule": rule.id, "outcome": outcome})
	if s.frame.cursor == s.frame.queue.size():
		s.last_events = s.frame.events.duplicate(true)
		s.frame = {}
		s.tick += 1
		s.tips.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
		return {"success": true, "state": s, "status": "TICK_COMPLETE", "operations": operations}
	return {"success": true, "state": s, "status": "RUNNING", "operations": operations}

static func resize_capacity(source: Dictionary, genome: Dictionary, modules: int, tips: int) -> Dictionary:
	if not S.validate(source, genome).is_empty() or modules < source.modules.size() or modules > 256 or tips < maxi(1, source.tips.size()) or tips > 32:
		return _fail("INVALID_CAPACITY")
	var s := source.duplicate(true)
	s.limits = {"modules": modules, "tips": tips}
	return {"success": true, "state": s}

static func _execute(s: Dictionary, g: Dictionary, tip: Dictionary, a: Dictionary) -> String:
	if a.op == "retire":
		return "RETIRED"
	if a.op == "branch":
		if tip.depth >= g.program.max_depth:
			return "GENETIC_DEPTH_LIMIT"
		if s.tips.size() >= s.limits.tips:
			return "TIP_CAPACITY"
		if s.next_tip >= 1000000:
			return "COUNTER_CAPACITY"
		var bud_cost := B.stock()
		bud_cost.energy_mj = 1
		if not _pay(s, bud_cost):
			return "WAIT_RESOURCES"
		s.branch_energy_mj += 1
		s.tips.append({"id": "p%06d" % s.next_tip, "module": tip.module, "rule": a.target, "pc": 0, "depth": tip.depth + 1, "birth_tick": s.tick + 1})
		s.next_tip += 1
		return "BRANCHED"
	var parent_index := int(tip.module.substr(1))
	var parent: Dictionary = s.modules[parent_index]
	var module := parent.duplicate(true) if a.op == "allocate" else {"id": "m%06d" % s.modules.size(), "parent": parent.id, "role": a.role, "start_mm": parent.end_mm.duplicate(), "end_mm": parent.end_mm.duplicate(), "radius_mm": 0, "area_mm2": 0, "reach_mm": 0, "cost": B.stock()}
	if a.op == "allocate" and (parent.id == "m000000" or a.role != parent.role):
		return "WAIT_ALLOCATION_ROLE"
	if a.op != "allocate" and s.modules.size() >= s.limits.modules:
		return "MODULE_CAPACITY"
	for axis in 3:
		module.end_mm[axis] += a.delta_mm[axis] * g.genes.length_permille / 1000
	module.radius_mm += a.radius_mm * g.genes.radius_permille / 1000
	module.area_mm2 += a.area_mm2 * g.genes.collector_permille / 1000
	module.reach_mm += a.reach_mm * g.genes.absorber_permille / 1000
	if module.radius_mm < 1:
		module.radius_mm = 1
	if module.radius_mm > 1000 or module.area_mm2 > 4000000 or module.reach_mm > 10000 or not C.vector(module.end_mm, 10000000):
		return "DIMENSION_CAPACITY"
	if a.op == "attach" and not E.can_attach(s.frame.environment, a.target, module.end_mm, module.reach_mm):
		return "WAIT_ATTACHMENT"
	var new_cost := B.cost(module)
	var debit := new_cost.duplicate()
	if a.op == "allocate":
		for name in B.RESOURCES:
			debit[name] -= parent.cost[name]
	if not _pay(s, debit):
		return "WAIT_RESOURCES"
	module.cost = new_cost
	if a.op == "allocate":
		s.modules[parent_index] = module
	else:
		s.modules.append(module)
		tip.module = module.id
	if a.op == "attach":
		s.attachments.append({"module": module.id, "support_id": a.target, "environment_hash": C.digest(s.frame.environment)})
	return "ALLOCATED" if a.op == "allocate" else "MODULE_CREATED"

static func _pay(s: Dictionary, debit: Dictionary) -> bool:
	for name in B.RESOURCES:
		if debit[name] < 0 or debit[name] > s.reserves[name]:
			return false
	for name in B.RESOURCES:
		s.reserves[name] -= debit[name]
		s.spent[name] += debit[name]
	return true

static func _guard(guard: Dictionary, env: Dictionary) -> bool:
	if guard.channel == "always":
		return true
	var value: int = env.channels[guard.channel]
	return value >= guard.min and value <= guard.max

static func _priority(tip: Dictionary, rule: Dictionary, tick: int, program: Dictionary) -> int:
	if tick - tip.birth_tick >= program.max_age: return 0
	if tip.depth < program.max_depth:
		for a in rule.actions:
			if a.enabled and a.op == "branch": return 2
	return 1

static func _tip_index(s: Dictionary, id: String) -> int:
	for i in s.tips.size():
		if s.tips[i].id == id:
			return i
	return -1

static func _fail(error: String) -> Dictionary:
	return {"success": false, "error": error}
