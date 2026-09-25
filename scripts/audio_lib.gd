class_name AudioLib
extends RefCounted

# Generación procedural de audio (sin assets externos).
# Toda la identidad sonora del juego se construye acá y se rutea por buses
# (Master → Ambiente / SFX / Voz).

static var _rng := RandomNumberGenerator.new()

static func _mono(samples: PackedFloat32Array, rate: int) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav

## Envuelve un síntesis mono en estéreo con un canal dominante ("mayormente" en
## ese oído). strong = proporción del canal fuerte; el otro conserva 1-strong
## para no perder la referencia espacial de la sala.
static func _stereo_panned(samples: PackedFloat32Array, rate: int, strong_left: bool, strong: float = 0.8) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 4)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		var weak := int(v * (1.0 - strong))
		var ch_l := v if strong_left else weak
		var ch_r := weak if strong_left else v
		data.encode_s16(i * 4, ch_l)
		data.encode_s16(i * 4 + 2, ch_r)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = true
	wav.data = data
	return wav

# Sonido n.º 16 · Viento de superficie (loop): ruido marrón.
static func wind(seconds: float = 4.0) -> AudioStreamWAV:
	var rate := AudioServer.get_mix_rate()
	var n := int(rate * seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var lfo := 0.0
	for i in n:
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.006)
		lp2 = lerpf(lp2, lp, 0.12)
		lfo = lerpf(lfo, _rng.randf_range(-1.0, 1.0), 0.02)
		var v := lp2 * (0.7 + 0.3 * lfo)
		out[i] = v * 0.35
	var wav := _mono(out, rate)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav

# Sonido: paso sobre regolito (crunch seco y corto).
static func crunch() -> AudioStreamWAV:
	var rate := AudioServer.get_mix_rate()
	var n := int(rate * 0.09)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.7)
		var env := exp(-t * 34.0)
		out[i] = lp * env * 0.25
	return _mono(out, rate)

# Sonido: paso bloqueado (golpe seco bajo).
static func thud() -> AudioStreamWAV:
	var rate := AudioServer.get_mix_rate()
	var n := int(rate * 0.13)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		phase += TAU * lerpf(170.0, 55.0, t / 0.13) / rate
		var env := exp(-t * 32.0)
		out[i] = sin(phase) * env * 0.7
	return _mono(out, rate)

# ============================================================
# VOZ FORMANTA (Sintetizador): fuente glotal + resonadores.
# No es TTS: vocabulario fijo del juego (tabla WORDS), fonemas
# codificados a mano (PHONES). Ruteado al bus Voz.
# ============================================================

const PHONES := {
	"#":  {"t": "s", "dur": 0.06},
	"a":  {"t": "v", "f1": 720.0, "f2": 1240.0, "f3": 2550.0, "amp": 0.9, "dur": 0.095},
	"e":  {"t": "v", "f1": 540.0, "f2": 1860.0, "f3": 2500.0, "amp": 0.85, "dur": 0.09},
	"i":  {"t": "v", "f1": 400.0, "f2": 2400.0, "f3": 2600.0, "amp": 0.75, "dur": 0.085},
	"o":  {"t": "v", "f1": 500.0, "f2": 920.0,  "f3": 2600.0, "amp": 0.9, "dur": 0.09},
	"u":  {"t": "v", "f1": 380.0, "f2": 620.0,  "f3": 2500.0, "amp": 0.85, "dur": 0.08},
	"b":  {"t": "v", "f1": 260.0, "f2": 980.0,  "f3": 2400.0, "amp": 0.5, "dur": 0.05},
	"d":  {"t": "v", "f1": 320.0, "f2": 1500.0, "f3": 2500.0, "amp": 0.55, "dur": 0.05},
	"g":  {"t": "v", "f1": 300.0, "f2": 1180.0, "f3": 2300.0, "amp": 0.55, "dur": 0.05},
	"l":  {"t": "v", "f1": 420.0, "f2": 1500.0, "f3": 2200.0, "amp": 0.6, "dur": 0.065},
	"m":  {"t": "v", "f1": 330.0, "f2": 980.0,  "f3": 2000.0, "amp": 0.55, "dur": 0.07},
	"n":  {"t": "v", "f1": 360.0, "f2": 1350.0, "f3": 2000.0, "amp": 0.55, "dur": 0.07},
	"r":  {"t": "v", "f1": 420.0, "f2": 1500.0, "f3": 2300.0, "amp": 0.55, "dur": 0.05},
	"rr": {"t": "v", "f1": 420.0, "f2": 1500.0, "f3": 2300.0, "amp": 0.55, "dur": 0.08},
	"y":  {"t": "v", "f1": 380.0, "f2": 2300.0, "f3": 2500.0, "amp": 0.7, "dur": 0.07},
	"p":  {"t": "p", "f2": 1200.0, "amp": 0.55, "dur": 0.06},
	"t":  {"t": "p", "f2": 1900.0, "amp": 0.55, "dur": 0.06},
	"ch": {"t": "p", "f2": 3400.0, "amp": 0.5, "dur": 0.08},
	"k":  {"t": "p", "f2": 1100.0, "amp": 0.55, "dur": 0.06},
	"s":  {"t": "n", "f2": 4300.0, "amp": 0.42, "dur": 0.08},
	"sh": {"t": "n", "f2": 3400.0, "amp": 0.45, "dur": 0.09},
	"z":  {"t": "n", "f2": 3800.0, "amp": 0.4, "dur": 0.08},
}

const WORDS := {
	"roca":        ["r", "o", "k", "a"],
	"de":          ["d", "e"],
	"a":           ["a"],
	"casillas":    ["k", "a", "s", "i", "y", "a", "s"],
	"basalto":     ["b", "a", "s", "a", "l", "t", "o"],
	"regolito":    ["r", "e", "g", "o", "l", "i", "t", "o"],
	"brecha":      ["b", "r", "e", "ch", "a"],
	"ignea":       ["i", "g", "n", "e", "a"],
	"sedimentaria":["s", "e", "d", "i", "m", "e", "n", "t", "a", "r", "i", "a"],
	"muestra":     ["m", "u", "e", "s", "t", "r", "a"],
	"analizada":   ["a", "n", "a", "l", "i", "z", "a", "d", "a"],
	"no":          ["n", "o"],
	"catalogable": ["k", "a", "t", "a", "l", "o", "g", "a", "b", "l", "e"],
	"sin":         ["s", "i", "n"],
	"retorno":     ["r", "e", "t", "o", "r", "n", "o"],
	"solido":      ["s", "o", "l", "i", "d", "o"],
	"plano":       ["p", "l", "a", "n", "o"],
	"base":        ["b", "a", "s", "e"],
	"nada":        ["n", "a", "d", "a"],
	"cerca":       ["s", "e", "r", "k", "a"],
	"delante":     ["d", "e", "l", "a", "n", "t", "e"],
	"detras":      ["d", "e", "t", "r", "a", "s"],
	"izquierda":   ["i", "s", "k", "i", "e", "r", "d", "a"],
	"derecha":     ["d", "e", "r", "e", "ch", "a"],
	"y":           ["i"],
	"muchas":      ["m", "u", "ch", "a", "s"],
	"obsidiana":   ["o", "b", "s", "i", "d", "i", "a", "n", "a"],
	"todas":       ["t", "o", "d", "a", "s"],
	"las":         ["l", "a", "s"],
	"muestras":    ["m", "u", "e", "s", "t", "r", "a", "s"],
	"recolectadas":["r", "e", "k", "o", "l", "e", "k", "t", "a", "d", "a", "s"],
	"volver":      ["b", "o", "l", "b", "e", "r"],
	"mision":      ["m", "i", "s", "i", "o", "n"],
	"cumplida":    ["k", "u", "m", "p", "l", "i", "d", "a"],
	"uno":         ["u", "n", "o"],
	"dos":         ["d", "o", "s"],
	"tres":        ["t", "r", "e", "s"],
	"cuatro":      ["k", "u", "a", "t", "r", "o"],
	"cinco":       ["s", "i", "n", "k", "o"],
	"seis":        ["s", "e", "i", "s"],
	"siete":       ["s", "i", "e", "t", "e"],
	"ocho":        ["o", "ch", "o"],
	"nueve":       ["n", "u", "e", "b", "e"],
	"diez":        ["d", "i", "e", "z"],
	"once":        ["o", "n", "s", "e"],
	"doce":        ["d", "o", "s", "e"],
	"trece":       ["t", "r", "e", "s", "e"],
	"catorce":     ["k", "a", "t", "o", "r", "s", "e"],
	"quince":      ["k", "i", "n", "s", "e"],
}

## Palabra hablada para un número (1..15).
static func number_word(n: int) -> String:
	var nums := ["uno", "dos", "tres", "cuatro", "cinco", "seis", "siete",
		"ocho", "nueve", "diez", "once", "doce", "trece", "catorce", "quince"]
	if n >= 1 and n <= nums.size():
		return nums[n - 1]
	return "diez"

## Convierte palabras en secuencia de fonemas (con silencio entre palabras).
static func words_phones(words: Array) -> Array:
	var out: Array = []
	var first := true
	for w in words:
		var phones: Array = WORDS.get(str(w), [])
		if phones.is_empty():
			continue
		if not first:
			out.append("#")
		out.append_array(phones)
		first = false
	return out

## Coeficientes de un resonador de 2 polos RBJ dado centro f y ancho de banda bw (Hz).
## Bandwidth estrecho (50–120 Hz) = formantes nítidos = voz más clara.
static func _res_coeff(f: float, bw: float, rate: int) -> Array:
	var w := TAU * f / rate
	var alpha := sin(w) * bw / (2.0 * f)
	return [1.0 / (1.0 + alpha), -2.0 * cos(w), 1.0 - alpha, alpha]

## Envolvente por fonema con base 0.2 (evita clics y suaviza las uniones).
static func _seg_env(i: int, n: int, atk: int) -> float:
	if i < atk:
		return 0.2 + 0.8 * (float(i) / atk)
	if i > n - atk:
		return 0.2 + 0.8 * (float(n - i) / atk)
	return 1.0

## Sintetiza una frase como voz femenina natural:
## fuente glotal suave (Rosenberg) con jitter/shimmer/vibrato y aire,
## formantes en paralelo con COARTICULACIÓN (glide entre fonemas),
## radiación de labios parcial. Volumen normalizado por sonoridad (RMS).
static func speak(phones: Array) -> AudioStreamWAV:
	var rate := 22050
	var segs: Array = []
	var total := 0
	for ph in phones:
		var data: Dictionary = PHONES.get(str(ph), {"t": "s", "dur": 0.06})
		segs.append(data)
		total += int(float(data["dur"]) * rate)
	if total < 1:
		total = 1
	var out := PackedFloat32Array()
	out.resize(total)
	var idx := 0
	var fem := 1.16            # tracto vocal femenino: formantes más altos
	var f0 := 205.0            # tono base femenino
	var atk := maxi(1, int(rate * 0.014))
	var vib_phase := 0.0
	# Formantes del fonema previo (coarticulación: glide suave al entrar al nuevo).
	var cf1 := 0.0; var cf2 := 0.0; var cf3 := 0.0
	var have_carry := false
	for data in segs:
		var t := str(data["t"])
		var n := int(float(data["dur"]) * rate)
		if t == "s":
			idx += n
			continue
		var amp: float = float(data.get("amp", 0.7))
		if t == "n":
			# Fricativa: ruido en banda ancha alrededor de f2 → diferenciador.
			var c := _res_coeff(float(data.get("f2", 4000.0)) * fem, 2000.0, rate)
			var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0; var prev := 0.0
			for i in n:
				var src := _rng.randf_range(-1.0, 1.0)
				var y: float = (c[3] * (src - x2) - c[1] * y1 - c[2] * y2) * c[0]
				x2 = x1; x1 = src; y2 = y1; y1 = y
				var rad: float = y - prev
				prev = y
				out[idx] = rad * amp * _seg_env(i, n, atk) * 1.7
				idx += 1
			continue
		# Vocal (v) u oclusiva (p): formantes en paralelo con coarticulación.
		var f1t := float(data.get("f1", 500.0)) * fem
		var f2t := float(data.get("f2", 1500.0)) * fem
		var f3t := float(data.get("f3", 2500.0)) * fem
		if not have_carry:
			cf1 = f1t; cf2 = f2t; cf3 = f3t
			have_carry = true
		var v1x1 := 0.0; var v1x2 := 0.0; var v1y1 := 0.0; var v1y2 := 0.0
		var v2x1 := 0.0; var v2x2 := 0.0; var v2y1 := 0.0; var v2y2 := 0.0
		var v3x1 := 0.0; var v3x2 := 0.0; var v3y1 := 0.0; var v3y2 := 0.0
		var phase := 0.0
		var period := rate / f0
		var shim := 1.0
		var prev := 0.0
		var gap := int(n * 0.4) if t == "p" else 0
		var glide := maxi(1, int(n * 0.55))
		for i in n:
			var src := 0.0
			if t == "v":
				if phase >= 1.0:
					phase -= 1.0
					# declinación prosódica + vibrato + jitter; shimmer en amplitud.
					var decl := 1.0 - 0.15 * (float(idx) / float(total))
					vib_phase += TAU * 5.0 / rate
					var f := f0 * decl * (1.0 + 0.02 * sin(vib_phase) + _rng.randf_range(-0.02, 0.02))
					period = rate / f
					shim = 1.0 + _rng.randf_range(-0.05, 0.05)
				phase += 1.0 / period
				# pulso glotal suave (Rosenberg) + un poco de aire.
				var gp := 0.0
				if phase < 0.42:
					gp = 0.5 * (1.0 - cos(PI * phase / 0.42))
				src = gp * shim + _rng.randf_range(-1.0, 1.0) * 0.05
			else:
				src = _rng.randf_range(-1.0, 1.0)
				if i < gap:
					src *= 0.04
			var gf1 := f1t; var gf2 := f2t; var gf3 := f3t
			if t == "v":
				var g := clampf(float(i) / glide, 0.0, 1.0)
				gf1 = lerpf(cf1, f1t, g)
				gf2 = lerpf(cf2, f2t, g)
				gf3 = lerpf(cf3, f3t, g)
			var c1 := _res_coeff(gf1, 80.0, rate)
			var c2 := _res_coeff(gf2, 100.0, rate)
			var c3 := _res_coeff(gf3, 130.0, rate)
			var s1: float = (c1[3] * (src - v1x2) - c1[1] * v1y1 - c1[2] * v1y2) * c1[0]
			v1x2 = v1x1; v1x1 = src; v1y2 = v1y1; v1y1 = s1
			var s2: float = (c2[3] * (src - v2x2) - c2[1] * v2y1 - c2[2] * v2y2) * c2[0]
			v2x2 = v2x1; v2x1 = src; v2y2 = v2y1; v2y1 = s2
			var s3: float = (c3[3] * (src - v3x2) - c3[1] * v3y1 - c3[2] * v3y2) * c3[0]
			v3x2 = v3x1; v3x1 = src; v3y2 = v3y1; v3y1 = s3
			var voiced := s1 + s2 + 0.5 * s3
			var rad := voiced - prev
			prev = voiced
			out[idx] = (0.55 * rad + 0.45 * voiced) * amp * _seg_env(i, n, atk)
			idx += 1
		cf1 = f1t; cf2 = f2t; cf3 = f3t
	var edge := int(rate * 0.012)
	for i in mini(edge, total / 2):
		out[i] *= float(i) / edge
		out[total - 1 - i] *= float(i) / edge
	# Normalización por sonoridad (RMS) → todas las frases suenan igual de fuerte.
	var sum_sq := 0.0
	for v in out:
		sum_sq += v * v
	var rms := sqrt(sum_sq / float(out.size()))
	if rms > 0.0001:
		var k := 0.11 / rms
		for i in out.size():
			out[i] *= k
	# Limitador de pico (nunca saturar).
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v))
	if peak > 0.9:
		var k2 := 0.9 / peak
		for i in out.size():
			out[i] *= k2
	return _mono(out, rate)

## Dice una frase: carga las palabras pre-generadas con piper y las concatena.
## Lo que no fue horneado cae al sintetizador formant (speak).
static func speak_words(words: Array) -> AudioStreamWAV:
	var full := PackedFloat32Array()
	var gap := int(VOICE_RATE * WORD_GAP)
	for w in words:
		var audio := _word_audio(str(w))
		var samples := _wave_samples(audio)
		if full.size() > 0 and samples.size() > 0:
			full.resize(full.size() + gap)
		var base := full.size()
		full.resize(base + samples.size())
		for i in samples.size():
			full[base + i] = samples[i]
	if full.is_empty():
		full.resize(1)
	var edge := int(VOICE_RATE * 0.006)
	for i in mini(edge, full.size() / 2):
		full[i] *= float(i) / edge
		full[full.size() - 1 - i] *= float(i) / edge
	# Normalización por sonoridad (RMS) + limitador de pico.
	var sum_sq := 0.0
	for v in full:
		sum_sq += v * v
	var rms := sqrt(sum_sq / float(full.size()))
	if rms > 0.0001:
		var k := 0.11 / rms
		for i in full.size():
			full[i] *= k
	var peak := 0.0
	for v in full:
		peak = maxf(peak, absf(v))
	if peak > 0.9:
		var k2 := 0.9 / peak
		for i in full.size():
			full[i] *= k2
	return _mono(full, VOICE_RATE)

# ============================================================
# VOZ POR WAV (piper): palabras pre-generadas en assets/voice/.
# El sintetizador formant (speak) queda como fallback por palabra.
# ============================================================

const VOICE_DIR := "res://assets/voice/"
const VOICE_RATE := 22050
const WORD_GAP := 0.09

static var _word_cache := {}

## Extrae muestras mono 16-bit de cualquier WAV del juego.
static func _wave_samples(audio: AudioStreamWAV) -> PackedFloat32Array:
	var data := audio.data
	var count := data.size() / 2
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		out[i] = float(data.decode_s16(i * 2)) / 32767.0
	return out

## Carga el audio de una palabra (con cache) o sintetiza con formantes.
## Sólo se usa el WAV si es PCM 16-bit mono 22050 Hz (importación sin
## compresión); cualquier otro formato (p.ej. QOA del importador) cae al
## sintetizador formant para no reproducir estática.
static func _word_audio(word: String) -> AudioStreamWAV:
	if _word_cache.has(word):
		return _word_cache[word]
	var path := VOICE_DIR + word + ".wav"
	var audio: AudioStreamWAV
	if ResourceLoader.exists(path):
		var candidate: AudioStreamWAV = load(path)
		if candidate.format == AudioStreamWAV.FORMAT_16_BITS \
				and not candidate.stereo \
				and candidate.mix_rate == VOICE_RATE:
			audio = candidate
	if audio == null:
		audio = speak(words_phones([word]))
	_word_cache[word] = audio
	return audio

# ============================================================
# SONIDOS DE FASE 2 (espectrómetro, contenedor)
# ============================================================

# Sonido 13 · Espectrómetro activo: chirrido analítico y brillante.
static func spectro_chirp() -> AudioStreamWAV:
	var rate := AudioServer.get_mix_rate()
	var n := int(rate * 0.35)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var p := float(i) / n
		var f := lerpf(280.0, 980.0, p * p) + sin(TAU * p * 8.0) * 12.0
		phase += TAU * f / rate
		var src := sin(phase) + 0.3 * _rng.randf_range(-1.0, 1.0)
		var env := sin(PI * p)
		out[i] = src * env * env * 0.6
	return _mono(out, rate)

# Sonido 14 · Contenedor: doble click "kchk" (pitch por escala en runtime).
static func container_kchk() -> AudioStreamWAV:
	var rate := AudioServer.get_mix_rate()
	var n := int(rate * 0.09)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.6)
		var c1v := exp(-t * 140.0) if t < 0.025 else 0.0
		var t2 := t - 0.04
		var c2v := exp(-t2 * 140.0) if t2 >= 0.0 and t2 < 0.03 else 0.0
		out[i] = (c1v + c2v) * lp * 0.7
	return _mono(out, rate)

# Sonido de giro: servo mecánico — barrido descendente + ruido filtrado, corto.
static func turn() -> AudioStreamWAV:
	var rate := AudioServer.get_mix_rate()
	var dur := 0.2
	var n := int(rate * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var p := t / dur
		var f := lerpf(300.0, 150.0, p * p)
		phase += TAU * f / rate
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.25)
		var wobble := 1.0 + 0.25 * sin(TAU * p * 14.0)
		var env := sin(PI * p)
		out[i] = (sin(phase) * 0.5 + lp * 0.45) * env * wobble * 0.5
	return _mono(out, rate)

## Giro paneado al oído del lado del giro (turn_left → canal izquierdo).
## El servo se oye "mayormente" en ese oído; el otro canal conserva un eco leve.
static func turn_panned(turn_left: bool) -> AudioStreamWAV:
	var rate := AudioServer.get_mix_rate()
	var dur := 0.2
	var n := int(rate * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var p := t / dur
		var f := lerpf(300.0, 150.0, p * p)
		phase += TAU * f / rate
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.25)
		var wobble := 1.0 + 0.25 * sin(TAU * p * 14.0)
		var env := sin(PI * p)
		out[i] = (sin(phase) * 0.5 + lp * 0.45) * env * wobble * 0.5
	return _stereo_panned(out, rate, turn_left, 0.8)