extends SceneTree

## Smoke test de la intro hablada de arranque: 4 clips (bienvenida, explicación,
## quién sos, controles). Cada uno se REPITE hasta que el jugador pulsa
## CUALQUIER gatillo (LT/RT · Q/E); al pulsar suena el éxito y continúa al
## siguiente; tras el último arranca la misión (conducción libre + primer dato).
## OJO: la pausa de repetición espera tiempo REAL (create_timer), así que corre
## con --quit-after 2000 (600 frames no alcanzan).
## Correr: godot --headless --script res://tests/intro_smoke.gd --quit-after 2000

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

	# Los 4 clips existen y cargan como audio reproducible (MP3 provistos por el
	# usuario en assets/; el bus Voz los reproduce por el player como cualquier stream).
	_check(main.INTRO_PATHS.size() == 4, "la intro tiene 4 clips")
	for p in main.INTRO_PATHS:
		var stream: AudioStream = load(p)
		var len_s := stream.get_length() if stream != null else 0.0
		_check(stream is AudioStream and len_s > 3,
			"%s carga como audio (%.1f s)" % [p.get_file(), len_s])

	# Arranque de la partida: intro activa en el clip 1 y conducción bloqueada.
	_check(main._intro_active, "la partida arranca con la intro activa")
	_check(main._intro_idx == 0, "primer clip = bienvenida")
	_check("bienvenida" in main.INTRO_PATHS[main._intro_idx].to_lower(), "INTRO_PATHS[0] contiene 'bienvenida'")
	_check(not player.input_enabled, "conducción bloqueada durante la intro")
	_check(main._voice_player.stream.resource_path == main.INTRO_PATHS[0], "la voz está cargando la bienvenida")

	# Si el clip termina sin gatillo, hay una PAUSA de silencio y después se
	# repite en loop (sin avanzar de clip).
	var replays_before: int = main._intro_replays
	main._voice_player.finished.emit()
	await create_timer(main.INTRO_REPEAT_PAUSE * 0.5).timeout
	_check(main._intro_replays == replays_before, "pausa antes de repetir (todavía no repite)")
	await create_timer(main.INTRO_REPEAT_PAUSE + 0.1).timeout
	_check(main._intro_replays == replays_before + 1, "clip terminado sin gatillo → repite tras la pausa")
	_check(main._intro_idx == 0, "el loop no avanza de clip")

	# 1er gatillo (RT): suena el éxito y pasa al clip 2.
	main._consume_right_trigger(1.0)
	_check(main._intro_idx == 1, "RT avanza al clip 2 (explicación)")
	_check(main._success_player.playing, "al pulsar suena el éxito")
	main._consume_right_trigger(0.0)

	# Debounce: un gatillo durante el éxito NO saltea clips.
	main._consume_left_trigger(1.0)
	_check(main._intro_idx == 1, "gatillo durante el éxito no saltea al 3")
	main._consume_left_trigger(0.0)

	# Dejo que arranque el clip 2 (espera la cola del éxito).
	await create_timer(main._sfx_lead(main._success_player) + 0.1).timeout
	_check(main._voice_player.stream.resource_path == main.INTRO_PATHS[1], "clip 2 = explicación")
	_check(main._voice_player.playing, "el éxito deja paso al clip 2")

	# 2º gatillo (LT): pasa al clip 3.
	main._consume_left_trigger(1.0)
	_check(main._intro_idx == 2, "LT avanza al clip 3 (quién sos)")
	main._consume_left_trigger(0.0)
	await create_timer(main._sfx_lead(main._success_player) + 0.1).timeout
	_check(main._voice_player.stream.resource_path == main.INTRO_PATHS[2], "clip 3 = quien_sos")

	# 3er gatillo (RT): pasa al clip 4.
	main._consume_right_trigger(1.0)
	_check(main._intro_idx == 3, "RT avanza al clip 4 (controles)")
	main._consume_right_trigger(0.0)
	await create_timer(main._sfx_lead(main._success_player) + 0.1).timeout
	_check(main._voice_player.stream.resource_path == main.INTRO_PATHS[3], "clip 4 = controles")

	# 4º gatillo (LT): termina la intro y arranca la misión.
	main._consume_left_trigger(1.0)
	main._consume_left_trigger(0.0)
	_check(not main._intro_active, "tras el clip 4, el gatillo termina la intro")
	_check(main._intro_idx == -1, "índice de intro reseteado al terminar")
	_check(player.input_enabled, "conducción liberada al terminar la intro")
	_check(main._debug_label.text == main._base_label_text, "HUD restaurado al arrancar la misión")
	_check(main._success_player.playing, "el último gatillo también suena el éxito")

	# La misión arranca con la primera guía (basalto a 3 casillas delante).
	await create_timer(main._sfx_lead(main._success_player) + 0.1).timeout
	_check(main._debug_label.text.begins_with("ALREDEDOR"),
		"misión: primer alrededores en el HUD (%s)" % main._debug_label.text)
	_check(main._voice_player.playing, "misión: la voz anuncia el primer dato")

	# Reiniciar la experiencia re-dispara la intro desde la bienvenida.
	main._hud_button.pressed.emit()
	await process_frame
	_check(main._intro_active, "reinicio → intro activa de nuevo")
	_check(main._intro_idx == 0, "reinicio → vuelve a la bienvenida")
	_check(not player.input_enabled, "reinicio → conducción bloqueada de nuevo")

	# La tecla E (action interact) también cuenta como gatillo durante la intro
	# (patrón anclado tras physics_frame, como input_smoke).
	await physics_frame
	Input.action_press(&"interact")
	await process_frame
	Input.action_release(&"interact")
	await process_frame
	_check(main._intro_idx == 1, "tecla E durante la intro avanza al clip 2")
	_check(main._intro_active, "sigue en la intro (un gatillo no la termina)")

	# Suelto referencias a los clips antes de salir (evita 'resources in use').
	main._voice_player.stop()
	main._voice_player.stream = null
	main._intro_streams.clear()

	print("RESULTADO: %d fallos" % _failures)
	await process_frame
	quit(1 if _failures > 0 else 0)