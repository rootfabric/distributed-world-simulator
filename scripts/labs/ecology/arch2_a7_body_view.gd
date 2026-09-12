extends Control
## Fixed physical field of view; common scale across sites, never fit to a living phenotype.
var site: Dictionary = {}
var selected_id := "study"
var common_canvas_size := Vector2.ZERO
const WORLD_MM := Rect2(-100, -130, 200, 200)
const ROLE_COLORS := {"collector": Color("7be0a2"), "absorber": Color("70bce0"),
	"reproductive": Color("f4ca74"), "attachment": Color("a8b5c6"), "support": Color("c8d6cf")}

func present(value: Dictionary, individual: String, canvas_size: Vector2 = Vector2.ZERO) -> void:
	site = value.duplicate(true)
	selected_id = individual
	common_canvas_size = canvas_size
	queue_redraw()

func projection_scale() -> float:
	var canvas := common_canvas_size if common_canvas_size.x > 0 and common_canvas_size.y > 0 else size
	return maxf(0.1, minf((canvas.x - 32) / WORLD_MM.size.x, (canvas.y - 56) / WORLD_MM.size.y))

func map_projected(coords: Vector2) -> Vector2:
	var scale := projection_scale()
	return Vector2((size.x - WORLD_MM.size.x * scale) * 0.5, 16) + (coords - WORLD_MM.position) * scale

func point(coords: Array) -> Vector2:
	return map_projected(Vector2(float(coords[0]) + float(coords[2]) * 0.45, -float(coords[1]) + float(coords[2]) * 0.22))

func visual_bounds(entry: Dictionary) -> Rect2:
	var bounds := Rect2()
	var first := true
	var scale := projection_scale()
	for module in entry.phenotype.representation.modules:
		var radius := 4.0 if module.id == "m000000" else maxf(1.0, float(module.radius_mm) * scale)
		for coords in [module.start_mm, module.end_mm]:
			var circle := Rect2(point(coords) - Vector2.ONE * radius, Vector2.ONE * radius * 2)
			bounds = circle if first else bounds.merge(circle)
			first = false
		var proxy := 0.0
		if module.role == "collector": proxy = sqrt(float(module.area_mm2) / PI) * scale
		if module.role == "absorber": proxy = float(module.reach_mm) * scale
		if module.role == "reproductive": proxy = 5.0
		if proxy > 0:
			bounds = bounds.merge(Rect2(point(module.end_mm) - Vector2.ONE * proxy, Vector2.ONE * proxy * 2))
	return bounds

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("111e2a"))
	var scale := projection_scale()
	for x in range(int(WORLD_MM.position.x), int(WORLD_MM.end.x) + 1, 10):
		draw_line(map_projected(Vector2(x, WORLD_MM.position.y)), map_projected(Vector2(x, WORLD_MM.end.y)), Color(0.2, 0.32, 0.40, 0.22))
	for y in range(int(WORLD_MM.position.y), int(WORLD_MM.end.y) + 1, 10):
		draw_line(map_projected(Vector2(WORLD_MM.position.x, y)), map_projected(Vector2(WORLD_MM.end.x, y)), Color(0.2, 0.32, 0.40, 0.22))
	draw_line(map_projected(Vector2(WORLD_MM.position.x, 0)), map_projected(Vector2(WORLD_MM.end.x, 0)), Color("476774"), 2)
	if site.is_empty(): return
	for entry in site.entries:
		if entry.id != selected_id: continue
		for module in entry.phenotype.representation.modules:
			var a := point(module.start_mm)
			var b := point(module.end_mm)
			var color: Color = ROLE_COLORS.get(module.role, Color("c8d6cf"))
			if not entry.alive: color = Color("7d8490")
			if module.id == "m000000": draw_circle(a, 4, Color("dee8f0")); continue
			draw_line(a, b, color, maxf(1, float(module.radius_mm) * 2 * scale), true)
			if module.role == "collector":
				# Disc is a labelled area proxy, not an invented leaf mesh.
				var radius := sqrt(float(module.area_mm2) / PI) * scale
				draw_circle(b, radius, Color(color, 0.15))
				draw_circle(b, radius, color, false, 1.5, true)
			if module.role == "absorber": draw_circle(b, float(module.reach_mm) * scale, Color(color, 0.45), false, 1.5, true)
			if module.role == "reproductive": draw_circle(b, 5, color)
		break
	draw_line(Vector2(16, size.y - 20), Vector2(16 + 20 * scale, size.y - 20), Color("cad6df"), 2)
	draw_string(ThemeDB.fallback_font, Vector2(16, size.y - 28), "20 mm | X/Y/Z | FOV 200 mm", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("cad6df"))
