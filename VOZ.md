# VOZ — Textos hablados de Marte Sónico

Referencia de **todo lo que se dice por voz** en el juego (v1). La pantalla es
prescindible; estas frases son la interfaz principal.

## Cómo funciona

- Toda la voz sale de `scripts/main.gd` → `_say()` → `AudioLib.speak_words()`:
  concatena **palabra por palabra** los WAVs de `assets/voice/` (Piper). Si una
  palabra no tiene WAV, usa el sintetizador formant como fallback.
- **Una frase a la vez**: `_say()` descarta el pedido si otra voz está sonando.
  Los anuncios (`_announce_all_collected`, `_announce_mission_done`) esperan a
  que la voz quede libre antes de hablar.
- **No hay voz en el arranque**: la bienvenida ("MARTE SÓNICO — …") es solo
  texto del HUD. Lo primero que se escucha es LT/Q o los pasos.
- Los números se dicen siempre **≥ 1** (nunca "cero") y coinciden con los pasos
  sobre el eje de la dirección dicha: 2 adelante + 1 al costado = "a 2 casillas
  delante".

## Frases (8 plantillas)

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

### 5 · Espectrómetro — roca decorativa (RT/E)
```
["roca", "de", <VOZ>, "no", "catalogable"]
→ "roca de obsidiana no catalogable"
```
RT/E con una roca **decorativa** en la casilla de enfrente.

### 6 · Espectrómetro — muestra analizada (RT/E)
```
["roca", "de", <VOZ>, "muestra", "analizada"]
→ "roca de basalto, muestra analizada"
```
RT/E con una roca **catalogable** en la casilla de enfrente. Precedido por el
chirrido del espectrómetro y seguido por el *kchk* del contenedor.

### 7 · Anuncio — todas las muestras recolectadas
```
["todas", "las", "muestras", "recolectadas", "volver", "base"]
→ "todas las muestras recolectadas, volvé a la base"
```

### 8 · Anuncio — misión cumplida
```
["mision", "cumplida"]                   → "misión cumplida"
```

## Vocabulario (49 WAVs en assets/voice/)

| Palabra | Uso | | Palabra | Uso |
|---|---|---|---|---|
| roca | frases 2, 5, 6 | | muchas | 2, 4 (N > 15) |
| de | 2, 5, 6 | | obsidiana | 2, 5, 6 |
| a | 2, 4, 6 | | todas | 7 |
| casillas | 2, 4 | | las | 7 |
| basalto | 2, 5, 6 | | muestras | 7 |
| regolito | 2, 5, 6 | | recolectadas | 7 |
| sedimentaria | 2, 5, 6 | | volver | 7 |
| muestra | 6 | | mision | 8 |
| analizada | 6 | | cumplida | 8 |
| no | 5 | | **números** | 2, 4 |
| catalogable | 5 | | (uno…quince) | |
| nada | 1 | | delante | 1, 2, 4 |
| base | 3, 4, 7 | | detras | 2, 4 |
| derecha | 2, 4 | | izquierda | 2, 4 |

### Palabras con WAV pero **sin uso actual** en frases
`brecha` · `ignea` (roca retirada del layout) · `sin` · `retorno` · `solido` ·
`plano` · `cerca` · `y` — restos de los sistemas retirados (sonar de geometría
y vara). Se conservan como asset para futuras frases.

## SFX (no son voz)

Pasos (crunch) · bloqueo (thud) · giro (paneado 80/20 al oído del lado del
giro) · chirrido del espectrómetro · *kchk* del contenedor · viento ambiente.