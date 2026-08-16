extends SceneTree

const VIS18_Bridge = preload("res://scripts/labs/ecology/eco_vis1_8a_turnover_bridge.gd")
const VIS18_VIS16 = preload("res://scripts/labs/ecology/eco_vis1_6_lineage_genome_bridge.gd")
const VIS18_MutationKernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const VIS18_Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const VIS18_LineageRecord = preload("res://scripts/research/ecology/plant_lineage_record_v1.gd")
const VIS18_EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const VIS18_RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")

var _assertions := 0
var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var snapshot_hash := "a".repeat(64)
	var baseline := VIS18_VIS16.create_population_baseline_genome("alpha")
	_expect(bool(VIS18_Genome.validate(baseline).get("success", false)), "alpha baseline genome is valid")
	var records: Array[Dictionary] = []
	for index in range(8):
		var lineage := VIS18_MutationKernel.create_ancestor(baseline, 1000 + index)
		_expect(bool(VIS18_LineageRecord.validate(lineage).get("success", false)), "founder lineage is valid")
		var angle := TAU * float(index) / 8.0
		var record := VIS18_Bridge.create_founder_record(
			"test/founder/%02d" % index,
			"A",
			"alpha",
			index,
			cos(angle) * 7.0,
			sin(angle) * 7.0,
			angle,
			baseline,
			lineage,
			3.6 / 8.0,
			0.64 + 0.035 * float(index)
		)
		_expect(not record.is_empty(), "founder record is created")
		records.append(record)

	var advanced := VIS18_Bridge.advance_population(records, 8, 3.6, 1, snapshot_hash, "A", "alpha", Vector2.ZERO)
	_expect(not advanced.is_empty(), "turnover transition is created")
	if advanced.is_empty():
		_finish()
		return
	_expect(String(advanced.get("mode", "")) == VIS18_Bridge.MODE, "turnover mode matches")
	_expect(not bool(advanced.get("canonical_population_truth", true)), "turnover is not canonical population truth")
	_expect(int(advanced.get("birth_count", 0)) > 0, "turnover produces recruitment")
	_expect(int(advanced.get("death_count", 0)) > 0, "turnover produces mortality")
	_expect(int(advanced.get("survivor_count", 0)) > 0, "turnover preserves survivors")
	_expect(int(advanced.get("target_count", 0)) == Array(advanced.get("records", [])).size(), "target count matches next generation")
	_expect(int(advanced.get("survivor_count", 0)) + int(advanced.get("birth_count", 0)) == int(advanced.get("target_count", 0)), "survivors plus births equals target")
	_expect(int(advanced.get("previous_count", 0)) - int(advanced.get("survivor_count", 0)) == int(advanced.get("death_count", 0)), "mortality arithmetic is exact")
	_expect(is_equal_approx(float(advanced.get("represented_biomass_kg", 0.0)), 3.6), "represented biomass is conserved")
	_expect(String(advanced.get("turnover_hash", "")).length() == 64, "turnover hash is present")

	var repeated := VIS18_Bridge.advance_population(records, 8, 3.6, 1, snapshot_hash, "A", "alpha", Vector2.ZERO)
	_expect(String(repeated.get("turnover_hash", "")) == String(advanced.get("turnover_hash", "")), "turnover transition is deterministic")

	var biomass_sum := 0.0
	var found_birth := false
	var born_record := {}
	for record_variant in Array(advanced.get("records", [])):
		var record: Dictionary = record_variant
		biomass_sum += float(record.get("represented_biomass_kg", 0.0))
		var position := Vector2(float(record.get("world_x", 0.0)), float(record.get("world_z", 0.0)))
		_expect(position.length() <= VIS18_Bridge.FIELD_RADIUS_M + 0.000001, "representative stays inside patch field radius")
		_expect(bool(VIS18_Genome.validate(Dictionary(record.get("genome", {}))).get("success", false)), "turnover genome remains valid")
		_expect(bool(VIS18_LineageRecord.validate(Dictionary(record.get("lineage", {}))).get("success", false)), "turnover lineage remains valid")
		if int(record.get("birth_generation", 0)) == 1:
			found_birth = true
			born_record = record
			_expect(not String(record.get("parent_stable_id", "")).is_empty(), "recruit records its parent")
	_expect(is_equal_approx(biomass_sum, 3.6), "per-record represented biomass sums to source")
	_expect(found_birth, "at least one recruit is present")

	var environment := VIS18_EnvironmentSample.create(0.0, 0.0, 18.0, 0.72, 0.65, 0.58, 0.18, 73191, "vis1-8a-bridge-test")
	var profile := VIS18_RendererProfile.create("BRANCH_LEAF_INSTANCED")
	var realization := VIS18_Bridge.realize_individual(born_record, environment, profile, snapshot_hash, 1)
	_expect(not realization.is_empty(), "recruited individual realizes through development and PH5")
	if not realization.is_empty():
		_expect(String(realization.get("geometry_hash", "")).length() == 64, "recruit has PH5 geometry hash")
		_expect(String(realization.get("phenotype_hash", "")).length() == 64, "recruit has phenotype hash")
		_expect(float(realization.get("current_fitness", -1.0)) >= 0.0, "recruit has local fitness")
		var materialization: Dictionary = realization.get("materialization", {})
		_expect(materialization.get("branch_mesh") is ArrayMesh, "recruit has branch mesh")
		_expect(materialization.get("foliage_multimesh") is MultiMesh, "recruit has foliage multimesh")

	print("ECO.VIS1.8A turnover bridge: PASS (%d assertions)" % _assertions if _failures == 0 else "ECO.VIS1.8A turnover bridge: FAIL (%d assertions, %d failures)" % [_assertions, _failures])
	_finish()

func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("ECO.VIS1.8A bridge assertion failed: %s" % message)

func _finish() -> void:
	quit(0 if _failures == 0 else 1)
