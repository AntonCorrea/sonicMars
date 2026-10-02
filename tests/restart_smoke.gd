extends SceneTree

## Smoke test del botón REINICIAR EXPERIENCIA del HUD: el reinicio vuelve la
## misión, las rocas, el rover y el HUD al estado de arranque (spawn en la base
## mirando al OESTE), y los análisis en vuelo quedan invalidados (guard _session).
## Correr: godot --headless --script res://tests/restart_smoke.gd

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

	_check(main._hud_button != null, "el HUD tiene el botón REINICIAR")
	_check(main._session == 0, "sesión arranca en 0")
	_check(player.cell == Vector2i(13, 1) and player.facing == MapGrid.W, "estado inicial: base (13,1) mirando al OESTE")

	# Llevo la partida a un estado avanzado: todo recolectado + misión cumplida,
	# rover lejos mirando al este, HUD con texto de victoria.
	for b in main._rock_data:
		b.collected = true
		b.node.visible = false
		main.grid.set_blocked(b.cell, false)
	main._collected = main._catalog_count
	main._mission_done = true
	main._debug_label.text = "MISIÓN CUMPLIDA"
	player.cell = Vector2i(5, 5)
	player.position = MapGrid.center(player.cell)
	player.facing = MapGrid.E
	player.rotation = MapGrid.forward_angle(MapGrid.E)
	await physics_frame

	# Pulso el botón del HUD (señal pressed → _restart_experience).
	main._hud_button.pressed.emit()
	await physics_frame

	_check(main._collected == 0, "reinicio: 0 muestras a bordo")
	_check(main._catalog_count == 2, "reinicio: catálogo reconstruido (2 muestras)")
	_check(not main._mission_done, "reinicio: misión no cumplida")
	_check(not main._spectro_busy, "reinicio: análisis no ocupado")
	var mundo_ok := true
	for b in main._rock_data:
		mundo_ok = mundo_ok and not b.collected and b.node.visible and main.grid.is_blocked(b.cell)
	_check(mundo_ok, "reinicio: rocas visibles, sin recolectar y bloqueando sus casillas")
	_check(player.cell == Vector2i(13, 1), "reinicio: rover de vuelta en la base")
	_check(player.facing == MapGrid.W, "reinicio: rover mirando al OESTE (estado de arranque)")
	_check(player.position.is_equal_approx(MapGrid.center(Vector2i(13, 1))), "reinicio: rover centrado en su casilla")
	_check("MARTE SÓNICO" in main._debug_label.text, "reinicio: HUD de arranque restaurado")
	_check(main._session == 1, "reinicio: sesión incrementada (invalida coroutines en vuelo)")

	# Un análisis iniciado justo antes del reinicio NO puede completar la
	# recolección ni los anuncios (await interrumpido por la sesión nueva).
	var basalto: Dictionary = main._rock_data[0]
	player.cell = basalto.cell + Vector2i(0, 1)
	player.position = MapGrid.center(player.cell)
	player.facing = MapGrid.N
	player.rotation = MapGrid.forward_angle(MapGrid.N)
	await physics_frame
	main._try_interact()           # arranca sin esperar: queda en vuelo
	main._restart_experience()     # reinicio inmediato
	await create_timer(2.2).timeout # pasa el análisis completo (0.4 + 1.5 s)
	_check(not basalto.collected, "análisis en vuelo invalidado por el reinicio")
	_check(not main._spectro_busy, "análisis invalidado no deja el espectrómetro ocupado")

	print("RESULTADO: %d fallos" % _failures)
	await process_frame
	quit(1 if _failures > 0 else 0)