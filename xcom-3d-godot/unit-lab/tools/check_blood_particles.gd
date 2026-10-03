## Rendered regression/visual check: run with Godot --path unit-lab --fixed-fps 60
## --script res://tools/check_blood_particles.gd (requires a GPU, not --headless).
extends SceneTree

var world: Node3D
var fx: Node3D
var camera: Camera3D
var output := "user://blood_particles_check"


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for i in count:
		await process_frame
		await RenderingServer.frame_post_draw


func shot(name: String) -> void:
	var img := root.get_texture().get_image()
	assert(img.save_png(output.path_join(name + ".png")) == OK)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(900, 800)
	world = Node3D.new()
	root.add_child(world)
	fx = Node3D.new()
	world.add_child(fx)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.14, 0.17)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.7
	world.add_child(env)
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-40, -25, 0)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(2.2, 1.8, 3.1)
	camera.look_at(Vector3(0, 0.85, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	var cases := [
		["sectoid", SectoidV4LabUnit, "SECTOID/SECTOID.opus-v6", 0.82],
		["snakeman", SnakemanV2LabUnit, "SNAKEMAN/SNAKEMAN.opus-v6", 0.95],
		["floater", FloaterV2LabUnit, "FLOATER/FLOATER.opus-v2", 0.9],
		["floater_v1", FloaterLabUnit, "FLOATER/FLOATER.opus-v1", 0.9],
		["muton", MutonV1LabUnit, "MUTON/MUTON.opus-v1", 1.0],
	]
	for c: Array in cases:
		var unit: LabUnit = c[1].new()
		unit.model_path = "res://assets/models/units/" + c[2] + ".gltf"
		unit.fx_root = fx
		world.add_child(unit)
		await frames(8)
		# Warm up both GPU materials before capturing the short-lived burst.
		unit.blood.spray(Vector3(0, c[3], 0), Vector3.FORWARD)
		await frames(150)
		assert(unit.blood.spawned.is_empty(), "Finished particles must remove their cleanup references")
		for repeat in 2:
			unit.pose_at("Idle", 0.0)
			await frames(8)
			var rec: Dictionary = unit.shoot(Vector3(0, c[3], 3), Vector3.FORWARD, false)
			assert(not rec.get("miss", false), "Expected a real skinned surface hit: " + c[0])
			assert(unit.blood.wounds.size() == repeat + 1)
			var attachment: BoneAttachment3D = unit.blood.wounds.back()
			assert(attachment.bone_name == rec["bone"])
			assert(attachment.get_child_count() == 2, "Expected impact wound and growing drip")
			var wound_decal := attachment.get_child(0) as Decal
			var drip_decal := attachment.get_child(1) as Decal
			assert(wound_decal.sorting_offset > 0 and drip_decal.sorting_offset < 0)
			assert(wound_decal.sorting_offset - drip_decal.sorting_offset > wound_decal.size.length() + drip_decal.size.length(), "Wound sorting must dominate overlapping drip bounds")
			for decal: Decal in attachment.get_children():
				assert(decal.modulate == unit.blood.color)
				assert(decal.cull_mask == unit.layer_mask())
			var bursts: Array[GPUParticles3D] = []
			for node in fx.get_children():
				if node is GPUParticles3D:
					bursts.append(node)
			assert(bursts.size() == 5)
			assert(bursts[0].global_position.is_equal_approx(bursts[1].global_position))
			var point: Array = rec["point"]
			assert(bursts[0].global_position.distance_to(Vector3(point[0], point[1], point[2])) < 0.006)
			for burst in bursts:
				assert(not burst.use_fixed_seed and not burst.local_coords)
				var factors := {"BloodSpray": 0.65, "BloodSprayMedium": 0.95, "BloodSprayLarge": 1.3, "BloodMist": 1.0, "BloodMistLingering": 1.55}
				assert(is_equal_approx(burst.lifetime, float(unit.blood.cfg.get("spray", {}).get("runtime", {}).get("lifetime_s", 0.4)) * float(factors[burst.name])))
				assert(burst.draw_pass_1.material.get_shader_parameter("blood_color") == unit.blood.color)
			for band in 2:
				var smaller := bursts[band].process_material as ParticleProcessMaterial
				var larger := bursts[band + 1].process_material as ParticleProcessMaterial
				assert(smaller.scale_max <= larger.scale_min)
				assert(bursts[band].lifetime < bursts[band + 1].lifetime)
				assert(smaller.initial_velocity_min < smaller.initial_velocity_max and smaller.lifetime_randomness > 0.0)
			await frames(3)
			shot("%s_%d_005" % [c[0], repeat])
			await frames(6)
			shot("%s_%d_015" % [c[0], repeat])
			await frames(9)
			shot("%s_%d_030" % [c[0], repeat])
			await frames(15)
			shot("%s_%d_055" % [c[0], repeat])
			await frames(12)
			shot("%s_%d_075_lingering" % [c[0], repeat])
			await frames(120)
			assert(unit.blood.spawned.is_empty())
		if c[0] == "floater_v1":
			unit.blood.clear()
			unit.pose_at("Idle", 0.0)
			await frames(2)
			var head := unit.skeleton.global_transform * unit.skeleton.get_bone_global_pose(unit.skeleton.find_bone("head")).origin
			var saved_camera := camera.transform
			camera.position = head + Vector3(1, 0.3, -2)
			camera.look_at(head)
			var skin_hit: Dictionary = unit.shoot(head + Vector3(0, 0, -3), Vector3.BACK, false)
			assert(not skin_hit.get("miss", false))
			assert(skin_hit["bone"] == "head", "Expected an exposed head skin hit")
			await frames(33)
			shot("floater_v1_skin_wound")
			unit.blood.clear()
			await frames(2)
			var lethal: Dictionary = unit.shoot(Vector3(0, c[3], -3), Vector3.BACK, true)
			assert(lethal["lethal"] and unit._dying)
			assert(unit.blood.wounds.size() == 1)
			assert(unit.body_mesh.get_active_material(unit.skin_surface).next_pass == null, "No old whole-body wound overlay")
			var particle_count := 0
			for node in fx.get_children():
				if node is GPUParticles3D:
					particle_count += 1
			assert(particle_count == 5, "Lethal impact must emit only one set of three droplet bands and two mist layers")
			unit.blood.clear()
			await frames(2)
			camera.transform = saved_camera
			print("PASS Floater exposed skin and lethal impact")
		unit.blood.spray(Vector3.ZERO, Vector3.UP)
		unit.blood.clear()
		await frames(2)
		assert(fx.get_child_count() == 0, "Clear must remove both droplets and mist")
		unit.queue_free()
		await frames(2)
		print("PASS surface, tint, lifetime, cleanup: ", c[0])
	# A future species requires only its colour; no spray texture or species class.
	var generic := UnitBlood.new()
	world.add_child(generic)
	generic.setup({"per_unit_parameter": {"blood_color_srgb": "#2594db"}, "runtime_files": {}}, "res://", fx)
	var p := generic.spray(Vector3(0, 0.8, 0), Vector3.RIGHT)
	assert(is_equal_approx(p.lifetime, 0.26))
	await frames(9)
	shot("generic_blue_015")
	var first_burst := root.get_texture().get_image().get_data()
	await frames(150)
	assert(generic.spawned.is_empty())
	generic.spray(Vector3(0, 0.8, 0), Vector3.RIGHT)
	await frames(9)
	shot("generic_blue_repeat_015")
	assert(first_burst != root.get_texture().get_image().get_data(), "Identical hits must produce different particle distributions")
	generic.clear()
	await frames(2)
	assert(fx.get_child_count() == 0)
	print("PASS generic species without flipbook. Captures: ", ProjectSettings.globalize_path(output))
	quit()
