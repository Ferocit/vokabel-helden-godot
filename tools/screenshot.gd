extends Node
## Screenshot-Hilfe: lädt eine Szene, ruft optional Methoden auf ihr auf, wartet und speichert ein PNG.
## Aufruf (unter Linux z. B. mit xvfb-run):
##   godot --path . --rendering-driver opengl3 res://tools/screenshot.tscn -- \
##     scene=res://scenes/title.tscn out=screenshots/title.png [call=open_unit_manager] [frames=30]

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var scene: PackedScene = load(args.get("scene", "res://scenes/title.tscn"))
	var node := scene.instantiate()
	get_tree().root.add_child.call_deferred(node)
	await get_tree().process_frame
	await get_tree().process_frame
	for m: String in String(args.get("call", "")).split(",", false):
		var parts := m.split("|")
		if parts.size() > 1:
			# Argumente mit @ am Anfang sind Dateipfade, deren Inhalt übergeben wird.
			var call_args := Array(parts.slice(1)).map(func(x: String) -> String:
				return FileAccess.get_file_as_string(x.substr(1)) if x.begins_with("@") else x)
			node.callv(parts[0], call_args)
		else:
			node.call(m)
		for i in 5:
			await get_tree().process_frame
	for i in int(args.get("frames", "30")):
		await get_tree().process_frame
	var out: String = args.get("out", "screenshots/shot.png")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(out.get_base_dir()))
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://").path_join(out))
	print("Screenshot: ", out)
	get_tree().quit()
