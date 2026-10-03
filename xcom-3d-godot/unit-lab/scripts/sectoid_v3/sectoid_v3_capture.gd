## Automated Sectoid opus-v3 review run (sectoid_v3_lab.tscn with `-- --capture <dir>`), adapted from lab_capture.gd /
## floater_capture.gd. Run with --fixed-fps 60 (one 60 Hz physics tick per frame).
##
## Writes into <dir>:
##   idle_<SE|NE|NW|SW>.png                  Idle frame 0, review camera, unit faces north
##   colour_<v3|v2>_f<3|7>.png               Idle at sprite facings 3 / 7, floor hidden (colour check vs SECTOID.PCK)
##   clip_<name>_<tag>.png                   clip frames (unit faces east); armed clips show the stand-in pistol
##   turn_hit_<t>.png                        non-lethal hit from E: the unit turns toward the attacker during Hit
##   ragdoll_<from>_top.png / _review.png    death tests from all 8 directions
##   fall_E_<t>.png                          lethal hit from E: turn + crumple lead-in -> ragdoll
##   blood_closeup.png, blood_wound.png, blood_spray_<t>.png
##   bzoom_<v2|v3>_<t>.png                   hit spray at battlescape zoom (Sectoid ~46 px tall, OXCE 2x), v2 vs v3
##   lab_metrics.json
extends Node

const LabMain := preload("res://scripts/lab_main.gd")
const V2_MODEL := "res://assets/models/units/SECTOID/SECTOID.opus-v2.gltf"
const STAND_TARGET := Vector3(0, 0.8, 0)
const STAND_SIZE := 2.1

var lab: Node3D
var out_dir: String
var vp: SubViewport
var cam: Camera3D
var caption: Label
var metrics := {"unit": "units/SECTOID opus-v3", "shots": [], "clips": {}, "ragdoll_tests": [], "turn_hit": {}, "spray_bzoom": {}, "notes": []}


func run(p_lab: Node3D, p_out_dir: String) -> void:
	lab = p_lab
	out_dir = p_out_dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	seed(20261001)
	_make_viewport()
	metrics["engine"] = {
		"godot": Engine.get_version_info()["string"],
		"physics_engine": ProjectSettings.get_setting("physics/3d/physics_engine"),
		"physics_hz": Engine.physics_ticks_per_second,
		"renderer": RenderingServer.get_current_rendering_driver_name() + " / " + RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
	}
	await _ticks(10)
	await _idle_angles()
	await _colour_shots()
	await _clip_frames()
	await _turn_hit()
	await _ragdoll_tests()
	await _blood_shots()
	await _bzoom_spray()
	var f := FileAccess.open(out_dir.path_join("lab_metrics.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(metrics, "  ", false))
	f.close()
	print("UNIT_LAB_CAPTURE_DONE ", out_dir)
	get_tree().quit()


func _make_viewport() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(640, 800)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	cam = Camera3D.new()
	cam.current = true
	vp.add_child(cam)
	caption = Label.new()
	caption.position = Vector2(10, 6)
	caption.add_theme_font_size_override("font_size", 15)
	caption.add_theme_color_override("font_color", Color(1, 1, 1))
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	caption.add_theme_constant_override("outline_size", 5)
	vp.add_child(caption)


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(file: String, size: Vector2i, text: String) -> Image:
	vp.size = size
	caption.text = text
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png(out_dir.path_join(file))
	metrics["shots"].append({"file": file, "caption": text})
	return img


func _idle_angles() -> void:
	var u: LabUnit = lab.spawn_unit(0.0)
	await _ticks(3)
	u.pose_at("Idle", 0.0)
	var names := ["SE", "NE", "NW", "SW"]
	for k in 4:
		LabMain.set_review_camera(cam, LabMain.REVIEW_YAW + k * PI * 0.5, STAND_TARGET, STAND_SIZE)
		await _shot("idle_%s.png" % names[k], Vector2i(560, 700), "Idle f0 | review cam %s, 30 deg ortho | unit faces N" % names[k])


## Colour check: sprite facings 3 (faces the SE camera) and 7 (back), floor hidden so only the unit differs from the
## background; the same shots of the opus-v2 model give the before / after.
func _colour_shots() -> void:
	var floor_node: Node3D = lab.get_node("Floor")
	floor_node.visible = false
	for model: Array in [["v3", ""], ["v2", V2_MODEL]]:
		for fc in [3, 7]:
			var u: LabUnit = lab.spawn_unit_model(-PI * 0.25 * fc, model[1])
			await _ticks(3)
			u.pose_at("Idle", 0.0)
			LabMain.set_review_camera(cam, LabMain.REVIEW_YAW, STAND_TARGET, STAND_SIZE)
			await _shot("colour_%s_f%d.png" % [model[0], fc], Vector2i(560, 700), "")
	floor_node.visible = true


func _clip_frames() -> void:
	var u: LabUnit = lab.spawn_unit(-PI * 0.5)  # facing 2 = east
	await _ticks(3)
	var shots := [
		["Idle", 0.5], ["IdleArmed", 0.5], ["Walk", 0.5], ["WalkArmed", 0.5], ["Attack", 0.5], ["Attack", -12],
		["Hit", 0.5], ["Kneel", 1.0], ["Death", -3], ["Death", -6], ["Death", -9], ["Death", 1.0],
		["DeathBaked", 0.6], ["DeathBaked", 1.0],
	]
	for s: Array in shots:
		var clip: String = (u as SectoidV3LabUnit)._clip(s[0])
		var length := u.anim.get_animation(clip).length
		var t: float = length * s[1] if s[1] >= 0 else -float(s[1]) / 30.0
		u.pose_at(s[0], t)
		await _ticks(1)
		var tag := "mid" if s[1] is float and s[1] == 0.5 else ("end" if s[1] is float and s[1] == 1.0 else ("f%d" % -int(s[1]) if s[1] is int else "t%02d" % int(round(float(s[1]) * 10))))
		var target := STAND_TARGET
		var size := STAND_SIZE
		if clip.begins_with("Death"):
			target = Vector3(-0.45, 0.45, 0)
			size = 2.5
		LabMain.set_review_camera(cam, LabMain.REVIEW_YAW, target, size)
		var file := "clip_%s_%s.png" % [s[0], tag]
		await _shot(file, Vector2i(560, 700), "%s %s (t=%.3f s of %.3f s) | review SE | unit faces E" % [clip, tag, t, length])
		metrics["clips"][clip] = {"length_s": length, "tracks": u.anim.get_animation(clip).get_track_count(),
			"loop": u.anim.get_animation(clip).loop_mode != Animation.LOOP_NONE}


## Non-lethal hit from the east on a unit facing north: it turns toward the attacker during the Hit clip.
func _turn_hit() -> void:
	var u: SectoidV3LabUnit = lab.spawn_unit(0.0)
	await _ticks(20)
	var arrow := _arrow(Vector3(-1, 0, 0))
	var start := Engine.get_physics_frames()
	u.hit(Vector3(-1, 0, 0))
	var yaws := []
	for t in [0.0, 0.1, 0.2, 0.35]:
		while (Engine.get_physics_frames() - start) / 60.0 < t - 1e-4:
			await get_tree().physics_frame
		var ts := (Engine.get_physics_frames() - start) / 60.0
		yaws.append([snappedf(ts, 0.001), snappedf(rad_to_deg(u.rotation.y), 0.1)])
		LabMain.set_review_camera(cam, LabMain.REVIEW_YAW, Vector3(0, 0.75, 0), 2.4)
		await _shot("turn_hit_%03d.png" % int(round(t * 100)), Vector2i(520, 600), "Hit from E (unit faced N): t = %.2f s, yaw %.0f deg" % [ts, rad_to_deg(u.rotation.y)])
	metrics["turn_hit"] = {"from": "E", "log": u.turn_log, "yaw_samples_s_deg": yaws}
	arrow.queue_free()


func _ragdoll_tests() -> void:
	var tests := [
		["N", Vector3(0, 0, 1)], ["NE", Vector3(-1, 0, 1).normalized()], ["E", Vector3(-1, 0, 0)], ["SE", Vector3(-1, 0, -1).normalized()],
		["S", Vector3(0, 0, -1)], ["SW", Vector3(1, 0, -1).normalized()], ["W", Vector3(1, 0, 0)], ["NW", Vector3(1, 0, 1).normalized()],
	]
	var idx := 0
	for t: Array in tests:
		var from_name: String = t[0]
		var dir: Vector3 = t[1]
		var u: LabUnit = lab.spawn_unit(0.0)
		(u.ragdoll as SectoidV3Ragdoll).rng.seed = 7001 + idx   # a different (repeatable) per-death variation per test
		idx += 1
		await _ticks(20)
		var arrow := _arrow(dir)
		var rep := {}
		u.died.connect(func(r: Dictionary) -> void: rep.merge(r))
		var start_frame := Engine.get_physics_frames()
		u.die(dir)
		var strip := from_name == "E"
		var strip_times := [0.0, 0.1, 0.2, 0.3, 0.4, 0.6, 1.0, 1.8]
		if strip:
			LabMain.set_review_camera(cam, LabMain.REVIEW_YAW, Vector3(-0.4, 0.55, 0), 2.7)
			await _shot("fall_E_000.png", Vector2i(560, 560), "Lethal hit from E (unit faced N) | t = 0.00 s: lethal frame, no snap")
			strip_times.pop_front()
		while not rep.has("settle_time_s") and Engine.get_physics_frames() - start_frame < 420:
			await get_tree().physics_frame
			var t_s := (Engine.get_physics_frames() - start_frame) / 60.0
			if strip and not strip_times.is_empty() and t_s >= strip_times[0] - 1e-4:
				LabMain.set_review_camera(cam, LabMain.REVIEW_YAW, Vector3(-0.4, 0.55, 0), 2.7)
				await _shot("fall_E_%03d.png" % int(round(t_s * 100)), Vector2i(560, 560), "Attack from E | t = %.2f s after the lethal hit (turn 0-0.2 s, hand-off 0.40 s) | yaw %.0f" % [t_s, rad_to_deg(u.rotation.y)])
				strip_times.pop_front()
		rep["from"] = from_name
		rep["frames_to_freeze"] = Engine.get_physics_frames() - start_frame
		await _ticks(160)
		var flags := _flags(rep)
		rep["exploded"] = flags[0]
		rep["interpenetration"] = flags[1]
		metrics["ragdoll_tests"].append(rep)
		LabMain.set_top_camera(cam, Vector3.ZERO, 4.6)
		var line1 := "Attack from %s -> falls %s | settled %.2f s after hand-off (%s)" % [from_name, _opposite(from_name), rep.get("settle_time_s", -1.0), rep.get("settle_reason", "?")]
		var line2 := "past tile edge: joints %.2f m | bodies %.2f m | mesh %.2f m | align %.2f" % [rep.get("joint_outside_tile_m", -1.0), rep.get("shape_outside_tile_m", -1.0), rep.get("mesh_outside_tile_m", -1.0), rep.get("fall_alignment", -9.0)]
		var line3 := "peak %.1f m/s | joint gap max %.1f cm | jitter %+.1f deg, spin %+.2f | %s" % [rep.get("max_body_speed_mps", -1.0), rep.get("max_joint_separation_m", -1.0) * 100.0, rep.get("push_jitter_deg", 0.0), rep.get("spin_added_radps", 0.0), "EXPLODED" if flags[0] else "stable"]
		await _shot("ragdoll_%s_top.png" % from_name, Vector2i(760, 760), "%s\n%s\n%s\n(top view, north up, 2 m tiles, 0.5 m sub-grid)" % [line1, line2, line3])
		LabMain.set_review_camera(cam, LabMain.REVIEW_YAW, Vector3(rep["pelvis_xz"][0], 0.2, rep["pelvis_xz"][1]), 2.8)
		await _shot("ragdoll_%s_review.png" % from_name, Vector2i(640, 520), "Attack from %s | corpse, review SE" % from_name)
		if from_name == "E":
			await _corpse_closeups(u)
		arrow.queue_free()


func _flags(rep: Dictionary) -> Array:
	var exploded: bool = rep.get("nan", false) or rep.get("max_body_speed_mps", 0.0) > 8.0 \
		or rep.get("max_joint_separation_m", 0.0) > 0.05 or rep.get("lowest_shape_y_during_m", 0.0) < -0.05
	var overlap := 0.0
	for o: Dictionary in rep.get("body_overlaps", []):
		overlap = maxf(overlap, o["depth_m"])
	var interpen: bool = overlap > 0.01 or rep.get("mesh_min_y_m", 0.0) < -0.02
	return [exploded, interpen]


func _opposite(n: String) -> String:
	return {"N": "S", "S": "N", "E": "W", "W": "E", "NE": "SW", "SW": "NE", "NW": "SE", "SE": "NW"}[n]


func _arrow(dir: Vector3) -> Node3D:
	var a := Node3D.new()
	a.name = "AttackArrow"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.9, 0.12, 0.08)
	var shaft := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.02, 0.5)
	box.material = mat
	shaft.mesh = box
	shaft.layers = 1 << 3
	a.add_child(shaft)
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.12
	cone.height = 0.22
	cone.radial_segments = 3
	cone.material = mat
	head.mesh = cone
	head.layers = 1 << 3
	head.rotation.x = -PI * 0.5
	head.position = Vector3(0, 0, -0.35)
	a.add_child(head)
	lab.add_child(a)
	a.basis = Basis.looking_at(dir, Vector3.UP)
	a.position = -dir.normalized() * 1.75 + Vector3(0, 0.02, 0)
	return a


func _corpse_closeups(u: LabUnit) -> void:
	var pelvis := Vector3(u.death_report["pelvis_xz"][0], 0.0, u.death_report["pelvis_xz"][1])
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 34.0
	cam.position = pelvis + Vector3(1.2, 1.35, 1.25)
	cam.look_at(pelvis + Vector3(-0.1, 0.05, 0.0), Vector3.UP)
	await _shot("blood_closeup.png", Vector2i(900, 640), "Blood close-up: pool + splatter decals + wound overlay, tint #%s" % u.blood.color.to_html(false))
	var chest := u.skeleton.global_transform * u.skeleton.get_bone_global_pose(u.skeleton.find_bone("spine_03")).origin
	cam.fov = 26.0
	cam.position = chest + Vector3(0.55, 0.75, 0.75)
	cam.look_at(chest, Vector3.UP)
	await _shot("blood_wound.png", Vector2i(900, 640), "Wound overlay (UV0, next_pass on skin) on the frozen corpse")


func _blood_shots() -> void:
	var u: LabUnit = lab.spawn_unit(0.0)
	await _ticks(10)
	u.pose_at("Idle", 0.0)
	var dir := Vector3(-1, 0, 1).normalized()
	LabMain.set_review_camera(cam, LabMain.REVIEW_YAW, Vector3(-0.3, 0.95, 0.3), 1.8)
	var start := Engine.get_physics_frames()
	u.hit(dir)
	for t in [0.05, 0.15, 0.25, 0.35]:
		while (Engine.get_physics_frames() - start) / 60.0 < t:
			await get_tree().physics_frame
		await _shot("blood_spray_%03d.png" % int(round(t * 100)), Vector2i(640, 640), "Hit + v3 spray (2x2 flipbook, sidecar runtime params) t=%.2f s | shot from NE" % t)


## Battlescape zoom: 192 px viewport, 5.9 m ortho height -> ~33 px/m, the Sectoid ~46 px tall (the PCK sprite at OXCE 2x).
## The same spray call with the opus-v2 settings (0.6 m quad, 3 bursts, 128 px flipbook) gives the before.
func _bzoom_spray() -> void:
	var v2_book: Texture2D = load("res://assets/textures/units/sectoid_opus-v1_blood_spray_flipbook_2x2.png")
	var dir := Vector3(-1, 0, 1).normalized()
	for variant in ["v2", "v3"]:
		var u: SectoidV3LabUnit = lab.spawn_unit(0.0)
		await _ticks(10)
		u.pose_at("Idle", 0.0)
		LabMain.set_review_camera(cam, LabMain.REVIEW_YAW, Vector3(-0.2, 0.8, 0.2), 5.9)
		var start := Engine.get_physics_frames()
		var b := u.blood as SectoidV3Blood
		if variant == "v2":
			b.spray_custom(u.chest_point(dir), dir, SectoidV3Blood.V2_SPRAY, v2_book)
		else:
			b.spray(u.chest_point(dir), dir)
		var counts := []
		for t in [0.05, 0.15, 0.25]:
			while (Engine.get_physics_frames() - start) / 60.0 < t:
				await get_tree().physics_frame
			var img := await _shot("bzoom_%s_%03d.png" % [variant, int(round(t * 100))], Vector2i(192, 192), "")
			counts.append(_green_pixels(img))
		metrics["spray_bzoom"][variant] = {"green_pixels_at_0.05_0.15_0.25_s": counts, "viewport_px": 192, "ortho_m": 5.9}


static func _green_pixels(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.g > c.r + 0.03 and c.g > c.b + 0.03:
				n += 1
	return n
