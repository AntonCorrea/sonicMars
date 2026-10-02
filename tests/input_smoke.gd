extends SceneTree

## Smoke test de input: mapeo físico (Q = alrededores sin LB · E = recoger) y
## flanco ascendente de los gatillos (LT → alrededores, RT → recoger), el mismo
## mecanismo por eje en PC y Android.
## Correr: godot --headless --script res://tests/input_smoke.gd

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

	# La intro hablada de arranque secuestra los gatillos (avanza de clip): la
	# doy por terminada para probar el mapeo físico LT/RT (en el juego se
	# supera con cualquier gatillo; ver intro_smoke).
	main._intro_active = false
	main._intro_advancing = false
	main._voice_player.stop()
	player.input_enabled = true

	# --- Mapeo del input map ---
	var surr := InputMap.action_get_events(&"surroundings")
	_check(surr.size() == 1, "surroundings: 1 sola entrada (LB removido)")
	if surr.size() == 1 and surr[0] is InputEventKey:
		_check((surr[0] as InputEventKey).physical_keycode == KEY_Q, "surroundings = tecla Q (física)")
		var itrc := InputMap.action_get_events(&"interact")
		_check(itrc.size() == 1, "interact: 1 sola entrada (E)")
		if itrc.size() == 1 and itrc[0] is InputEventKey:
			_check((itrc[0] as InputEventKey).physical_keycode == KEY_E, "interact = tecla E (física)")

	# --- Tecla Q: action → _process → _describe_surroundings ---
	Input.action_press(&"surroundings")
	await process_frame
	Input.action_release(&"surroundings")
	await process_frame
	_check(main._debug_label.text.begins_with("ALREDEDOR"),
		"Q dispara alrededores (HUD: %s)" % main._debug_label.text)

	# --- LT: flanco ascendente → alrededores, una sola vez por presión ---
	main._consume_left_trigger(1.0)
	var first: String = main._debug_label.text
	_check(first.begins_with("ALREDEDOR"), "LT dispara alrededores")
	_check(main._lt_down, "LT queda pulsado mientras se mantiene")
	main._consume_left_trigger(1.0)
	_check(main._debug_label.text == first, "LT sostenido NO re-dispara")
	main._consume_left_trigger(0.0)
	_check(not main._lt_down, "LT liberado → estado no pulsado")
	main._consume_left_trigger(1.0)
	_check(main._lt_down and main._debug_label.text.begins_with("ALREDEDOR"),
		"LT vuelve a disparar tras liberar")
	main._consume_left_trigger(0.0)

	# --- RT: flanco ascendente → recoger (espectrómetro sobre roca catalogable) ---
	var basalto: Dictionary = main._rock_data[0]
	player.cell = basalto.cell + Vector2i(0, 1)
	player.position = MapGrid.center(player.cell)
	player.facing = MapGrid.N
	player.rotation = MapGrid.forward_angle(MapGrid.N)
	await physics_frame
	main._consume_right_trigger(1.0)
	_check(main._spectro_busy, "RT arranca el análisis del espectrómetro")
	main._consume_right_trigger(0.0)
	_check(not main._rt_down, "RT liberado → estado no pulsado")
	main._consume_right_trigger(1.0)
	_check(main._rt_down and main._spectro_busy, "RT sostenido NO re-dispara (análisis en curso)")
	main._consume_right_trigger(0.0)

	print("RESULTADO: %d fallos" % _failures)
	await process_frame
	quit(1 if _failures > 0 else 0)