extends Control
## Isometric projection of actual phenotype modules. All sites use one physical scale.
var site: Dictionary = {}
var selected_id := "study"
const PX_PER_MM := 2.4
const ROLE_COLORS := {"collector": Color("7be0a2"), "absorber": Color("70bce0"),
	"reproductive": Color("f4ca74"), "attachment": Color("a8b5c6"), "support": Color("c8d6cf")}

func present(value: Dictionary, individual: String) -> void:
	site = value.duplicate(true)
	selected_id = individual
	queue_redraw()

func point(coords: Array) -> Vector2:
	return Vector2(size.x * 0.52, size.y * 0.56) + Vector2(float(coords[0]) + float(coords[2]) * 0.45, -float(coords[1]) + float(coords[2]) * 0.22) * PX_PER_MM

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("111e2a"))
	var ground := size.y * 0.56
	for x in range(0, int(size.x), 24): draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.2, 0.32, 0.40, 0.22))
	for y in range(0, int(size.y), 24): draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.2, 0.32, 0.40, 0.22))
	draw_line(Vector2(0, ground), Vector2(size.x, ground), Color("476774"), 2)
	if site.is_empty(): return
	for entry in site.entries:
		if entry.id != selected_id: continue
		for module in entry.phenotype.representation.modules:
			var a := point(module.start_mm)
			var b := point(module.end_mm)
			var color: Color = ROLE_COLORS.get(module.role, Color("c8d6cf"))
			if not entry.alive: color = Color("7d8490")
			if module.id == "m000000": draw_circle(a, 4, Color("dee8f0")); continue
			draw_line(a, b, color, maxf(1, float(module.radius_mm) * 2 * PX_PER_MM), true)
			if module.role == "collector":
				# Disc is an explicitly labelled area proxy, not an invented leaf mesh.
				var radius := sqrt(float(module.area_mm2) / PI) * PX_PER_MM
				draw_circle(b, radius, Color(color, 0.15))
				draw_circle(b, radius, color, false, 1.5, true)
			if module.role == "absorber": draw_circle(b, float(module.reach_mm) * PX_PER_MM, Color(color, 0.45), false, 1.5, true)
			if module.role == "reproductive": draw_circle(b, 5, color)
		break
	draw_line(Vector2(16, size.y - 20), Vector2(16 + 20 * PX_PER_MM, size.y - 20), Color("cad6df"), 2)
	draw_string(ThemeDB.fallback_font, Vector2(16, size.y - 28), "20 mm | X/Y/Z projection", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("cad6df"))
