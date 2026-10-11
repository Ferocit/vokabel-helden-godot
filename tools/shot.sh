#!/bin/sh
# Linux/Cloud: Screenshot einer Szene per xvfb. Beispiel: tools/shot.sh title scene=res://scenes/title.tscn
name=$1; shift
cd "$(dirname "$0")/.." && xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 res://tools/screenshot.tscn -- out=screenshots/$name.png "$@"
