# EcologyWorkbench MorphotypeClassifier v1 (P9, ECO ARCH2 A10.5 / ECO-POLYGON-1).
# Role: DERIVED analytics over a MorphologyDescriptor (§20 emergent
#   morphotypes): classify(descriptor) -> one of bilateral_like /
#   radial_like / branched_like / segmented_like / cluster_NN using purely
#   GEOMETRIC metrics (degree distribution, mirror symmetry, branching,
#   radial balance). No species labels, no curated forms: the class names
#   describe geometry only and are analytics, NOT a reproduction/genome
#   input (classification never feeds back into canonical state).
# Layer: 3 (READ-ONLY PROJECTION / analytics).
#   Reads ONLY the descriptor; classify() is a pure function: identical
#   descriptor => identical classification_digest, input never mutated.
class_name EcoWorkbenchMorphotypeClassifierV1
extends RefCounted

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")

const SCHEMA := "dws.ecology.workbench.morphotype-classifier.v1"
const MORPHOTYPES := ["bilateral_like", "radial_like", "branched_like", "segmented_like"]
# Fallback family: "cluster_NN" where NN = module count (see classify()).

## Classify one descriptor. Pure, deterministic, read-only.
## Returns {"schema", "entity_id", "morphotype", "metrics", "classification_digest"}.
static func classify(descriptor: Dictionary) -> Dictionary:
	if not descriptor is Dictionary or descriptor.is_empty() or not descriptor.has("modules") or descriptor.modules.is_empty():
		return {}
	var modules: Array = descriptor.modules
	var n := modules.size()
	# --- degree distribution (children counts over parent links) -----------
	var children := {}
	var roots := 0
	for module in modules:
		children[String(module.id)] = 0
	for module in modules:
		var parent := String(module.get("parent", ""))
		if parent.is_empty():
			roots += 1
		elif children.has(parent):
			children[parent] = int(children[parent]) + 1
	var degrees: Array = []
	for id in children.keys():
		degrees.append(int(children[id]))
	var max_degree := 0
	var degree_sum := 0
	var branching := 0
	var chain := 0
	var leaves := 0
	for degree in degrees:
		max_degree = maxi(max_degree, degree)
		degree_sum += degree
		if degree >= 3:
			branching += 1
		if degree <= 1:
			chain += 1
		if degree == 0:
			leaves += 1
	var mean_degree := float(degree_sum) / float(n)
	var branch_fraction := float(branching) / float(n)
	var chain_fraction := float(chain) / float(n)

	# --- centroid + radial balance ------------------------------------------
	var centroid := Vector3.ZERO
	for module in modules:
		var p: Array = module.position_mm
		centroid += Vector3(float(p[0]), float(p[1]), float(p[2]))
	centroid /= float(n)
	var distances: Array = []
	var mean_distance := 0.0
	for module in modules:
		var p: Array = module.position_mm
		var d := Vector3(float(p[0]), float(p[1]), float(p[2])).distance_to(centroid)
		distances.append(d)
		mean_distance += d
	mean_distance /= float(n)
	var variance := 0.0
	for d in distances:
		variance += (d - mean_distance) * (d - mean_distance)
	variance /= float(n)
	var radial_balance := 1.0
	if mean_distance > 0.0001:
		radial_balance = clampf(1.0 - sqrt(variance) / mean_distance, 0.0, 1.0)

	# --- mirror symmetry (bilateral): each module has a partner mirrored ---
	# across the vertical plane through the centroid (x mirrored, y/z kept).
	var tolerance := _symmetry_tolerance(modules)
	var symmetric := 0
	for module in modules:
		var p: Array = module.position_mm
		var mirrored := Vector3(2.0 * centroid.x - float(p[0]), float(p[1]), float(p[2]))
		for other in modules:
			if other == module:
				continue
			var q: Array = other.position_mm
			if mirrored.distance_to(Vector3(float(q[0]), float(q[1]), float(q[2]))) <= tolerance:
				symmetric += 1
				break
	var symmetry_fraction := float(symmetric) / float(n)

	# --- deterministic decision tree (documented thresholds) ----------------
	var morphotype := ""
	if n <= 1:
		morphotype = "cluster_1"
	elif branch_fraction >= 0.2 and max_degree >= 3:
		morphotype = "branched_like"
	elif max_degree <= 2 and chain_fraction >= 0.7 and roots == 1:
		morphotype = "segmented_like"
	elif symmetry_fraction >= 0.75 and n >= 3:
		morphotype = "bilateral_like"
	elif radial_balance >= 0.75 and max_degree >= 3:
		morphotype = "radial_like"
	else:
		# Emergent fallback: an unclassifiable-yet-real body form is reported
		# as a cluster of its own size (cluster_NN, NN = module count).
		morphotype = "cluster_%d" % n
	# Integer-permille encodings (canonical digest is integer-only).
	var metrics := {
		"module_count": n,
		"max_degree": max_degree,
		"mean_degree_permille": roundi(mean_degree * 1000.0),
		"branch_fraction_permille": roundi(branch_fraction * 1000.0),
		"chain_fraction_permille": roundi(chain_fraction * 1000.0),
		"leaf_count": leaves,
		"symmetry_fraction_permille": roundi(symmetry_fraction * 1000.0),
		"radial_balance_permille": roundi(radial_balance * 1000.0),
		"centroid_mm": [roundi(centroid.x), roundi(centroid.y), roundi(centroid.z)],
	}
	var result := {
		"schema": SCHEMA,
		"entity_id": String(descriptor.get("entity_id", "")),
		"morphotype": morphotype,
		"is_cluster_fallback": morphotype.begins_with("cluster_"),
		"metrics": metrics,
	}
	result["classification_digest"] = C.digest(result)
	return result

## Aggregate analytics over many classifications (observatory): morphotype
## histogram + Shannon entropy over the morphotype distribution. Pure.
static func diversity(classifications: Array) -> Dictionary:
	var histogram := {}
	for classification in classifications:
		if classification is Dictionary and classification.has("morphotype"):
			var key := String(classification.morphotype)
			if key.begins_with("cluster_"):
				key = "cluster_*"
			histogram[key] = int(histogram.get(key, 0)) + 1
	var total := 0
	for key in histogram.keys():
		total += int(histogram[key])
	var shannon := 0.0
	if total > 0:
		for key in histogram.keys():
			var p := float(histogram[key]) / float(total)
			if p > 0.0:
				shannon -= p * log(p)
	return {
		"schema": SCHEMA,
		"count": classifications.size(),
		"unique_morphotypes": histogram.size(),
		"histogram": histogram,
		"shannon_entropy": shannon,
	}

## Symmetry matching tolerance: max module bounding size / 2 (module bodies
## are extended primitives, not points), floored at 1 mm.
static func _symmetry_tolerance(modules: Array) -> float:
	var tolerance := 1.0
	for module in modules:
		var size: Array = module.get("size_mm", [0, 0, 0])
		tolerance = maxf(tolerance, float(maxi(maxi(int(size[0]), int(size[1])), int(size[2]))) * 0.5)
	return tolerance
