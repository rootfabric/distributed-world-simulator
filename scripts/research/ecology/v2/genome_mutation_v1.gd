extends RefCounted
## Typed edits of the inherited program only. Never mutates a live organism or a parent input.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const OPERATORS := ["small", "medium", "regulatory", "duplicate", "activate", "delete", "rewire", "insert", "module_parameter", "development_parameter", "none"]

static func draw(seed: int, key: String, count: int) -> int:
	return ("evo-arch2|%d|%s" % [seed, key]).sha256_text().substr(0, 12).hex_to_int() % maxi(1, count)

static func mutate(parent: Dictionary, seed: int, operator: String = "small") -> Dictionary:
	if not G.validate(parent).is_empty() or not C.integer(seed, 0, C.MAX_INT) or not operator in OPERATORS:
		return _rejected(operator, "INVALID_INPUT")
	var g := parent.duplicate(true)
	g.program = P.normalized(g.program)
	var rules: Array = g.program.rules
	var detail := {}
	match operator:
		"small", "medium":
			var names: Array = G.BOUNDS.keys()
			names.sort()
			var name: String = names[draw(seed, "gene", names.size())]
			var step := 1 + draw(seed, "step", 30 if operator == "small" else 250)
			var direction := -1 if draw(seed, "sign", 2) == 0 else 1
			var candidate: int = g.genes[name] + direction * step
			# Reflection is the declared boundary mutation, not validation repair.
			if candidate < G.BOUNDS[name][0] or candidate > G.BOUNDS[name][1]:
				candidate = g.genes[name] - direction * step
			g.genes[name] = candidate
			detail = {"gene": name, "old": parent.genes[name], "new": candidate}
		"module_parameter":
			var candidates: Array = []
			for r in rules:
				for a in r.actions:
					if a.op in ["extend", "differentiate", "attach"]:
						candidates.append(a)
			if candidates.is_empty():
				return _rejected(operator, "NO_MODULE_ACTION")
			var a: Dictionary = candidates[draw(seed, "module", candidates.size())]
			var axis := draw(seed, "axis", 3)
			var delta := 1 + draw(seed, "module-step", 10)
			var direction := -1 if draw(seed, "module-sign", 2) == 0 else 1
			var proposed: int = a.delta_mm[axis] + direction * delta
			if proposed < -2000 or proposed > 2000: proposed = a.delta_mm[axis] - direction * delta
			a.delta_mm[axis] = proposed
			detail = {"axis": axis, "delta_mm": a.delta_mm.duplicate()}
		"development_parameter":
			var field := "max_age" if draw(seed,"development-field",2) == 0 else "max_depth"
			var low := 1 if field == "max_age" else 0
			var high := 64 if field == "max_age" else 12
			var sign := -1 if draw(seed,"development-sign",2) == 0 else 1
			var proposed: int = g.program[field] + sign
			if proposed < low or proposed > high: proposed = g.program[field] - sign
			g.program[field] = proposed
			detail = {"field": field, "value": proposed}
		"regulatory":
			var r: Dictionary = rules[draw(seed, "rule", rules.size())]
			var channel: String = ["light", "water", "temperature", "competition", "mechanical"][draw(seed, "channel", 5)]
			r.guard = {"channel": channel, "min": draw(seed, "threshold", 501), "max": 1000}
			detail = {"rule": r.id, "guard": r.guard.duplicate()}
		"duplicate":
			if rules.size() >= 64:
				return _rejected(operator, "RULE_CAPACITY")
			var entry := _rule(rules, g.program.entry)
			if entry.actions.size() >= 8:
				return _rejected(operator, "ACTION_CAPACITY")
			var source: Dictionary = rules[draw(seed, "duplicate", rules.size())]
			var id := "dup_" + G.biological_hash(parent).substr(0, 10) + "_%d" % seed
			if not _rule(rules, id).is_empty():
				return _rejected(operator, "ID_COLLISION")
			var clone := source.duplicate(true)
			clone.id = id
			if clone.next == source.id:
				clone.next = id
			for a in clone.actions:
				if a.op == "branch" and a.target == source.id:
					a.target = id
			var edge := P.action("branch", "support", [0, 0, 0], 0, 0, 0, id)
			edge.enabled = false
			entry.actions.push_front(edge)
			rules.append(clone)
			detail = {"source": source.id, "new_rule": id, "activation": "DISABLED_NEUTRAL_MOTIF"}
		"activate":
			var actions: Array = []
			for r in rules:
				for a in r.actions:
					if not a.enabled:
						actions.append(a)
			if actions.is_empty():
				return _rejected(operator, "NO_DISABLED_ACTION")
			actions[draw(seed, "activate", actions.size())].enabled = true
			detail = {"activation": "EXPLICIT"}
		"delete":
			var ids: Array = []
			for r in rules:
				if r.id != g.program.entry:
					ids.append(r.id)
			if ids.is_empty():
				return _rejected(operator, "NO_REMOVABLE_RULE")
			return delete_rule(parent, ids[draw(seed, "delete", ids.size())], seed)
		"rewire":
			var edges: Array = []
			for r in rules:
				for a in r.actions:
					if a.op == "branch":
						edges.append(a)
			if edges.is_empty() or rules.size() < 2:
				return _rejected(operator, "NO_REWIRE_TARGET")
			var edge: Dictionary = edges[draw(seed, "edge", edges.size())]
			var targets: Array = []
			for r in rules:
				if r.id != edge.target:
					targets.append(r.id)
			detail = {"old_target": edge.target, "new_target": targets[draw(seed, "target", targets.size())]}
			edge.target = detail.new_target
		"insert":
			var candidates: Array = []
			for r in rules:
				if r.actions.size() < 8:
					candidates.append(r)
			if candidates.is_empty():
				return _rejected(operator, "ACTION_CAPACITY")
			var r: Dictionary = candidates[draw(seed, "insert-rule", candidates.size())]
			var a := P.action("extend", "support", [draw(seed, "x", 161)-80, draw(seed, "y", 161)-80, draw(seed, "z", 161)-80], 2)
			r.actions.push_front(a)
			detail = {"rule": r.id, "action": a.duplicate(true)}
		"none":
			detail = {"neutral_control": true}
	return _accepted(parent, g, seed, operator, detail)

static func delete_rule(parent: Dictionary, id: String, seed: int = 0) -> Dictionary:
	if not G.validate(parent).is_empty() or not C.integer(seed, 0, C.MAX_INT) or id == parent.program.entry:
		return _rejected("delete", "PROTECTED_ENTRY")
	var g := parent.duplicate(true)
	var target := _rule(g.program.rules, id)
	if target.is_empty():
		return _rejected("delete", "UNKNOWN_RULE")
	var successor: String = target.next if target.next != id else ""
	g.program.rules.erase(target)
	for r in g.program.rules:
		if r.next == id:
			r.next = successor
		var retained: Array = []
		for a in r.actions:
			if not (a.op == "branch" and a.target == id):
				retained.append(a)
		r.actions = retained if not retained.is_empty() else [P.action("retire")]
	return _accepted(parent, g, seed, "delete", {"removed_rule": id, "dependent_edges": "REMOVE_BRANCHES_BYPASS_NEXT_OR_TERMINATE"})

static func crossover(parent: Dictionary, donor: Dictionary, seed: int = 0) -> Dictionary:
	if not G.validate(parent).is_empty() or not G.validate(donor).is_empty() or not C.integer(seed, 0, C.MAX_INT):
		return _rejected("crossover", "INCOMPATIBLE_SCHEMA")
	var g := parent.duplicate(true)
	var entry := _rule(g.program.rules, g.program.entry)
	if entry.actions.size() >= 8 or g.program.rules.size() + donor.program.rules.size() > 64:
		return _rejected("crossover", "SPLICE_CAPACITY")
	donor = donor.duplicate(true)
	donor.program = P.normalized(donor.program)
	var prefix := "x" + str(seed) + "_"
	var mapping := {}
	for i in donor.program.rules.size():
		var id := prefix + str(i)
		if not _rule(g.program.rules, id).is_empty():
			return _rejected("crossover", "ID_COLLISION")
		mapping[donor.program.rules[i].id] = id
	for r in donor.program.rules:
		var clone: Dictionary = r.duplicate(true)
		clone.id = mapping[r.id]
		clone.next = "" if r.next.is_empty() else mapping[r.next]
		for a in clone.actions:
			if a.op == "branch":
				a.target = mapping[a.target]
		g.program.rules.append(clone)
	entry.actions.push_front(P.action("branch", "support", [0, 0, 0], 0, 0, 0, mapping[donor.program.entry]))
	return _accepted(parent, g, seed, "crossover", {"donor_hash": G.biological_hash(donor), "mode": "TYPED_RESEARCH_MOTIF_SPLICE_NOT_SEXUAL_REPRODUCTION"})

static func _rule(rules: Array, id: String) -> Dictionary:
	for r in rules:
		if r.id == id:
			return r
	return {}

static func _accepted(parent: Dictionary, g: Dictionary, seed: int, operator: String, detail: Dictionary) -> Dictionary:
	var error := G.validate(g)
	if not error.is_empty():
		return _rejected(operator, error)
	g.program = P.normalized(g.program)
	var event := {"schema": "dws.ecology.mutation-event.v1", "operator": operator, "seed": str(seed), "parent_hash": G.biological_hash(parent), "child_hash": G.biological_hash(g), "detail": detail}
	return {"success": true, "genome": g, "event": event, "event_hash": C.digest(event)}

static func _rejected(operator: String, reason: String) -> Dictionary:
	return {"success": false, "operator": operator, "reason": reason}
