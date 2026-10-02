extends SceneTree

## Smoke test Fase 3: misión completa — spawn en la base, roca recolectada que
## deja de detectarse, catálogo 2 muestras (brecha removida), guía hacia la base
## con todas las muestras, y misión cumplida al volver.
## Correr: godot --headless --script res://tests/fase3_smoke.gd

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

	# Misión v1: arranca en la base y hay 2 muestras catalogables.
	_check(player.cell == Vector2i(13, 1), "spawn = base (13,1)")
	_check(main._catalog_count == 2, "catálogo = 2 muestras (brecha removida)")

	# Recolecto basalto (roca 0): desaparece y libera su casilla.
	var basalto: Dictionary = main._rock_data[0]
	player.cell = basalto.cell + Vector2i(0, 1)
	player.position = MapGrid.center(player.cell)
	player.facing = MapGrid.N
	await physics_frame
	await main._try_interact()
	await process_frame
	_check(basalto.collected, "basalto recolectado")
	_check(not basalto.node.visible, "roca recolectada desaparece (visible=false)")
	_check(not main.grid.is_blocked(basalto.cell), "casilla de la roca liberada")

	# Alrededores desde (5,2) mirando al norte: basalto ya no se detecta.
	player.cell = Vector2i(5, 2)
	player.position = MapGrid.center(player.cell)
	player.facing = MapGrid.N
	await physics_frame
	main._describe_surroundings()
	var around: String = main._debug_label.text.to_lower()
	_check("nada" in around, "roca recolectada ya no se detecta (nada delante)")

	# Con todas las muestras, LT describe la BASE (guía de regreso), no las rocas.
	main._collected = main._catalog_count
	for b in main._rock_data:
		b.collected = b.catalogable
	player.cell = Vector2i(10, 1)
	player.position = MapGrid.center(player.cell)
	player.facing = MapGrid.E
	await physics_frame
	main._describe_surroundings()
	var base_around: String = main._debug_label.text.to_lower()
	_check("base" in base_around and "delante" in base_around, "todas recolectadas → LT guía hacia la base")

	# Aviso "todas recolectadas / volver base".
	main._announce_all_collected()
	await process_frame
	_check("base" in main._debug_label.text.to_lower(), "aviso: todas las muestras, volver a la base")

	# Al pisar la base con todo a bordo → misión cumplida.
	player.cell = Vector2i(12, 1)
	player.position = MapGrid.center(player.cell)
	await physics_frame
	main._on_step_taken(Vector2i(13, 1))
	await process_frame
	_check(main._mission_done, "misión cumplida al volver a la base")
	_check("cumplida" in main._debug_label.text.to_lower(), "HUD anuncia misión cumplida")

	print("RESULTADO: %d fallos" % _failures)
	await process_frame
	quit(1 if _failures > 0 else 0)