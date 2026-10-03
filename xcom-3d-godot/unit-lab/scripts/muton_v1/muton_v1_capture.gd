## Automated Muton opus-v1 (copy of the Sectoid opus-v4 lab file) review run (snakeman_lab.tscn with `-- --capture <dir>`), adapted from sectoid_v3_capture.gd
## (units_opus55). Run with --fixed-fps 60 (one 60 Hz physics tick per frame).
##
## User decisions 2026-10-02 covered here: snappy directional death (no animated turn), the late-turn TWIST (whole body,
## toward the shooter, scaled by the facing / shot angle), hit-point wound decals + spray from the hit point.
## Writes into <dir>:
##   idle_<SE|NE|NW|SW>.png                  Idle frame 0, review camera, unit faces north
##   colour_v1_f<3|7>.png                    Idle at sprite facings 3 / 7, floor hidden (hue / contrast check vs SNAKEMAN.PCK)
##   clip_<name>_<tag>.png                   clip frames (unit faces east); armed clips show the stand-in pistol
##   hit_<from>_<t>.png                      non-lethal hits from the front / side / back: directional recoil, no turn
##   fall_<from>_<t>.png                     lethal hits from the front (N) / side (E) / back (S): recoil -> ragdoll + twist
##   ragdoll_<from>_top.png / _review.png    death tests from all 8 directions (unit faces N)
##   shot_<region>_<from>.png                hit-point gallery: head / torso / arm / serpent from several directions
##   stack_<n>.png, corpse_*.png             decals stacking to the cap, then following the body through the ragdoll
##   drip_<t>.png                            hits on head / torso / arm / serpent, runs growing down the surface, then a
##                                           lethal shot: the runs stay on their bones through the fall
##   spray_<from>_<t>.png, wound_<from>*.png spray from the skin point along the shot, wound + drips (front / side / back)
##   bzoom_<v1|cam>_<t>.png                  hit spray at battlescape zoom
##   lab_metrics.json
extends Node

const LabMain := preload("res://scripts/lab_main.gd")
const STAND_TARGET := Vector3(0, 1.05, 0)
const STAND_SIZE := 2.8
## Muton (2.14 m, very broad): framing for the close / review / fall views
const BODY_T := Vector3(0, 1.1, 0)
const BODY_S := 3.0
const DIRS := {"N": Vector3(0, 0, 1), "NE": Vector3(-0.7071, 0, 0.7071), "E": Vector3(-1, 0, 0), "SE": Vector3(-0.7071, 0, -0.7071),
	"S": Vector3(0, 0, -1), "SW": Vector3(0.7071, 0, -0.7071), "W": Vector3(1, 0, 0), "NW": Vector3(0.7071, 0, 0.7071)}

## blood check v2 hits: [row, shooter side, target bone, offset]
const BC_HITS := [["front", "N", "spine_03", Vector3(0.05, 0.02, 0)], ["side", "E", "spine_02", Vector3(0, 0.0, -0.03)], ["back", "S", "spine_03", Vector3(0.05, 0.02, 0)]]

var lab: Node3D
var out_dir: String
var vp: SubViewport
var cam: Camera3D
var caption: Label
var metrics := {"unit": "units/MUTON opus-v1", "shots": [], "clips": {}, "ragdoll_tests": [], "hits": {}, "gallery": [],
	"stack": {}, "spray_bzoom": {}, "notes": []}


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
	await _hit_variants()
	await _ragdoll_tests()
	await _shot_gallery()
	await _spray_closeups()
	await _stack_and_die()
	await _drip_sequence()
	await _bzoom_spray()
	var f := FileAccess.open(out_dir.path_join("lab_metrics.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(metrics, "  ", false))
	f.close()
	print("UNIT_LAB_CAPTURE_DONE ", out_dir)
	get_tree().quit()


## Blood verification run (user priority 2026-10-02): `-- --blood-check <dir>`. Front / side / back hits on a unit facing N:
## red arrow = the shot (pointing along its travel, ending just short of the skin), caption = the shooter's side of the
## frame; spray frames at 0.05 / 0.15 / 0.30 s (side-on, from the shooter's side), wound + drips at 0.5 s and 2 s, and a
## game-zoom view (5.9 m ortho in 192 px, 30 deg, from the shooter's side). Writes bc_*.png + blood_check.json.
func run_blood_check(p_lab: Node3D, p_out_dir: String) -> void:
	# Blood check v2 (user feedback 2026-10-02: the spray must visibly emerge AT the skin where the hit lands): front / side
	# / back hits on a unit facing N; side-on GRAZING close-ups at 0.02 / 0.05 / 0.10 s (camera perpendicular to the spray, at
	# the hit height, looking along the skin) so any gap between the wound and the spray root shows; an oblique view from
	# the shooter's side at 0.05 s; wound + drips at 0.5 s and 2 s; a game-zoom view. Writes bc_*.png + blood_check.json.
	lab = p_lab
	out_dir = p_out_dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	seed(20261001)
	_make_viewport()
	await _ticks(10)
	var rows := {}
	for cfg: Array in BC_HITS:
		var from_name: String = cfg[1]
		var dir: Vector3 = DIRS[from_name]
		var u: MutonV1LabUnit = lab.spawn_unit(0.0)
		await _ticks(10)
		u.pose_at("Idle", 0.0)
		await _ticks(2)
		var target: Vector3 = _bone_pos(u, cfg[2]) + (cfg[3] as Vector3)
		var origin := target - dir * 2.5
		var start := Engine.get_physics_frames()
		var rec: Dictionary = u.shoot(origin, dir, false)
		var hp := Vector3(rec["point"][0], rec["point"][1], rec["point"][2])
		var hn := Vector3(rec["normal"][0], rec["normal"][1], rec["normal"][2])
		var sd := Vector3(rec["spray_dir"][0], rec["spray_dir"][1], rec["spray_dir"][2])
		var sp := Vector3(rec["spray_origin"][0], rec["spray_origin"][1], rec["spray_origin"][2])
		var line := _ray_line(hp - dir * 0.7, hp - dir * 0.16)
		# side-on: horizontal perpendicular to the spray, on the side away from the body axis
		var sh := Vector3(sd.x, 0.0, sd.z)
		if sh.length() < 1e-3:
			sh = -Vector3(dir.x, 0.0, dir.z)
		var side := sh.normalized().cross(Vector3.UP).normalized()
		var axis := Vector3(u.global_position.x, hp.y, u.global_position.z)
		if (hp + side * 0.5).distance_to(axis) < (hp - side * 0.5).distance_to(axis):
			side = -side
		var look := hp + sd * 0.07
		var eye := hp + side * 0.80 + Vector3.UP * 0.06 + sh.normalized() * 0.07
		for t in [0.02, 0.05, 0.10]:
			var ts := await _wait_until(start, t)
			_persp(look, eye, 30.0)
			await _shot("bc_%s_side_%03d.png" % [cfg[0], int(round(t * 100))], Vector2i(480, 480),
				"%s hit (shot from %s), side-on grazing close-up, t = %.3f s\nspray root on the wound (red line = the shot)" % [cfg[0], from_name, ts])
		# oblique, from the shooter's side
		var ts2 := Engine.get_physics_frames()
		var eye2 := hp + sh.normalized() * 0.75 + side * 0.40 + Vector3.UP * 0.18
		_persp(hp + sd * 0.05, eye2, 34.0)
		await _shot("bc_%s_oblique.png" % cfg[0], Vector2i(480, 480), "%s hit, from the shooter's side at t = %.3f s" % [cfg[0], (ts2 - start) / 60.0])
		line.queue_free()
		var bx := _bone_xf(u, rec["bone"])
		var rc := {"bone": rec["bone"], "local_point": bx.affine_inverse() * hp, "local_normal": (bx.basis.inverse() * hn).normalized()}
		for t in [0.5, 2.0]:
			var ts := await _wait_until(start, t)
			_look_at_hit(u, rc, 1.15, 0.05)
			await _shot("bc_%s_wound_%03d.png" % [cfg[0], int(round(t * 100))], Vector2i(480, 480),
				"%s hit: %s wound + drips on %s, t = %.1f s" % [cfg[0], rec["wound"], rec["bone"], ts])
		var s_ := -dir
		LabMain.set_review_camera(cam, atan2(s_.x, s_.z), Vector3(0, 1.05, 0), 5.9)
		await _shot("bc_%s_game.png" % cfg[0], Vector2i(192, 192), "")
		rows[cfg[0]] = {"from": from_name, "bone": rec["bone"], "wound": rec["wound"], "hit_point": rec["point"], "normal": rec["normal"],
			"spray_origin": rec["spray_origin"], "spray_dir": rec["spray_dir"], "shot_dir": rec["shot_dir"],
			"spray_toward_shooter_cos": snappedf(sd.dot(-dir), 0.001),
			"origin_offset_along_normal_m": snappedf((sp - hp).dot(hn), 0.0001),
			"wound_size_m": u.blood_profile["wound_decals"]["size_m"][rec["wound"]], "drip_size_m": u.blood_profile["wound_decals"]["drips"]["size_m"],
			"spray_runtime": u.blood_profile["spray"]["runtime"]}
	var f := FileAccess.open(out_dir.path_join("blood_check.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(rows, "  ", false))
	f.close()
	print("BLOOD_CHECK_DONE ", out_dir)
	get_tree().quit()


## Red 3D arrow from `a` to `b` (head at b).
func _shot_arrow(a: Vector3, b: Vector3) -> Node3D:
	var n := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.95, 0.1, 0.06)
	var L := a.distance_to(b)
	var shaft := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.025, 0.025, L - 0.12)
	box.material = mat
	shaft.mesh = box
	shaft.layers = 1 << 3
	shaft.position = Vector3(0, 0, -(L - 0.12) * 0.5)
	n.add_child(shaft)
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.05
	cone.height = 0.12
	cone.material = mat
	head.mesh = cone
	head.layers = 1 << 3
	head.rotation.x = -PI * 0.5
	head.position = Vector3(0, 0, -(L - 0.06))
	n.add_child(head)
	lab.add_child(n)
	n.global_transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP), a)
	return n


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


func _wait_until(start: int, t: float) -> float:
	while (Engine.get_physics_frames() - start) / 60.0 < t - 1e-4:
		await get_tree().physics_frame
	return (Engine.get_physics_frames() - start) / 60.0


func _shot(file: String, size: Vector2i, text: String) -> Image:
	vp.size = size
	caption.text = text
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png(out_dir.path_join(file))
	metrics["shots"].append({"file": file, "caption": text})
	return img


func _persp(at: Vector3, from: Vector3, fov := 34.0) -> void:
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = fov
	cam.position = from
	cam.look_at(at, Vector3.UP)


func _idle_angles() -> void:
	var u: LabUnit = lab.spawn_unit(0.0)
	await _ticks(3)
	u.pose_at("Idle", 0.0)
	var names := ["SE", "NE", "NW", "SW"]
	for k in 4:
		LabMain.set_review_camera(cam, LabMain.REVIEW_YAW + k * PI * 0.5, STAND_TARGET, STAND_SIZE)
		await _shot("idle_%s.png" % names[k], Vector2i(560, 700), "Idle f0 | review cam %s, 30 deg ortho | unit faces N" % names[k])


## Colour check: sprite facings 3 (faces the SE camera) and 7 (back), floor hidden.
func _colour_shots() -> void:
	var floor_node: Node3D = lab.get_node("Floor")
	floor_node.visible = false
	for fc in [3, 7]:
		var u: LabUnit = lab.spawn_unit_model(-PI * 0.25 * fc, "")
		await _ticks(3)
		u.pose_at("Idle", 0.0)
		LabMain.set_review_camera(cam, LabMain.REVIEW_YAW, STAND_TARGET, STAND_SIZE)
		await _shot("colour_v1_f%d.png" % fc, Vector2i(560, 700), "")
	floor_node.visible = true


func _clip_frames() -> void:
	var u: LabUnit = lab.spawn_unit(-PI * 0.5)  # facing 2 = east
	await _ticks(3)
	var shots := [
		["Idle", 0.5], ["IdleArmed", 0.5], ["Walk", 0.5], ["WalkArmed", 0.5], ["Attack", 0.5], ["Attack", -12],
		["Walk", 0.0], ["Walk", 0.25], ["HitFront", -2], ["HitLeft", -2],
		["DeathFront", -2], ["DeathFront", -4], ["DeathBack", -4], ["DeathLeft", -4], ["DeathRight", -4],
		["DeathBaked", 0.6], ["DeathBaked", 1.0],
	]
	for s: Array in shots:
		var clip: String = (u as MutonV1LabUnit)._clip(s[0])
		if not u.anim.has_animation(clip):
			metrics["notes"].append("clip missing: " + clip)
			continue
		var length := u.anim.get_animation(clip).length
		var t: float = length * s[1] if s[1] >= 0 else -float(s[1]) / 30.0
		u.pose_at(s[0], t)
		await _ticks(1)
		var tag := "mid" if s[1] is float and s[1] == 0.5 else ("end" if s[1] is float and s[1] == 1.0 else ("f%d" % -int(s[1]) if s[1] is int else "t%03d" % int(round(float(s[1]) * 100))))
		var target := STAND_TARGET
		var size := STAND_SIZE
		if clip.begins_with("DeathBaked"):
			target = Vector3(-0.2, 0.6, 0)
			size = 3.4
		LabMain.set_review_camera(cam, LabMain.REVIEW_YAW, target, size)
		var file := "clip_%s_%s.png" % [s[0], tag]
		await _shot(file, Vector2i(560, 700), "%s %s (t=%.3f s of %.3f s) | review SE | unit faces E" % [clip, tag, t, length])
		metrics["clips"][clip] = {"length_s": length, "tracks": u.anim.get_animation(clip).get_track_count(),
			"loop": u.anim.get_animation(clip).loop_mode != Animation.LOOP_NONE}


## Non-lethal hits from the front, side and back on a unit facing north: directional recoil, NO turn.
func _hit_variants() -> void:
	for from_name: String in ["N", "E", "S"]:
		var dir: Vector3 = DIRS[from_name]
		var u: MutonV1LabUnit = lab.spawn_unit(0.0)
		await _ticks(20)
		var arrow := _arrow(dir)
		var start := Engine.get_physics_frames()
		var rec := u.shoot(u._default_origin(dir), dir, false)
		var yaws := []
		for t in [0.067, 0.15, 0.35]:
			var ts := await _wait_until(start, t)
			yaws.append([snappedf(ts, 0.001), snappedf(rad_to_deg(u.rotation.y), 0.1)])
			LabMain.set_review_camera(cam, LabMain.REVIEW_YAW, BODY_T, BODY_S)
			await _shot("hit_%s_%03d.png" % [from_name, int(round(t * 100))], Vector2i(480, 560),
				"Hit from %s (unit faces N): Hit%s t=%.2f s | yaw %.0f deg (no turn)" % [from_name, rec.get("variant", "?"), ts, rad_to_deg(u.rotation.y)])
		metrics["hits"][from_name] = {"variant": rec.get("variant"), "bone": rec.get("bone"), "wound": rec.get("wound"), "yaw_samples_s_deg": yaws}
		arrow.queue_free()


func _ragdoll_tests() -> void:
	var idx := 0
	var strip_for := {"N": "front", "E": "side", "S": "back"}
	for from_name: String in DIRS:
		var dir: Vector3 = DIRS[from_name]
		var u: MutonV1LabUnit = lab.spawn_unit(0.0)
		(u.ragdoll as MutonV1Ragdoll).rng.seed = 7001 + idx
		u.rng.seed = 9001 + idx
		idx += 1
		await _ticks(20)
		var arrow := _arrow(dir)
		var rep := {}
		u.died.connect(func(r: Dictionary) -> void: rep.merge(r))
		var start_frame := Engine.get_physics_frames()
		u.die(dir)
		var strip := strip_for.has(from_name)
		var strip_times := [0.0, 0.067, 0.133, 0.25, 0.4, 0.6, 1.0, 1.8]
		while not rep.has("settle_time_s") and Engine.get_physics_frames() - start_frame < 420:
			var t_s := (Engine.get_physics_frames() - start_frame) / 60.0
			if strip and not strip_times.is_empty() and t_s >= strip_times[0] - 1e-4:
				LabMain.set_review_camera(cam, LabMain.REVIEW_YAW, Vector3(0, 0.8, 0), 4.3)
				await _shot("fall_%s_%03d.png" % [from_name, int(round(strip_times[0] * 100))], Vector2i(520, 520),
					"Lethal hit from %s (%s; unit faced N): Death%s, twist %+.2f rad/s | t = %.2f s (hand-off 0.13 s)" % [from_name, strip_for[from_name], u.death_variant, u.death_twist_radps, t_s])
				strip_times.pop_front()
			await get_tree().physics_frame
		rep["from"] = from_name
		rep["frames_to_freeze"] = Engine.get_physics_frames() - start_frame
		await _ticks(160)
		var flags := _flags(rep)
		rep["exploded"] = flags[0]
		rep["interpenetration"] = flags[1]
		metrics["ragdoll_tests"].append(rep)
		LabMain.set_top_camera(cam, Vector3.ZERO, 6.0)
		var line1 := "Shot from %s -> falls %s | Death%s, twist %+.2f rad/s, chest yaw %+.0f deg in 0.5 s | settled %.2f s (%s)" % [from_name, _opposite(from_name), rep.get("variant", "?"), rep.get("twist_radps", 0.0), rep.get("chest_yaw_first_0p5s_deg", 0.0), rep.get("settle_time_s", -1.0), rep.get("settle_reason", "?")]
		var line2 := "past tile edge: joints %.2f m | bodies %.2f m | mesh %.2f m | align %.2f" % [rep.get("joint_outside_tile_m", -1.0), rep.get("shape_outside_tile_m", -1.0), rep.get("mesh_outside_tile_m", -1.0), rep.get("fall_alignment", -9.0)]
		var line3 := "peak %.1f m/s | joint gap max %.1f cm | jitter %+.1f deg, spin %+.2f | %s" % [rep.get("max_body_speed_mps", -1.0), rep.get("max_joint_separation_m", -1.0) * 100.0, rep.get("push_jitter_deg", 0.0), rep.get("spin_added_radps", 0.0), "EXPLODED" if flags[0] else "stable"]
		await _shot("ragdoll_%s_top.png" % from_name, Vector2i(760, 760), "%s\n%s\n%s\n(top view, north up, 2 m tiles, 0.5 m sub-grid)" % [line1, line2, line3])
		LabMain.set_review_camera(cam, LabMain.REVIEW_YAW, Vector3(rep["pelvis_xz"][0], 0.3, rep["pelvis_xz"][1]), 3.9)
		await _shot("ragdoll_%s_review.png" % from_name, Vector2i(640, 520), "Shot from %s | corpse, review SE | wound decal + splatter + pool" % from_name)
		arrow.queue_free()


func _flags(rep: Dictionary) -> Array:
	# opus-v2: the floor-dip criterion is -8 cm (was -5 cm): the 1.3 m wide chest box (shoulder shells) dips 5.3-5.8 cm for a
	# tick or two when its edge hits the floor at 4-5 m/s in a backward fall and is pushed out at once (lowest_body* in the
	# report); speed, joint-gap and NaN criteria unchanged
	var exploded: bool = rep.get("nan", false) or rep.get("max_body_speed_mps", 0.0) > 11.0 \
		or rep.get("max_joint_separation_m", 0.0) > 0.05 or rep.get("lowest_shape_y_during_m", 0.0) < -0.08 \
		or rep.get("lowest_shape_y_final_m", 0.0) < -0.03
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


## Thin red line along the shot, ending at the hit point.
func _ray_line(from: Vector3, to: Vector3) -> Node3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	var len := from.distance_to(to)
	box.size = Vector3(0.008, 0.008, len)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.15, 0.1)
	box.material = mat
	mi.mesh = box
	mi.layers = 1 << 3
	lab.add_child(mi)
	mi.global_transform = Transform3D(Basis.looking_at((to - from).normalized(), Vector3.UP), (from + to) * 0.5)
	return mi


func _bone_pos(u: LabUnit, bone: String, toward := "", k := 0.5) -> Vector3:
	var sk := u.skeleton
	var p := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin
	if toward != "":
		var q := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(toward)).origin
		p = p.lerp(q, k)
	return p


## Hit-point gallery: each shot is ray-cast against the skinned mesh; the decal and the spray sit where it lands.
func _shot_gallery() -> void:
	var items := [
		["head", "N", "head", "", 0.0, Vector3(0, 0.12, 0)], ["head", "E", "head", "", 0.0, Vector3(0, 0.12, 0)],
		["torso", "N", "spine_03", "", 0.0, Vector3(0, 0.02, 0)], ["torso", "S", "spine_03", "", 0.0, Vector3(0, 0.02, 0)],
		["torso", "NW", "spine_02", "", 0.0, Vector3(0, 0.0, 0)],
		["arm", "W", "lowerarm_l", "hand_l", 0.45, Vector3.ZERO], ["arm", "E", "upperarm_r", "lowerarm_r", 0.5, Vector3.ZERO],
		["leg", "N", "thigh_l", "calf_l", 0.5, Vector3.ZERO], ["leg", "E", "calf_r", "foot_r", 0.35, Vector3.ZERO],
		["leg", "S", "thigh_r", "calf_r", 0.3, Vector3.ZERO],
	]
	for it: Array in items:
		var region: String = it[0]
		var from_name: String = it[1]
		var dir: Vector3 = DIRS[from_name]
		var u: MutonV1LabUnit = lab.spawn_unit(0.0)
		await _ticks(10)
		u.pose_at("Idle", 0.0)
		await _ticks(2)
		var target := _bone_pos(u, it[2], it[3], it[4]) + (it[5] as Vector3)
		var origin := target - dir * 2.5
		var start := Engine.get_physics_frames()
		var rec := u.shoot(origin, dir, false)
		var hp := Vector3(rec["point"][0], rec["point"][1], rec["point"][2])
		var line := _ray_line(origin, hp)
		var side := dir.cross(Vector3.UP).normalized()
		var eye := hp - dir * 0.85 + side * 0.55 + Vector3.UP * 0.30
		if region == "leg":
			eye = hp - dir * 0.9 + side * 0.5 + Vector3.UP * 0.55
		await _wait_until(start, 0.05)
		_persp(hp, eye, 38.0)
		await _shot("shot_%s_%s.png" % [region, from_name], Vector2i(520, 520),
			"%s from %s: hit %s (%s), %s, incidence %.0f deg | spray t=0.05 s" % [region, from_name, rec["bone"], "MISS" if rec["miss"] else "mesh ray", rec["wound"], rec["incidence_deg"]])
		await _wait_until(start, 0.6)
		_persp(hp, eye, 38.0)
		await _shot("shot_%s_%s_decal.png" % [region, from_name], Vector2i(520, 520),
			"%s from %s: wound decal on %s after the Hit clip (follows the bone)" % [region, from_name, rec["bone"]])
		rec["region"] = region
		rec["from"] = from_name
		var hb := _bone_pos(u, rec["bone"])
		rec["decal_offset_from_bone_m"] = snappedf(hb.distance_to(hp), 0.001)
		metrics["gallery"].append(rec)
		line.queue_free()


## Spray / wound close-ups for shots from the front, side and back (user feedback 2026-10-02): yellow dot = spray origin
## (the ray-cast skin point nudged 4 mm out), red line = the shot; side-on camera from the shooter's side so the spray
## heading back toward the shooter can be compared with the shot, then the wound + drips at full size after 2 s.
func _spray_closeups() -> void:
	var rows := {}
	for from_name: String in ["N", "E", "S"]:
		var dir: Vector3 = DIRS[from_name]
		var u: MutonV1LabUnit = lab.spawn_unit(0.0)
		await _ticks(10)
		u.pose_at("Idle", 0.0)
		await _ticks(2)
		var target := (_bone_pos(u, "spine_02") + Vector3(0, 0.0, -0.03)) if from_name == "E" else (_bone_pos(u, "spine_03") + Vector3(0.05, 0.02, 0))
		var origin := target - dir * 2.5
		var start := Engine.get_physics_frames()
		var rec := u.shoot(origin, dir, false)
		var sp := Vector3(rec["spray_origin"][0], rec["spray_origin"][1], rec["spray_origin"][2])
		var hp := Vector3(rec["point"][0], rec["point"][1], rec["point"][2])
		var hn := Vector3(rec["normal"][0], rec["normal"][1], rec["normal"][2])
		var line := _ray_line(origin, hp)
		var dot := _marker(sp)
		var side := dir.cross(Vector3.UP).normalized()
		var eye := sp + side * 1.35 + Vector3.UP * 0.3 - dir * 0.55
		for t in [0.03, 0.08, 0.15]:
			var ts := await _wait_until(start, t)
			_persp(sp - dir * 0.3, eye, 42.0)
			await _shot("spray_%s_%03d.png" % [from_name, int(round(t * 100))], Vector2i(480, 480),
				"Shot from %s (red line) -> %s: spray from the skin point (yellow) BACK toward the shooter, t = %.2f s" % [from_name, rec["bone"], ts])
		dot.queue_free()
		line.queue_free()
		await _wait_until(start, 2.0)
		var bx := _bone_xf(u, rec["bone"])
		var rc := {"bone": rec["bone"], "local_point": bx.affine_inverse() * hp, "local_normal": (bx.basis.inverse() * hn).normalized()}
		_look_at_hit(u, rc, 1.0)
		await _shot("wound_%s.png" % from_name, Vector2i(480, 480), "Shot from %s: %s wound + drips at full size (t = 2 s)" % [from_name, rec["wound"]])
		LabMain.set_review_camera(cam, LabMain.REVIEW_YAW + (0.0 if from_name == "S" else PI), BODY_T, BODY_S)
		await _shot("wound_%s_review.png" % from_name, Vector2i(400, 460), "Shot from %s: the same wound at review zoom" % from_name)
		var nudge := sp.distance_to(hp)
		rows[from_name] = {"bone": rec["bone"], "wound": rec["wound"], "spray_origin": rec["spray_origin"], "hit_point": rec["point"],
			"normal": rec["normal"], "spray_dir": rec["spray_dir"], "nudge_m": snappedf(nudge, 0.0001),
			"origin_outside_surface": (sp - hp).dot(hn) > 0.0, "incidence_deg": rec["incidence_deg"],
			"spray_toward_shooter_cos": snappedf(Vector3(rec["spray_dir"][0], rec["spray_dir"][1], rec["spray_dir"][2]).dot(-dir), 0.001)}
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	metrics["spray_closeups"] = rows


func _marker(p: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.024
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.1)
	mat.no_depth_test = true
	sm.material = mat
	mi.mesh = sm
	mi.layers = 1 << 3
	lab.add_child(mi)
	mi.global_position = p
	return mi


## Decals stack to the cap (blood.json wound_decals.max_per_unit), then follow the body through the ragdoll.
func _stack_and_die() -> void:
	var u: MutonV1LabUnit = lab.spawn_unit(0.0)
	await _ticks(20)
	var seq := [["N", "spine_03", Vector3(0.08, 0.06, 0)], ["NE", "head", Vector3(0, 0.12, 0)], ["W", "lowerarm_l", Vector3.ZERO],
		["N", "thigh_l", Vector3(0.0, 0, 0)], ["E", "upperarm_r", Vector3.ZERO], ["NW", "spine_02", Vector3(-0.06, 0, 0)],
		["N", "spine_03", Vector3(-0.1, 0.1, 0)], ["E", "calf_r", Vector3.ZERO]]
	var counts := []
	for s: Array in seq:
		u.pose_at("Idle", 0.0)
		await _ticks(2)
		var dir: Vector3 = DIRS[s[0]]
		var target := _bone_pos(u, s[1]) + (s[2] as Vector3)
		u.shoot(target - dir * 2.5, dir, false)
		await _ticks(30)
		counts.append((u.blood as MutonV1Blood).wounds.size())
	u.play("Idle")
	await _ticks(100)
	LabMain.set_review_camera(cam, LabMain.REVIEW_YAW, BODY_T, 2.9)
	await _shot("stack_alive_SE.png", Vector2i(560, 640), "8 shots from N / NE / W / E / NW: %d wound decals kept (cap %d), Idle playing" % [(u.blood as MutonV1Blood).wounds.size(), int(u.blood_profile["wound_decals"]["max_per_unit"])])
	LabMain.set_review_camera(cam, LabMain.REVIEW_YAW + PI, BODY_T, 2.9)
	await _shot("stack_alive_NW.png", Vector2i(560, 640), "same unit from NW")
	var rep := {}
	u.died.connect(func(r: Dictionary) -> void: rep.merge(r))
	var dir: Vector3 = DIRS["E"]
	u.shoot(_bone_pos(u, "spine_03") - dir * 2.5, dir, true)
	var start := Engine.get_physics_frames()
	while not rep.has("settle_time_s") and Engine.get_physics_frames() - start < 420:
		await get_tree().physics_frame
	await _ticks(60)
	metrics["stack"] = {"wounds_after_each_shot": counts, "cap": u.blood_profile["wound_decals"]["max_per_unit"],
		"final_wounds": (u.blood as MutonV1Blood).wounds.size(), "death": {"variant": rep.get("variant"), "twist_radps": rep.get("twist_radps"),
		"settle_time_s": rep.get("settle_time_s")}}
	var pelvis := Vector3(rep["pelvis_xz"][0], 0.0, rep["pelvis_xz"][1])
	_persp(pelvis + Vector3(-0.1, 0.1, 0.0), pelvis + Vector3(1.3, 1.4, 1.3), 36.0)
	await _shot("corpse_decals_SE.png", Vector2i(900, 640), "Corpse after a lethal shot from E: the wound decals stayed on their bones through the ragdoll; pool + splatter on the floor only")
	_persp(pelvis + Vector3(-0.1, 0.1, 0.0), pelvis + Vector3(-1.3, 1.4, -1.3), 36.0)
	await _shot("corpse_decals_NW.png", Vector2i(900, 640), "same corpse from NW")
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL


## Battlescape zoom: 192 px viewport, 5.9 m ortho height -> ~33 px/m, the Snakeman ~60 px tall (the PCK sprite at OXCE 2x).
func _bzoom_spray() -> void:
	for cfg: Array in [["v1", Vector3(-1, 0, 1).normalized(), "shot from NE (entry on the far side from the SE camera)"],
			["cam", Vector3(-1, 0, -1).normalized(), "shot from SE (entry facing the SE camera)"]]:
		var dir: Vector3 = cfg[1]
		var u: MutonV1LabUnit = lab.spawn_unit(0.0)
		await _ticks(10)
		u.pose_at("Idle", 0.0)
		LabMain.set_review_camera(cam, LabMain.REVIEW_YAW, Vector3(-0.2, 1.05, 0.2), 5.9)
		await _ticks(2)
		var base := await _shot("bzoom_%s_pre.png" % cfg[0], Vector2i(192, 192), "")
		var start := Engine.get_physics_frames()
		u.shoot(u._default_origin(dir), dir, false)
		var counts := []
		for t in [0.05, 0.15, 0.25]:
			await _wait_until(start, t)
			var img := await _shot("bzoom_%s_%03d.png" % [cfg[0], int(round(t * 100))], Vector2i(192, 192), "")
			counts.append(_blood_pixels(img, base))
		metrics["spray_bzoom"][cfg[0]] = {"blood_pixels_at_0.05_0.15_0.25_s": counts, "viewport_px": 192, "ortho_m": 5.9,
			"origin": "hit point on the body, along the shot: " + cfg[2]}

## Orange-brown blood pixels: changed by > 0.10 vs the pre-shot frame and orange (hue 12-48 deg, saturation > 0.35).
static func _blood_pixels(img: Image, base: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var c0 := base.get_pixel(x, y)
			if maxf(absf(c.r - c0.r), maxf(absf(c.g - c0.g), absf(c.b - c0.b))) < 0.10:
				continue
			var h := c.h * 360.0
			if h >= 12.0 and h <= 48.0 and c.s > 0.35 and c.v > 0.12:
				n += 1
	return n


## Hit then fall with drips: four non-lethal hits on head / torso / forearm / serpent (runs grow down the surface over
## ~1.5 s), close-ups of each, then a lethal shot from behind; close-ups follow each hit through the fall (the decal frame
## is stored in its bone at the hit and re-evaluated on the corpse).
func _drip_sequence() -> void:
	var u: MutonV1LabUnit = lab.spawn_unit(0.0)
	await _ticks(20)
	var seq := [["head", "N", "head", Vector3(0.05, 0.12, 0)], ["torso", "N", "spine_03", Vector3(-0.06, 0.02, 0)],
		["forearm", "E", "lowerarm_r", Vector3.ZERO], ["leg", "E", "thigh_r", Vector3.ZERO]]
	var start := Engine.get_physics_frames()
	var recs := []
	for i in seq.size():
		await _wait_until(start, 0.1 * i)
		var s: Array = seq[i]
		var dir: Vector3 = DIRS[s[1]]
		var target := _bone_pos(u, s[2]) + (s[3] as Vector3)
		var r := u.shoot(target - dir * 2.5, dir, false)
		var hp := Vector3(r["point"][0], r["point"][1], r["point"][2])
		var hn := Vector3(r["normal"][0], r["normal"][1], r["normal"][2])
		var bx := _bone_xf(u, r["bone"])
		recs.append({"part": s[0], "from": s[1], "bone": r["bone"], "point": r["point"], "normal": r["normal"],
			"local_point": bx.affine_inverse() * hp, "local_normal": (bx.basis.inverse() * hn).normalized()})
	# growth on the head hit
	for t in [0.4, 0.9, 1.9]:
		var ts := await _wait_until(start, t)
		_look_at_hit(u, recs[0], 0.75)
		await _shot("drip_head_%03d.png" % int(round(t * 100)), Vector2i(480, 480), "Head hit from N: runs growing down the face, t = %.2f s after the shot" % ts)
	await _wait_until(start, 2.0)
	for rc: Dictionary in recs.slice(1):
		_look_at_hit(u, rc, 0.8)
		await _shot("drip_%s_alive.png" % rc["part"], Vector2i(480, 480), "%s hit from %s (%s): runs down the surface (world down at the hit), grown" % [rc["part"], rc["from"], rc["bone"]])
	var rep := {}
	u.died.connect(func(r: Dictionary) -> void: rep.merge(r))
	var dir: Vector3 = DIRS["N"]           # from the front: he falls on his back, so the front wounds stay in view
	var t_l := Engine.get_physics_frames()
	u.shoot(_bone_pos(u, "spine_03") + Vector3(0.12, 0.0, 0.0) - dir * 2.5, dir, true)
	for t in [0.13, 0.4, 1.0]:
		var ts := await _wait_until(t_l, t)
		LabMain.set_review_camera(cam, LabMain.REVIEW_YAW + PI, Vector3(0, 0.8, 0.3), 4.0)
		await _shot("drip_fall_%03d.png" % int(round(t * 100)), Vector2i(560, 560), "Lethal shot from N (front) | t = %.2f s: Death%s; runs ride on their bones | review NW" % [ts, u.death_variant])
	while not rep.has("settle_time_s") and Engine.get_physics_frames() - t_l < 420:
		await get_tree().physics_frame
	await _ticks(30)
	var seen := []
	for rc: Dictionary in recs:
		var vis := _look_at_hit(u, rc, 0.9)
		seen.append([rc["part"], vis])
		if not vis:
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			LabMain.set_review_camera(cam, LabMain.REVIEW_YAW + PI, _bone_xf(u, rc["bone"]).origin, 1.6)
		await _shot("drip_%s_corpse.png" % rc["part"], Vector2i(480, 480), "Corpse: %s wound + runs still on %s after the fall%s" % [rc["part"], rc["bone"], "" if vis else " (decal faces the floor: review view)"])
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	LabMain.set_top_camera(cam, Vector3.ZERO, 6.0)
	await _shot("drip_corpse_top.png", Vector2i(640, 640), "Corpse, top view (settled %.2f s)" % rep.get("settle_time_s", -1.0))
	for rc: Dictionary in recs:
		rc.erase("local_point")
		rc.erase("local_normal")
	metrics["drips"] = {"hits": recs, "corpse_closeup_facing_up": seen, "death": {"variant": rep.get("variant"), "twist_radps": rep.get("twist_radps"),
		"chest_yaw_first_0p5s_deg": rep.get("chest_yaw_first_0p5s_deg"), "settle_time_s": rep.get("settle_time_s")},
		"drip_decals": _count_drips(u)}


func _bone_xf(u: LabUnit, bone: String) -> Transform3D:
	return u.skeleton.global_transform * u.skeleton.get_bone_global_pose(u.skeleton.find_bone(bone))


## Perspective close-up of a stored hit, looking at the decal along its (current) surface normal from a little above.
## Returns false when the decal faces the floor (camera clamped above the floor).
func _look_at_hit(u: LabUnit, rc: Dictionary, dist: float, up := 0.25) -> bool:
	var bx := _bone_xf(u, rc["bone"])
	var p: Vector3 = bx * (rc["local_point"] as Vector3)
	var n: Vector3 = (bx.basis * (rc["local_normal"] as Vector3)).normalized()
	var eye := p + n * dist + Vector3.UP * up
	var ok := eye.y > 0.2
	eye.y = maxf(eye.y, 0.35)
	_persp(p + Vector3.DOWN * 0.08, eye, 40.0)
	return ok


func _count_drips(u: MutonV1LabUnit) -> int:
	var n := 0
	for w: Node in (u.blood as MutonV1Blood).wounds:
		if is_instance_valid(w):
			for c in w.get_children():
				if String(c.name).begins_with("DripDecal"):
					n += 1
	return n
