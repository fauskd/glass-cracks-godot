extends Node2D
## Glass Cracks - starter prototype (Godot 4).
##
## How it plays:
## - Click inside the glass to hit it. Your hit does NOT land exactly where you
##   click: it lands at a random spot inside the white circle (the "jitter").
## - Every hit becomes the centre of one glass piece. A piece is all the glass
##   that is closer to its hit than to any other hit (a Voronoi cell).
## - Goal: after all hits, every piece must be (nearly) the same size.
##
## The level numbers below are a FIRST GUESS. Tuning them through playtesting
## is your design work for the portfolio.

const LEVELS := [
	{"name": "First Crack",   "shape": "rect",      "hits": 2, "tolerance": 0.20, "jitter": 8.0},
	{"name": "Three Ways",    "shape": "rect",      "hits": 3, "tolerance": 0.20, "jitter": 12.0},
	{"name": "Sharp Corners", "shape": "triangle",  "hits": 3, "tolerance": 0.20, "jitter": 12.0},
	{"name": "Window Pane",   "shape": "rect",      "hits": 4, "tolerance": 0.15, "jitter": 15.0},
	{"name": "Honeycomb",     "shape": "hexagon",   "hits": 4, "tolerance": 0.15, "jitter": 18.0},
	{"name": "Slanted",       "shape": "trapezoid", "hits": 5, "tolerance": 0.15, "jitter": 20.0},
	{"name": "Six Shards",    "shape": "hexagon",   "hits": 6, "tolerance": 0.12, "jitter": 22.0},
	{"name": "Shatterpoint",  "shape": "rect",      "hits": 7, "tolerance": 0.10, "jitter": 25.0},
]

const CENTER := Vector2(400, 330)
const GLASS_COLOR := Color(0.55, 0.8, 0.95, 0.35)
const GOOD_COLOR := Color(0.4, 0.9, 0.5, 0.45)
const BAD_COLOR := Color(0.95, 0.4, 0.4, 0.45)

var level_index := 0
var seeds: Array = []        # where each hit actually landed
var pieces: Array = []       # one PackedVector2Array polygon per piece
var panel := PackedVector2Array()
var finished := false
var passed := false
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.08, 0.09, 0.12))
	rng.randomize()
	load_level(0)


func load_level(i: int) -> void:
	level_index = clampi(i, 0, LEVELS.size() - 1)
	panel = make_shape(LEVELS[level_index]["shape"])
	seeds.clear()
	pieces = []
	finished = false
	passed = false
	queue_redraw()


func make_shape(shape: String) -> PackedVector2Array:
	var w := 260.0
	var h := 170.0
	match shape:
		"triangle":
			return PackedVector2Array([CENTER + Vector2(0, -h - 20), CENTER + Vector2(w, h), CENTER + Vector2(-w, h)])
		"hexagon":
			var pts := PackedVector2Array()
			for k in 6:
				var a := TAU * k / 6.0
				pts.append(CENTER + Vector2(cos(a) * 230.0, sin(a) * 200.0))
			return pts
		"trapezoid":
			return PackedVector2Array([CENTER + Vector2(-150, -h), CENTER + Vector2(150, -h), CENTER + Vector2(w, h), CENTER + Vector2(-w, h)])
		_:
			return PackedVector2Array([CENTER + Vector2(-w, -h), CENTER + Vector2(w, -h), CENTER + Vector2(w, h), CENTER + Vector2(-w, h)])


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not finished and Geometry2D.is_point_in_polygon(event.position, panel):
			hit(event.position)
	elif event is InputEventMouseMotion:
		queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				load_level(level_index)
			KEY_N, KEY_ENTER:
				if passed and level_index < LEVELS.size() - 1:
					load_level(level_index + 1)


# ---------------------------------------------------------------- game logic

func hit(aim: Vector2) -> void:
	var jitter: float = LEVELS[level_index]["jitter"]
	var p := aim
	# Pick a uniformly random point inside the jitter circle (sqrt keeps it uniform).
	for _attempt in 20:
		var angle := rng.randf() * TAU
		var r := jitter * sqrt(rng.randf())
		var candidate := aim + Vector2(cos(angle), sin(angle)) * r
		if Geometry2D.is_point_in_polygon(candidate, panel):
			p = candidate
			break
	seeds.append(p)
	pieces = compute_pieces()
	if seeds.size() >= LEVELS[level_index]["hits"]:
		evaluate()
	queue_redraw()


## Splits the panel into Voronoi cells: for every pair of hits, keep only the
## half of the glass that is closer to this hit.
func compute_pieces() -> Array:
	var result := []
	for i in seeds.size():
		var cell := panel
		var a: Vector2 = seeds[i]
		for j in seeds.size():
			if i == j:
				continue
			var b: Vector2 = seeds[j]
			if a.distance_to(b) < 0.01:
				continue
			var mid := (a + b) * 0.5
			var n := (b - a).normalized()
			var d := Vector2(-n.y, n.x)
			var big := 4000.0
			var half_plane := PackedVector2Array([
				mid + d * big, mid - d * big, mid - d * big - n * big, mid + d * big - n * big])
			var clipped := Geometry2D.intersect_polygons(cell, half_plane)
			if clipped.is_empty():
				cell = PackedVector2Array()
				break
			cell = clipped[0]
		if cell.size() >= 3:
			result.append(cell)
	return result


func evaluate() -> void:
	finished = true
	passed = true
	for piece in pieces:
		if not share_ok(piece):
			passed = false


func share_ok(piece: PackedVector2Array) -> bool:
	var ideal := 1.0 / float(LEVELS[level_index]["hits"])
	var tol: float = LEVELS[level_index]["tolerance"]
	var share := polygon_area(piece) / polygon_area(panel)
	return absf(share - ideal) <= ideal * tol


func polygon_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


func centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / max(poly.size(), 1)


func closed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	if out.size() > 0:
		out.append(out[0])
	return out


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var level: Dictionary = LEVELS[level_index]
	var font := ThemeDB.fallback_font
	var total := polygon_area(panel)

	# Glass and pieces
	if pieces.is_empty():
		draw_colored_polygon(panel, GLASS_COLOR)
	for piece in pieces:
		var col := GLASS_COLOR
		if finished:
			col = GOOD_COLOR if share_ok(piece) else BAD_COLOR
		draw_colored_polygon(piece, col)
		draw_polyline(closed(piece), Color(0.95, 0.97, 1.0), 2.0)
		var share := polygon_area(piece) / total
		draw_string(font, centroid(piece) + Vector2(-16, 6), "%d%%" % roundi(share * 100.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	draw_polyline(closed(panel), Color(0.8, 0.9, 1.0), 3.0)

	# Where the hits landed
	for s in seeds:
		draw_circle(s, 4.0, Color(1, 0.85, 0.3))

	# Aim preview: the circle shows where your hit may land
	if not finished:
		var m := get_local_mouse_position()
		if Geometry2D.is_point_in_polygon(m, panel):
			draw_arc(m, level["jitter"], 0.0, TAU, 32, Color(1, 1, 1, 0.6), 1.5)
			draw_circle(m, 2.0, Color.WHITE)

	# HUD
	var hits: int = level["hits"]
	draw_string(font, Vector2(20, 32), "Level %d/%d: %s" % [level_index + 1, LEVELS.size(), level["name"]],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, Vector2(20, 60), "Split the glass into %d equal pieces (each within +/-%d%%).   Hits left: %d" % [
		hits, roundi(level["tolerance"] * 100.0), hits - seeds.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.85, 0.9))
	var msg := "Click to hit. Your hit lands somewhere inside the circle.   R = restart"
	var msg_col := Color(0.7, 0.7, 0.75)
	if finished:
		if passed and level_index == LEVELS.size() - 1:
			msg = "You cleared every level!   R = play again"
			msg_col = Color(0.5, 1.0, 0.6)
		elif passed:
			msg = "Clean split! Press N for the next level."
			msg_col = Color(0.5, 1.0, 0.6)
		else:
			msg = "Uneven pieces (red). Press R to try again."
			msg_col = Color(1.0, 0.55, 0.55)
	draw_string(font, Vector2(20, 580), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, msg_col)
