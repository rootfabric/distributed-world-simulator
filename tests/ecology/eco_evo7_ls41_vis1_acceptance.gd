extends SceneTree

const LabScene = preload("res://scenes/labs/ecology/eco_evo7_ls41_multi_species_lab.tscn")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var lab = LabScene.instantiate()
    root.add_child(lab)
    await process_frame
    await process_frame

    _check(lab.has_method("get_visual_contract"), "VIS1 lab exposes visual contract")
    var contract: Dictionary = lab.get_visual_contract()
    _check(String(contract.get("revision", "")) == "ECO.EVO7-LS4-VIS1-R1", "VIS1 revision exact")
    _check(bool(contract.get("derived_only", false)), "VIS1 is explicitly derived-only")
    _check(not bool(contract.get("ecology_write", true)), "VIS1 has no ecology write authority")
    _check(not bool(contract.get("world_write", true)), "VIS1 has no WORLD write authority")
    _check(bool(contract.get("species_distribution_overlay", false)), "VIS1 exposes species distribution overlay")
    _check(bool(contract.get("cell_species_composition", false)), "VIS1 exposes cell composition")
    _check(lab.ecology != null, "VIS1 owns a live LS4.1 observer source")
    _check(lab.projection.size() == 1024, "VIS1 renders full 32x32 species projection")

    var before: Dictionary = lab.ecology.get_snapshot()
    _check(not before.is_empty(), "VIS1 source snapshot exists")
    var state_hash := String(before.get("state_hash", ""))
    var projection_a = lab.ecology.get_species_projection()
    var projection_b = lab.ecology.get_species_projection()
    _check(projection_a == projection_b, "VIS1 source projection is stable")
    _check(String(lab.ecology.get_snapshot().get("state_hash", "")) == state_hash, "VIS1 observation cannot mutate ecology state")

    lab.queue_free()
    if failures.is_empty():
        print("ECO.EVO7 LS4-VIS1: PASS (%d assertions)" % assertions)
        quit(0)
    else:
        for failure in failures:
            push_error("LS4-VIS1 FAIL: %s" % failure)
        print("ECO.EVO7 LS4-VIS1: FAIL (%d/%d failed)" % [failures.size(), assertions])
        quit(1)

func _check(condition: bool, label: String) -> void:
    assertions += 1
    if not condition:
        failures.append(label)
