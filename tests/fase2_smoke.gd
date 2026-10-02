extends SceneTree

## Smoke test Fase 2: voz, alrededores y espectrómetro.
## Correr: godot --headless --script res://tests/fase2_smoke.gd

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

	# La voz genera un WAV con duración válida.
	var wav := AudioLib.speak_words(["roca", "de", "basalto", "a", "cinco", "casillas"])
	_check(wav is AudioStreamWAV and wav.get_length() > 0.3, "speak_words produce audio (voz formant)")

	var main = scene
	var player: Player = scene.get_node("Player")

	# Voz y alrededores ya no dependen de la vara (removida junto al sonar).
	var near_rock := MapGrid.cell_at(main._rock_data[0].node.position)
	player.cell = near_rock + Vector2i(0, 1)
	player.position = MapGrid.center(player.cell)
	player.facing = MapGrid.N
	player.rotation = MapGrid.forward_angle(player.facing)
	await physics_frame

	# Espectrómetro: recolecta basalto y no repite.
	var collected_before: int = main._collected
	player.cell = near_rock + Vector2i(0, 1)
	player.position = MapGrid.center(player.cell)
	await physics_frame
	await main._try_interact()
	await process_frame
	await process_frame
	_check(main._collected == collected_before + 1, "espectrómetro guarda muestra (contador +1)")
	_check(main._rock_data[0].collected, "roca marcada como recolectada")
	var before2: int = main._collected
	await main._try_interact()
	await process_frame
	_check(main._collected == before2, "interacción repetida no suma muestra")

	# Decorativa no suma al catálogo.
	var deco: Dictionary = {}
	for b in main._rock_data:
		if not b.catalogable:
			deco = b
			break
	player.cell = deco.cell + Vector2i(0, 1)
	player.position = MapGrid.center(player.cell)
	await physics_frame
	var before3: int = main._collected
	main._try_interact()
	await process_frame
	_check(main._collected == before3, "roca decorativa no suma al catálogo")

	# Sonido de giro: la señal turn_taken se emite al girar.
	var turned := [false]
	player.turn_taken.connect(func(_turn_left): turned[0] = true)
	player.cell = Vector2i(7, 4)
	player.facing = MapGrid.N
	player.rotation = MapGrid.forward_angle(player.facing)
	player._start_turn(MapGrid.turn_left(player.facing))
	_check(turned[0], "señal turn_taken al girar (sonido de rotación)")

	# Direcciones relativas al cuerpo (alrededores).
	player.cell = Vector2i(7, 4)
	player.position = MapGrid.center(player.cell)
	player.facing = MapGrid.N
	_check(main._relative_dir(Vector2i(7, 2)) == "delante", "N: al norte = delante")
	_check(main._relative_dir(Vector2i(7, 7)) == "detras", "N: al sur = detras")
	_check(main._relative_dir(Vector2i(10, 4)) == "derecha", "N: al este = derecha")
	_check(main._relative_dir(Vector2i(4, 4)) == "izquierda", "N: al oeste = izquierda")
	player.facing = MapGrid.E
	_check(main._relative_dir(Vector2i(10, 4)) == "delante", "E: al este = delante")

	# Alrededores: nombra sólo la roca más cercana + dirección.
	# Desde (12,5) mirando al OESTE: regolito (10,5) a 2 delante.
	player.cell = Vector2i(12, 5)
	player.position = MapGrid.center(player.cell)
	player.facing = MapGrid.W
	player.rotation = MapGrid.forward_angle(player.facing)
	main._describe_surroundings()
	var around: String = main._debug_label.text.to_lower()
	_check(around.contains("alrededor"), "alrededores actualiza la etiqueta")
	_check("regolito" in around, "alrededores nombra la roca más cercana")
	_check("delante" in around, "alrededores da dirección relativa")
	_check(not ("base" in around), "alrededores ya no menciona la base")

	# Cono frontal: desde (7,5) mirando al este, la sedimentaria (6,7) queda
	# fuera del cono (detrás-izquierda) y se nombra la del cono: regolito.
	player.cell = Vector2i(7, 5)
	player.position = MapGrid.center(player.cell)
	player.facing = MapGrid.E
	player.rotation = MapGrid.forward_angle(player.facing)
	main._describe_surroundings()
	var around_e: String = main._debug_label.text.to_lower()
	_check("regolito" in around_e, "alrededores sólo escanea el cono frontal")
	_check(not ("sedimentaria" in around_e), "alrededores ignora roca fuera del cono")

	# Re-activo la detección de basalto para el test del cono de costado
	# (la roca recolectada arriba ya no se detecta por diseño).
	main._rock_data[0].collected = false

	# Costados: desde (10,2) mirando al este, el basalto (10,1) queda justo
	# a la izquierda (1 casilla lateral) y entra en el cono.
	player.cell = Vector2i(10, 2)
	player.position = MapGrid.center(player.cell)
	player.facing = MapGrid.E
	player.rotation = MapGrid.forward_angle(player.facing)
	main._describe_surroundings()
	var around_side: String = main._debug_label.text.to_lower()
	_check("basalto" in around_side, "alrededores cubre el costado (3 casillas de ancho)")
	_check("izquierda" in around_side, "alrededores indica el costado relativo")

	# Volumen parejo: dos frases de distinta longitud suenan igual de fuerte.
	var rms_a := _rms(AudioLib.speak_words(["roca", "de", "basalto"]))
	var rms_b := _rms(AudioLib.speak_words([
		"muestra", "analizada", "roca", "de", "sedimentaria", "a", "quince", "casillas", "izquierda"
	]))
	_check(absf(rms_a - rms_b) / maxf(rms_a, rms_b) < 0.25, "todas las frases tienen volumen parejo (RMS)")

	print("RESULTADO: %d fallos" % _failures)
	await process_frame
	quit(1 if _failures > 0 else 0)

func _rms(wav: AudioStreamWAV) -> float:
	var data := wav.data
	var count := data.size() / 2
	var s := 0.0
	for i in count:
		var v := data.decode_s16(i * 2) / 32768.0
		s += v * v
	return sqrt(s / maxf(1.0, float(count)))