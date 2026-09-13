extends Control
var snapshot: Dictionary = {}

func set_phenotype(value: Dictionary) -> void:
	snapshot = value.duplicate(true)
	queue_redraw()

func _draw() -> void:
	if snapshot.is_empty(): return
	var modules: Array = snapshot.get("representation", {}).get("modules", [])
	var center := Vector2(size.x * 0.5, size.y * 0.85)
	for module in modules:
		var a := center + Vector2(float(module.start_mm[0]) * 0.28, -float(module.start_mm[1]) * 0.28)
		var b := center + Vector2(float(module.end_mm[0]) * 0.28, -float(module.end_mm[1]) * 0.28)
		draw_line(a, b, Color.WHITE, maxf(1.0, float(module.radius_mm) * 0.12))
		if module.role == "collector": draw_circle(b, maxf(2.0, sqrt(float(module.area_mm2)) * 0.03), Color(0.3, 0.9, 0.4, 0.8))
		if module.role == "absorber": draw_circle(b, maxf(2.0, float(module.reach_mm) * 0.04), Color(0.3, 0.6, 1.0, 0.25), false, 1.0)
