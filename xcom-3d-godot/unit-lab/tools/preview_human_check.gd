extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var preview = load("res://scenes/unit_previewer.tscn").instantiate()
	root.size = Vector2i(1440, 900)
	root.add_child(preview)
	for i in 15:
		await process_frame
	await RenderingServer.frame_post_draw
	assert(preview.current_unit_type == "HUMAN")
	assert(preview.unit.model != null)
	assert(preview.unit_type_option_btn.get_item_text(preview.unit_type_option_btn.selected) == "Human (WIP)")
	root.get_texture().get_image().save_png("user://human_wip_preview.png")
	var hp = preview.current_hp
	preview.fire_attack(false)
	preview.fire_unit_attack()
	assert(preview.current_hp == hp)
	for index in preview.unit_type_option_btn.item_count:
		preview.unit_type_option_btn.select(index)
		preview.unit_type_option_btn.item_selected.emit(index)
		await process_frame
		assert(preview.unit.model != null)
		assert(preview.current_unit_type == preview.unit_type_option_btn.get_item_metadata(index))
	print("PASS human WIP, dropdown switching, combat guard. Screenshot: ", ProjectSettings.globalize_path("user://human_wip_preview.png"))
	quit()
