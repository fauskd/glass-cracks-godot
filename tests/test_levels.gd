extends SceneTree
## Plays every level with scripted hits and checks that the pieces always
## cover exactly the whole glass panel.
## Run:  godot --headless --path . -s res://tests/test_levels.gd

func _initialize() -> void:
	var g = load("res://main.gd").new()
	root.add_child(g)
	await process_frame
	var all_ok := true
	for li in g.LEVELS.size():
		g.load_level(li)
		var n: int = g.LEVELS[li]["hits"]
		var c: Vector2 = g.centroid(g.panel)
		for k in n:
			var a := TAU * k / n
			g.hit(c + Vector2(cos(a), sin(a)) * 120.0)
		var total := 0.0
		for p in g.pieces:
			total += g.polygon_area(p)
		var area_ok: bool = absf(total - g.polygon_area(g.panel)) < 1.0
		var count_ok: bool = g.pieces.size() == n
		all_ok = all_ok and area_ok and count_ok and g.finished
		print("Level %d: pieces=%d  area_ok=%s  finished=%s  passed=%s" % [li + 1, g.pieces.size(), area_ok, g.finished, g.passed])
	print("ALL TESTS PASSED" if all_ok else "SOME TESTS FAILED")
	quit(0 if all_ok else 1)
