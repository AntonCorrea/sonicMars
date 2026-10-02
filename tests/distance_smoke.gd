extends SceneTree

## Smoke test de distancias del detector (LT / Q): la cantidad dicha debe ser
## PASOS sobre el eje de la dirección nombrada, no distancia diagonal.
## Caso reportado por el usuario: roca a 2 adelante + 1-2 al costado
## → "a 2 casillas delante" (antes: dist. euclidiana → "3").
## Correr: godot --headless --script res://tests/distance_smoke.gd

var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(cond: bool, name: String) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_failures += 1

func _run() -> void:
	var scene: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var main = scene
	var player: Player = scene.get_node("Player")

	# Dejo solo BASALTO (4,2) detectable para probar geometrías precisas.
	for i in range(1, main._rock_data.size()):
		main._rock_data[i].collected = true

	# (pos_jugador, facing, fragmento esperado del HUD)
	var casos := [
		[Vector2i(2, 1), MapGrid.E, "delante 2"],  # 2 adelante, 1 derecha → 2 (caso usuario)
		[Vector2i(2, 0), MapGrid.E, "delante 2"],  # 2 adelante, 2 derecha → 2 (antes 3)
		[Vector2i(1, 1), MapGrid.E, "delante 3"],  # 3 adelante, 1 derecha → 3
		[Vector2i(4, 1), MapGrid.E, "derecha 1"],  # justo a la derecha → 1
		[Vector2i(4, 3), MapGrid.E, "izquierda 1"], # justo a la izquierda → 1
	]
	for c in casos:
		player.cell = c[0]
		player.position = MapGrid.center(player.cell)
		player.facing = c[1]
		player.rotation = MapGrid.forward_angle(player.facing)
		await physics_frame
		main._describe_surroundings()
		await process_frame
		var label: String = main._debug_label.text
		_check(("delante" in label or "detras" in label or "derecha" in label or "izquierda" in label)
			and c[2] in label and "BASALTO" in label,
			"roca desde %s con facing %s → %s (HUD: %s)" % [c[0], c[1], c[2], label])

	# Guía de base: la cantidad también es en pasos del eje dicho.
	for b in main._rock_data:
		b.collected = true
	main._collected = main._catalog_count
	main._mission_done = false
	var base_casos := [
		[Vector2i(10, 1), MapGrid.E, "BASE delante 3"],  # base (13,1) a 3 al frente
		[Vector2i(12, 1), MapGrid.W, "BASE detras 1"],   # base justo detrás
		[Vector2i(13, 2), MapGrid.N, "BASE delante 1"],  # base justo al frente
	]
	for c in base_casos:
		player.cell = c[0]
		player.position = MapGrid.center(player.cell)
		player.facing = c[1]
		player.rotation = MapGrid.forward_angle(player.facing)
		await physics_frame
		main._describe_surroundings()
		await process_frame
		var label: String = main._debug_label.text
		_check(c[2] in label, "guía base desde %s facing %s → %s (HUD: %s)" % [c[0], c[1], c[2], label])

	print("RESULTADO: %d fallos" % _failures)
	await process_frame
	quit(1 if _failures > 0 else 0)