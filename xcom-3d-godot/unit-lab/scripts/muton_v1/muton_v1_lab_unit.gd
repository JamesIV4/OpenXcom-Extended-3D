## The Muton opus-v1 (copy of the Sectoid opus-v4 lab file) in the unit lab (units_opus55). Same contract as LabUnit; differences:
##  * looping clips are exported as "<name>-loop" (Godot imports them as Idle / IdleArmed / Walk / WalkArmed, looping);
##    play("Idle") etc. work with either spelling;
##  * user decisions 2026-10-02 (snappy death, late-turn twist, hit-point blood):
##    - NO animated turn toward the attacker. Hit and Death are directional: the variant (Front / Back / Left / Right)
##      comes from the shot's travel direction relative to the facing (ragdoll.handoff.variant_rule);
##    - Death<variant> is a 0.133 s recoil, then the ragdoll takes over with that variant's velocities, a small push
##      along the shot and a whole-body TWIST about the vertical toward the shooter (0 for a frontal shot, full from
##      behind: he tries to turn round too late) - ragdoll.handoff.twist_toward_shooter;
##    - every shot is ray-cast against the skinned mesh: a wound Decal goes exactly where it lands (BoneAttachment3D on
##      the bone with the largest skin weight there, cull mask = this unit's own visual layer, capped) and the hit
##      spray starts at that point along the shot (blood.json wound_decals). No fixed wound overlay;
##  * MutonV1Ragdoll (variant velocities, push on several bodies, twist, per-death variation, ground-clearance lift);
##  * MutonV1Blood (spray parameters from the sidecar, wound decals);
##  * a stand-in pistol on the weapon_r socket bone, shown in the armed clips and Attack.
## model_path / visual_layer may be set before the node enters the tree.
class_name MutonV1LabUnit
extends LabUnit

const ARMED := ["IdleArmed", "WalkArmed", "IdleArmed-loop", "WalkArmed-loop", "Attack"]
const LOOPING := ["Idle", "IdleArmed", "Walk", "WalkArmed"]
## The hit spray starts on the visible (ray-cast, CPU-skinned) surface, nudged this far out along the normal, and flies
## BACK toward the shooter out of the entry wound: direction half-way between the reverse shot and the surface normal, in
## the sidecar's modest cone (user correction 2026-10-02).
const SPRAY_NUDGE_M := 0.004

var weapon: Node3D
## This unit's own VisualInstance3D layer (1-based). Wound decals only project onto it, so they never stain the floor
## (layer 1) or another unit that sits on a different layer.
var visual_layer := UNIT_VISUAL_LAYER
var hit_log: Array = []          # one record per shot: point, normal, bone, wound, variant
var death_variant := ""
var death_twist_radps := 0.0
var _mesh_cache: Array = []      # per surface [verts, bones, weights, indices]


func _init() -> void:
	model_path = "res://assets/models/units/MUTON/MUTON.opus-v1.gltf"
	var ua := OS.get_cmdline_user_args()          # another variant of this unit: -- --model res://...gltf
	var mi := ua.find("--model")
	if mi >= 0 and ua.size() > mi + 1:
		model_path = ua[mi + 1]


func _ready() -> void:
	rng.seed = 20261001
	model = (load(model_path) as PackedScene).instantiate()
	add_child(model)
	skeleton = _find(model, "Skeleton3D")
	anim = _find(model, "AnimationPlayer")
	body_mesh = _find_skinned_mesh(model)
	for s in body_mesh.mesh.get_surface_count():
		var m := body_mesh.mesh.surface_get_material(s)
		if m and m.resource_name.ends_with("skin"):
			skin_surface = s
	body_mesh.layers = layer_mask()
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	for lib_name in anim.get_animation_library_list():
		for an in anim.get_animation_library(lib_name).get_animation_list():
			var n := String(an)
			if n.ends_with("-loop") or LOOPING.has(n):
				anim.get_animation_library(lib_name).get_animation(an).loop_mode = Animation.LOOP_LINEAR
	anim.animation_finished.connect(_on_v3_clip_finished)
	_death_len = anim.get_animation(_clip("Death")).length
	var base := model_path.get_basename()
	ragdoll_profile = JSON.parse_string(FileAccess.get_file_as_string(base + ".ragdoll.json"))
	blood_profile = JSON.parse_string(FileAccess.get_file_as_string(base + ".blood.json"))
	var rd := MutonV1Ragdoll.new()
	rd.rng.seed = rng.seed + 7
	ragdoll = rd
	ragdoll.name = "RagdollController"
	ragdoll.extra_collision_exceptions = extra_collision_exceptions + ragdoll_profile.get("collision_exceptions", [])
	add_child(ragdoll)
	if not build_ragdoll_on_death:
		ragdoll.build(skeleton, ragdoll_profile)
	ragdoll.frozen.connect(_on_ragdoll_frozen)
	blood = MutonV1Blood.new()
	blood.name = "Blood"
	add_child(blood)
	blood.setup(blood_profile, model_path.get_base_dir(), fx_root if fx_root else get_parent())
	if skeleton.find_bone("weapon_r") >= 0:
		_make_weapon()
	var mesh := body_mesh.mesh
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		_mesh_cache.append([arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_BONES], arr[Mesh.ARRAY_WEIGHTS], arr[Mesh.ARRAY_INDEX]])


func layer_mask() -> int:
	return 1 << (visual_layer - 1)


## Stand-in one-handed weapon (dark grey grip + slide) on the socket bone: +Y barrel, +Z top.
func _make_weapon() -> void:
	var att := BoneAttachment3D.new()
	att.name = "WeaponSocket"
	att.bone_name = "weapon_r"
	skeleton.add_child(att)
	weapon = Node3D.new()
	att.add_child(weapon)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.62, 0.64)      # Metals rule 2026-10-02: steel reflectance, metallic 1, machined
	mat.metallic = 1.0
	mat.roughness = 0.35
	for part: Array in [[Vector3(0.035, 0.05, 0.10), Vector3(0, 0.0, -0.03)], [Vector3(0.03, 0.17, 0.045), Vector3(0, 0.06, 0.035)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[0]
		bm.material = mat
		mi.mesh = bm
		mi.position = part[1]
		mi.layers = layer_mask()
		weapon.add_child(mi)
	weapon.visible = false


func _clip(name: String) -> String:
	if anim == null or anim.has_animation(name):
		return name
	if anim.has_animation(name + "-loop"):
		return name + "-loop"
	if name.ends_with("-loop") and anim.has_animation(name.trim_suffix("-loop")):
		return name.trim_suffix("-loop")
	return name


func play(clip: String) -> void:
	if dead or _dying:
		return
	var c := _clip(clip)
	anim.play(c)
	if weapon:
		weapon.visible = ARMED.has(c)


func pose_at(clip: String, t: float) -> void:
	var c := _clip(clip)
	anim.play(c)
	anim.seek(t, true)
	anim.pause()
	if weapon:
		weapon.visible = ARMED.has(c)


## Shot travel direction (world) in the unit frame: x = unit right, y = unit forward (the unit faces local -Z).
func shot_local(dir: Vector3) -> Vector2:
	var l := global_basis.inverse() * dir
	var v := Vector2(l.x, -l.z)
	return v.normalized() if v.length() > 1e-6 else Vector2(0, -1)


## ragdoll.handoff.variant_rule
func variant_of(dir: Vector3) -> String:
	var t := shot_local(dir)
	if t.y <= -0.7071:
		return "Front"
	if t.y >= 0.7071:
		return "Back"
	return "Left" if t.x > 0.0 else "Right"


## ragdoll.handoff.twist_toward_shooter: signed vertical angular velocity (rad/s, +Y = counter-clockwise from above).
func twist_of(dir: Vector3) -> float:
	var tw: Dictionary = ragdoll_profile["handoff"].get("twist_toward_shooter", {})
	if tw.is_empty():
		return 0.0
	var t := shot_local(dir)
	var k_ang := acos(clampf(-t.y, -1.0, 1.0)) / PI          # 0 frontal .. 1 from behind
	var sgn := 1.0 if t.x > 0.0175 else (-1.0 if t.x < -0.0175 else (1.0 if rng.randf() < 0.5 else -1.0))
	return sgn * k_ang * float(tw["max_delta_angular_velocity_radps"])


## Ray vs the CPU-skinned mesh (both surfaces). Returns {} on a miss, else point, normal (facing the shooter), bone
## (largest barycentric skin weight at the hit), distance, triangle.
func raycast_body(origin: Vector3, dir: Vector3) -> Dictionary:
	var d := dir.normalized()
	var skin := body_mesh.skin
	var bind_xf: Array[Transform3D] = []
	var bind_bone := PackedInt32Array()
	for i in skin.get_bind_count():
		var bone := skin.get_bind_bone(i)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(i))
		bind_bone.append(bone)
		bind_xf.append(body_mesh.global_transform * skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(i))
	var best_t := INF
	var best := {}
	for sc: Array in _mesh_cache:
		var verts: PackedVector3Array = sc[0]
		var bones: PackedInt32Array = sc[1]
		var weights: PackedFloat32Array = sc[2]
		var idx: PackedInt32Array = sc[3]
		var n := bones.size() / verts.size()
		var P := PackedVector3Array()
		P.resize(verts.size())
		for vi in verts.size():
			var p := Vector3.ZERO
			for k in n:
				var w := weights[vi * n + k]
				if w > 0.0:
					p += (bind_xf[bones[vi * n + k]] * verts[vi]) * w
			P[vi] = p
		for ti in range(0, idx.size(), 3):
			var a := P[idx[ti]]
			var e1 := P[idx[ti + 1]] - a
			var e2 := P[idx[ti + 2]] - a
			var pv := d.cross(e2)
			var det := e1.dot(pv)
			if absf(det) < 1e-12:
				continue
			var inv := 1.0 / det
			var tv := origin - a
			var u := tv.dot(pv) * inv
			if u < 0.0 or u > 1.0:
				continue
			var qv := tv.cross(e1)
			var v := d.dot(qv) * inv
			if v < 0.0 or u + v > 1.0:
				continue
			var t := e2.dot(qv) * inv
			if t <= 1e-4 or t >= best_t:
				continue
			best_t = t
			var nrm := e1.cross(e2).normalized()
			if nrm.dot(d) > 0.0:
				nrm = -nrm
			var acc := {}
			var bary := [1.0 - u - v, u, v]
			for c in 3:
				var vi := idx[ti + c]
				for k in n:
					var w := weights[vi * n + k] * float(bary[c])
					if w > 0.0:
						var bn := bind_bone[bones[vi * n + k]]
						acc[bn] = acc.get(bn, 0.0) + w
			var top := -1
			var top_w := -1.0
			for bn: int in acc:
				if acc[bn] > top_w:
					top_w = acc[bn]
					top = bn
			best = {"point": origin + d * t, "normal": nrm, "bone": skeleton.get_bone_name(top), "distance_m": t}
	return best


## One shot travelling along `dir` from `origin` (world). Places the wound decal and the spray at the hit point, then
## plays the directional Hit (non-lethal) or starts the snappy Death. Returns the hit record.
func shoot(origin: Vector3, dir: Vector3, lethal: bool) -> Dictionary:
	if dead or _dying:
		return {}
	var d := dir.normalized()
	var t0 := Time.get_ticks_usec()
	var h := raycast_body(origin, d)
	var rec := {"lethal": lethal, "ray_ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)}
	if h.is_empty():
		h = {"point": chest_point(d), "normal": -d, "bone": "spine_03", "miss": true}
	var cos_in := clampf(-(h["normal"] as Vector3).dot(d), -1.0, 1.0)
	var grazing := rad_to_deg(acos(cos_in)) > 50.0
	var kind := "wound03" if lethal else ("wound02" if grazing else ("wound01" if rng.randf() < 0.6 else "wound04"))
	blood.wound_at(skeleton, h["bone"], h["point"], h["normal"], d, layer_mask(), kind)
	# Real droplets start just outside the raycast surface, without the old billboard depth pull.
	var spray_origin: Vector3 = h["point"] + (h["normal"] as Vector3) * SPRAY_NUDGE_M
	var spray_dir := (-d + (h["normal"] as Vector3)).normalized()                         # back toward the shooter
	if spray_dir.length() < 0.5:
		spray_dir = -d
	blood.spray(spray_origin, spray_dir)
	rec.merge({"point": _r3(h["point"]), "normal": _r3(h["normal"]), "bone": h["bone"], "wound": kind, "spray_origin": _r3(spray_origin),
		"spray_dir": _r3(spray_dir), "shot_dir": _r3(d),
		"incidence_deg": snappedf(rad_to_deg(acos(cos_in)), 0.1), "miss": h.get("miss", false), "variant": variant_of(d)})
	hit_log.append(rec)
	if lethal:
		_die_now(d)
	else:
		_hit_now(d)
	return rec


static func _r3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


## Aim point at chest height in front of the shooter's side (for callers that only know the direction).
func _default_origin(d: Vector3) -> Vector3:
	var chest := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("spine_03")).origin
	return chest + Vector3.UP * 0.05 - d * 3.0


func hit(attack_dir: Vector3) -> void:
	var d := attack_dir.normalized()
	shoot(_default_origin(d), d, false)


func die(attack_dir: Vector3) -> void:
	var d := Vector3(attack_dir.x, 0.0, attack_dir.z).normalized()
	shoot(_default_origin(d), d, true)


func _hit_now(d: Vector3) -> void:
	var c := _clip("Hit" + variant_of(d))
	if not anim.has_animation(c):
		c = _clip("Hit")
	anim.play(c)
	anim.seek(0.0, true)
	if weapon:
		weapon.visible = false


func _die_now(dir: Vector3) -> void:
	if weapon:
		weapon.visible = false
	var d := Vector3(dir.x, 0.0, dir.z).normalized()
	_attack_dir = d
	_tile_center = global_position
	death_variant = variant_of(d)
	death_twist_radps = twist_of(d)
	var c := _clip("Death" + death_variant)
	if not anim.has_animation(c):
		c = _clip("Death")
	_death_len = anim.get_animation(c).length
	var rd := ragdoll as MutonV1Ragdoll
	rd.variant = death_variant
	rd.twist_radps = death_twist_radps
	anim.play(c)
	anim.seek(0.0, true)
	_dying = true
	_death_t = 0.0
	blood.splatter(_tile_center, d, rng)


func _on_ragdoll_frozen(report: Dictionary) -> void:
	# root 2026-10-02: settle-time depenetration (the safety net behind the fitted finger / coil shapes)
	var dep: Dictionary = ragdoll_profile.get("settle_and_freeze", {}).get("depenetration", {})
	var lo := 1e9
	for v in skinned_vertices():
		lo = minf(lo, v.y)
	report["mesh_min_y_before_lift_m"] = snappedf(lo - _tile_center.y, 0.0001)
	report["depenetration_lift_m"] = 0.0
	if not dep.is_empty() and lo < _tile_center.y:
		var lift := minf(_tile_center.y - lo, float(dep.get("max_lift_m", 0.05)))
		global_position += Vector3.UP * lift
		report["depenetration_lift_m"] = snappedf(lift, 0.0001)
	report["variant"] = death_variant
	report["twist_radps"] = snappedf(death_twist_radps, 0.001)
	report["yaw_deg_unit"] = snappedf(rad_to_deg(rotation.y), 0.1)
	report["hits"] = hit_log.duplicate(true)
	super._on_ragdoll_frozen(report)


func _on_v3_clip_finished(clip: StringName) -> void:
	if String(clip).begins_with("Hit") and not dead and not _dying:
		play("Idle")
