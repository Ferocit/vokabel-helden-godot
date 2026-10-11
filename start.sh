#!/bin/sh
# Vokabel-Helden unter Linux/macOS starten. `./start.sh test` führt die Tests aus.
cd "$(dirname "$0")" || exit 1
GODOT=${GODOT:-$(command -v godot || command -v godot4)}
if [ -z "$GODOT" ]; then
  echo "Godot 4.7 wurde nicht gefunden. Bitte installieren oder GODOT=/pfad/zu/godot setzen." >&2
  exit 1
fi
if [ "$1" = "test" ]; then
  exec "$GODOT" --headless --path . -s res://tests/run_tests.gd
fi
if [ "$1" = "export" ]; then
  mkdir -p build/linux
  exec "$GODOT" --headless --path . --export-release "Linux" build/linux/Vokabel-Helden.x86_64
fi
# Vor jedem Start importieren (neue Skriptklassen nach einem Update registrieren).
"$GODOT" --headless --path . --import
exec "$GODOT" --path .
