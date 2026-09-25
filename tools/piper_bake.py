"""Genera los WAV de voz del juego con piper (offline, una sola vez).

Uso:
    python tools/piper_bake.py --model <ruta/modelo.onnx> --out assets/voice

Genera un .wav por palabra del vocabulario (clave = WORDS del juego) y por
número (1..15). El juego los concatena en runtime; lo que falte usa el
sintetizador formant como fallback.

NOTA (importación Godot): el importador de WAV de Godot 4.4 usa QOA por
defecto y las voces se escucharían como estática (AudioLib._wave_samples
lee PCM). Tras añadir/regenerar palabras, forzar PCM en los .import:
    Get-ChildItem assets\\voice\\*.wav.import | ForEach-Object {
        (Get-Content $_.FullName -Raw) -replace 'compress/mode=2','compress/mode=0' |
            Set-Content $_.FullName -NoNewline }
    (re-importar el proyecto)
"""

import argparse
import pathlib
import subprocess
import sys

# clave (WORDS del juego) -> texto con ortografía correcta para piper
WORDS = {
    "roca": "roca", "de": "de", "a": "a", "casillas": "casillas",
    "basalto": "basalto", "regolito": "regolito", "brecha": "brecha",
    "ignea": "\u00edgnea", "sedimentaria": "sedimentaria", "muestra": "muestra",
    "analizada": "analizada", "no": "no", "catalogable": "catalogable",
    "sin": "sin", "retorno": "retorno", "solido": "s\u00f3lido", "plano": "plano",
    "base": "base", "nada": "nada", "cerca": "cerca", "delante": "delante",
    "detras": "detr\u00e1s", "izquierda": "izquierda", "derecha": "derecha",
    "y": "y", "muchas": "muchas", "obsidiana": "obsidiana",
    "todas": "todas", "las": "las", "muestras": "muestras",
    "recolectadas": "recolectadas", "volver": "volver",
    "mision": "misión", "cumplida": "cumplida",
}

NUMS = ["uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho",
        "nueve", "diez", "once", "doce", "trece", "catorce", "quince"]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True, help="ruta al .onnx de piper")
    ap.add_argument("--out", required=True, help="carpeta de salida")
    args = ap.parse_args()

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    items = list(WORDS.items()) + [(n, n) for n in NUMS]
    for key, text in items:
        dest = out / f"{key}.wav"
        if dest.exists():
            print(f"[skip] {key}")
            continue
        subprocess.run(
            [sys.executable, "-m", "piper", "--model", args.model,
             "--output_file", str(dest), text],
            check=True,
        )
        print(f"[bake] {key} -> {dest.name}")


if __name__ == "__main__":
    main()