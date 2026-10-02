# VOZ — Textos hablados de Marte Sónico

Referencia de **todo lo que se dice por voz** en el juego (v1). La pantalla es
prescindible; estas frases son la interfaz principal.

## Cómo funciona

- Toda la voz sale de `scripts/main.gd` → `_say()` → `AudioLib.speak_words()`:
  concatena **palabra por palabra** los WAVs de `assets/voice/` (ElevenLabs,
  voz Bella; antes Piper). Si una palabra no tiene WAV, usa el sintetizador
  formant como fallback.
- **Ritmo de la voz** (todo en `scripts/audio_lib.gd`): `WORD_GAP` = pausa entre
  palabras (0.03 s), recorte del silencio de relleno por palabra
  (`_trim_silence`, umbral `SILENCE_THRESHOLD`) y `VOICE_SPEED` = velocidad
  final de la frase por resample (1.15 ≈ 15% más rápida).
- **Una frase a la vez**: `_say()` descarta el pedido si otra voz está sonando.
  Los anuncios (`_announce_all_collected`, `_announce_mission_done`) esperan a
  que la voz quede libre antes de hablar.
- **No hay voz en el arranque**: la bienvenida ("MARTE SÓNICO — …") es solo
  texto del HUD. Lo primero que se escucha es LT/Q o los pasos.
- Los números se dicen siempre **≥ 1** (nunca "cero") y coinciden con los pasos
  sobre el eje de la dirección dicha: 2 adelante + 1 al costado = "a 2 casillas
  delante".

## Frases (9 plantillas)

### 1 · Alrededores — nada (LT/Q)
```
["nada", "delante"]                      → "nada delante"
```
No hay ninguna roca sin recolectar dentro del cono frontal.

### 2 · Alrededores — roca más cercana (LT/Q)
```
["roca", "de", <VOZ>, "a", <NUM>, "casillas", <DIR>]
→ "roca de basalto a 3 casillas delante"
→ "roca de obsidiana a 1 casilla derecha"
→ "roca de regolito a muchas casillas izquierda"
```
- `<VOZ>` ∈ {basalto, regolito, obsidiana, sedimentaria} (fallback: "roca")
- `<NUM>` ∈ {uno…quince} o "muchas"
- `<DIR>` ∈ {delante, detras, izquierda, derecha}

### 3 · Guía de base — ya estás en la base (LT/Q)
```
["base"]                                 → "base"
```

### 4 · Guía de base — orientación (LT/Q)
```
["base", "a", <NUM>, "casillas", <DIR>]
→ "base a 4 casillas delante"
→ "base a 2 casillas izquierda"
```

### 5 · Recoger — roca decorativa (RT/E)
```
["roca", "de", <VOZ>, "no", "recogible"]
→ "roca de obsidiana no recogible"
```
RT/E con una roca **decorativa** en la casilla de enfrente. Precedido por el
**sonido de cancelación**.

### 6 · Recoger — muestra recogida (RT/E)
```
["roca", "de", <VOZ>, "recogida"]
→ "roca de basalto recogida"
```
RT/E con una roca **catalogable** en la casilla de enfrente. Precedido por el
**sonido de éxito**; la voz anuncia la muestra.

### 7 · Cancelación — no hay nada delante (RT/E)
```
["no", "hay", "nada", "que", "recoger"]
→ "no hay nada que recoger"
```
RT/E sin ninguna roca en la casilla de enfrente. Precedido por el **sonido de
cancelación**.

### 8 · Anuncio — todas las muestras recolectadas
```
["todas", "las", "muestras", "recolectadas", "volver", "base"]
→ "todas las muestras recolectadas, volvé a la base"
```

### 9 · Anuncio — misión cumplida
```
["mision", "cumplida"]                   → "misión cumplida"
```

## Vocabulario (54 WAVs en assets/voice/)

| Palabra | Uso | | Palabra | Uso |
|---|---|---|---|---|
| roca | 2, 5, 6 | | muchas | 2, 4 (N > 15) |
| de | 2, 5, 6 | | obsidiana | 2, 5, 6 |
| a | 2, 4 | | todas | 8 |
| casillas | 2, 4 | | las | 8 |
| basalto | 2, 5, 6 | | muestras | 8 |
| regolito | 2, 5, 6 | | recolectadas | 8 |
| sedimentaria | 2, 5, 6 | | volver | 8 |
| recogida | 6 | | mision | 9 |
| recoger | 7 | | cumplida | 9 |
| recogible | 5 | | hay | 7 |
| no | 5, 7 | | que | 7 |
| nada | 1, 7 | | delante | 1, 2, 4 |
| base | 3, 4, 8 | | detras | 2, 4 |
| derecha | 2, 4 | | izquierda | 2, 4 |
| **números** | 2, 4 | | (uno…quince) | |

### Palabras con WAV pero **sin uso actual** en frases
`brecha` · `ignea` (roca retirada del layout) · `sin` · `retorno` · `solido` ·
`plano` · `cerca` · `y` — restos de los sistemas retirados (sonar de geometría
y vara). `muestra`, `analizada` y `catalogable` quedaron sin uso al cambiar la
recogida de "muestra analizada" a "recogida". Se conservan como asset para
futuras frases.

## SFX (no son voz)

Pasos (crunch) · bloqueo (thud) · giro (paneado 80/20 al oído del lado del
giro) · **éxito de recogida** (`assets/kagateni__success2.wav`, antes del
anuncio por voz) · **cancelación** (`assets/kagateni__cancel.wav`, antes de
"no hay nada que recoger" y de "no recogible") · viento ambiente.

## Regenerar la voz con otro TTS (ElevenLabs)

El pipeline de voz es agnóstico al generador: un WAV por palabra, PCM 16-bit
**mono 22050 Hz** (`AudioLib._word_audio` rechaza cualquier otro formato y cae
al formant). Para re-baker con ElevenLabs:

1. `python tools/elevenlabs_bake.py --voice-id <id> --out tmp` (key en
   `ELEVENLABS_API_KEY`). Usa `output_format=wav_22050` → WAV PCM directo.
2. Escuchá una frase y si va, volcá sobre `assets/voice/` (guardá los WAV de
   piper por si querés volver).
3. Forzá `compress/mode=0` en los `.import` (QOA → estática) y re-importá.

Más detalles en la cabecera del script.