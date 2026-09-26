extends SceneTree

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Session = preload("res://scripts/ecology/habitat/persistent_habitat_session_v1.gd")
const Preset = preload("res://scripts/ecology/habitat/habitat_preset_v1.gd")
const Patch = preload("res://scripts/ecology/workbench/environment_patch_v1.gd")
const Adapter = preload("res://scripts/ecology/workbench/polygon_world_adapter_v1.gd")
const Region = preload("res://scripts/network/contracts/authority_region_descriptor.gd")
const Catalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const Batch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("A11_WORLD_FAIL " + message)

func region(lifecycle: String = "ACTIVE") -> Dictionary:
	return Region.create("region/a11", "u", "i", "surface", "octree", 7,
		{"kind": "GLOBAL_SPACE", "partition_prefix": "", "chunk_ids": []}, "node/a", 1, lifecycle, 10)

func world_manifest() -> Dictionary:
	var value := Preset.create(777, 64)
	value.mode = "WORLD_COMPAT"
	value.experiment_id = "eco/a11/world/v1"
	value.environment.spatial.width = 1
	value.environment.zones = [{"id": "wet", "water_mg": 0, "light": 700,
		"temperature": 500, "nutrient_mg": 0, "organic_mg": 0}]
	value.placement.entries = [{"founder_ref": "founder/a", "zone_id": "wet", "position_mm": [500, 0, 500]}]
	return value

func adapter(manifest: Dictionary) -> Object:
	var result := Adapter.new()
	var configured: Dictionary = result.configure(manifest, {"region": region(),
		"entity_id": "organism/a11", "owner_id": "node/a", "catalog": Catalog.default_catalog(),
		"map_id": "eco-map/a11", "mapping_entries": [{"material_id": "matter/water-ice", "resource": "water_mg"}]})
	check(configured.success, "real A10 world adapter configured")
	return result

func water_batch() -> Dictionary:
	return Batch.create({"batch_id": "batch/a11-water", "container_id": "container/a11",
		"source_body_id": "body/moon", "source_operation_id": "operation/a11",
		"total_mass_kg": 0.5, "bulk_volume_m3": 0.000001,
		"composition": Composition.create([{"material_id": "matter/water-ice", "mass_fraction": 1.0}]),
		"temperature_k": 273.15})

func _run() -> void:
	var manifest := world_manifest()
	var source_adapter: Object = adapter(manifest)
	var session := Session.new()
	check(not session.start(manifest).success, "WORLD_COMPAT needs explicit authority")
	check(session.start(manifest, {}, source_adapter).success, "world session starts through shared controller")
	var batch := water_batch()
	check(not batch.is_empty(), "production Matter batch created")
	check(source_adapter.add_batch(batch, String(batch.checksum)).success, "externally anchored Matter admitted")
	check(source_adapter.apply_environment(session.controller).success, "admitted delta reaches canonical field")
	check(int(session.controller.debug_state().field.cells[0].stocks.water_mg) == 500000, "one total admitted exactly once")
	var before: String = session.controller.get_snapshot().canonical_state_hash
	var before_manifest: Dictionary = session.controller.get_manifest()
	var before_cursor: Dictionary = source_adapter.cursor()
	var patched: Dictionary = session.controller.apply_field_patch(Patch.patch("wet", "water_mg", 100))
	check(not patched.success, "direct live stock patch cannot bypass Matter")
	check(String(patched.error).begins_with("CONTROLLER_FIELD_PATCH_WORLD:"), "failure occurs at world manifest admission")
	check(session.controller.get_snapshot().canonical_state_hash == before, "rejected resource patch preserves runtime")
	check(session.controller.get_manifest() == before_manifest, "rejected resource patch preserves manifest")
	check(source_adapter.cursor() == before_cursor, "rejected resource patch preserves world cursor")
	# Signals are declared by the configured authority manifest too: no implicit
	# reconfiguration via controller patches, even for a non-resource field.
	check(not session.controller.apply_field_patch(Patch.patch("wet", "light", 100)).success, "changed world signal requires explicit authority reconfiguration")
	check(source_adapter.cursor() == before_cursor, "signal rejection does not advance cursor")
	check(source_adapter.set_region(region("WARM")).success, "real region enters WARM")
	var warm_before: String = session.controller.get_snapshot().canonical_state_hash
	var warm_patch: Dictionary = session.controller.apply_field_patch(Patch.patch("wet", "water_mg", 0))
	check(not warm_patch.success, "even unchanged world patch cannot execute under WARM authority")
	check(session.controller.get_snapshot().canonical_state_hash == warm_before, "WARM patch leaves canonical runtime untouched")
	check(source_adapter.cursor() == before_cursor, "WARM patch leaves cursor untouched")
	check(source_adapter.set_region(region()).success, "ACTIVE restored by explicit host update")
	check(session.controller.run(4).success, "world session canonical ticks")

	var exported: Dictionary = session.export_bundle()
	check(exported.success, "world physical envelope exports through habitat transport")
	var original: Object = session.controller
	check(not session.restore_bundle(exported.text, exported.sha256, source_adapter).success, "reuse of live world adapter rejected")
	check(session.controller == original, "rejected adapter reuse leaves original live")
	var restored := Session.new()
	check(not restored.restore_bundle(exported.text, exported.sha256).success, "world restore needs fresh world context")
	var fresh_adapter: Object = adapter(manifest)
	var loaded: Dictionary = restored.restore_bundle(exported.text, exported.sha256, fresh_adapter)
	check(loaded.success, "world bundle restored into independently configured adapter")
	if loaded.success:
		check(restored.controller.get_snapshot().canonical_state_hash == session.controller.get_snapshot().canonical_state_hash, "world runtime exact across restart")
		check(fresh_adapter.export_state() == source_adapter.export_state(), "entire physical authority envelope preserved")
		check(int(fresh_adapter.observe_world().admitted_resources.water_mg) == 500000, "Matter admission total preserved")
		var restored_before: String = restored.controller.get_snapshot().canonical_state_hash
		check(fresh_adapter.add_batch(batch, String(batch.checksum)).success, "exact batch replay accepted idempotently after restart")
		check(fresh_adapter.apply_environment(restored.controller).success, "replayed batch application succeeds without minting")
		check(restored.controller.get_snapshot().canonical_state_hash == restored_before, "no second deposit after restart")
		check(session.controller.run(2).success and restored.controller.run(2).success, "both world continuations run")
		check(restored.controller.get_snapshot().canonical_state_hash == session.controller.get_snapshot().canonical_state_hash, "world continuation deterministic")
		check(fresh_adapter.export_state() == source_adapter.export_state(), "world cursors advance identically after resume")

	var lab := Session.new()
	check(lab.start(Preset.create()).success, "LAB still starts")
	check(lab.controller.apply_field_patch(Patch.patch("wet", "water_mg", 700000)).success, "LAB experimental resource edit retained")
	check(int(lab.controller.debug_state().field.cells[0].stocks.water_mg) == 700000, "LAB patch executes actual canonical delta")
	print("EVO_ARCH2_A11_WORLD checks=%d failed=%d" % [checks, failures.size()])
	print("EVO_ARCH2_A11_WORLD " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
