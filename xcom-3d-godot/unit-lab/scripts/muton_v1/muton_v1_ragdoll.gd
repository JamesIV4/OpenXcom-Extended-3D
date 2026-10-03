## Muton opus-v1 (copy of the Sectoid opus-v4 lab file) ragdoll (units_opus55): copy of SectoidV3Ragdoll - UnitRagdoll plus:
##  * handoff.extra_push.bones: the attack-direction delta-v goes to spine_02, spine_03 and head;
##  * handoff.variation: per-death random yaw jitter of the push and a small vertical spin;
##  * collision_exceptions from the JSON (only pairs that overlap at rest / hand-off);
##  * ground-clearance rule: if any collision shape is under the floor on the hand-off frame, lift all bodies by that
##    depth + 2 mm before they are released (a depenetration launch is worse than a 2 mm drop);
##  * snappy directional death (user 2026-10-02): `variant` picks handoff.variants[variant] velocities (Death<variant>);
##  * late turn toward the shooter as physics (user 2026-10-02, whole body): `twist_radps` is added as a rigid rotation
##    of ALL bodies about the vertical through their mass centre (angular += up*w, linear += (up*w) x r), so the joints
##    are not strained and the push momentum is unchanged. The chest yaw is logged for 0.5 s and to the freeze.
class_name MutonV1Ragdoll
extends UnitRagdoll

var rng := RandomNumberGenerator.new()
var last_push_dir := Vector3.ZERO
var variant := "Front"
var twist_radps := 0.0
var _yaw_int := 0.0
var _com0 := Vector3.ZERO
var _shot_h := Vector3.ZERO
var _tail: Array = []   # per tick {bone: [|v|, |w|]} for the last 30 ticks (settle diagnostics)


## settle_and_freeze.assist (opus-v3): once the fall is over (sim time >= after_s and every body slower than
## below_mps), raise every body's damping so the residual contact jitter of light limbs dies out instead of
## running into the 3 s cap (s3 lab: an arm capsule pinned between the torso and the floor kept rolling at 1 rad/s).
var _assisted := false
var _assisted_late := false


func _physics_process(delta: float) -> void:
	if state == State.SIMULATING and not _assisted:
		var a: Dictionary = profile["settle_and_freeze"].get("assist", {})
		if not a.is_empty() and _sim_time >= float(a["after_s"]):
			var fast := false
			for pb: PhysicalBone3D in bodies.values():
				var v: Vector3 = PhysicsServer3D.body_get_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
				if v.length() >= float(a["below_mps"]):
					fast = true
					break
			if not fast:
				_assisted = true
				for pb: PhysicalBone3D in bodies.values():
					pb.linear_damp = maxf(pb.linear_damp, float(a["linear_damp"]))
					pb.angular_damp = maxf(pb.angular_damp, float(a["angular_damp"]))
				report["settle_assist_at_s"] = snappedf(_sim_time, 0.001)
	# opus-v2: optional second, late assist stage (settle_and_freeze.assist_late): once the corpse only creeps (every body
	# slower than below_mps after after_s), raise the damping again so a slow topple / arm creep ends before the cap
	if state == State.SIMULATING and _assisted and not _assisted_late:
		var al: Dictionary = profile["settle_and_freeze"].get("assist_late", {})
		if not al.is_empty() and _sim_time >= float(al["after_s"]):
			var fast2 := false
			for pb: PhysicalBone3D in bodies.values():
				var v2: Vector3 = PhysicsServer3D.body_get_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
				if v2.length() >= float(al["below_mps"]):
					fast2 = true
					break
			if not fast2:
				_assisted_late = true
				for pb: PhysicalBone3D in bodies.values():
					pb.linear_damp = maxf(pb.linear_damp, float(al["linear_damp"]))
					pb.angular_damp = maxf(pb.angular_damp, float(al["angular_damp"]))
				report["settle_assist_late_at_s"] = snappedf(_sim_time, 0.001)
	if state == State.SIMULATING and bodies.has("spine_03"):
		var wv: Vector3 = PhysicsServer3D.body_get_state((bodies["spine_03"] as PhysicalBone3D).get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		_yaw_int += wv.y * delta
		if _sim_time <= 0.5:
			report["chest_yaw_first_0p5s_deg"] = snappedf(rad_to_deg(_yaw_int), 0.1)
		report["chest_yaw_total_deg"] = snappedf(rad_to_deg(_yaw_int), 0.1)
	if state == State.SIMULATING:
		# opus-v2 diagnostic: which body reaches the lowest point during the fall (the lab flags < -5 cm as "exploded")
		for bn: String in bodies:
			var cs: CollisionShape3D = (bodies[bn] as PhysicalBone3D).get_node("Shape")
			var xf := (bodies[bn] as PhysicalBone3D).global_transform * cs.transform
			var lo := 1e9
			var s := cs.shape
			if s is BoxShape3D:
				var h: Vector3 = (s as BoxShape3D).size * 0.5
				for sx in [-1.0, 1.0]:
					for sy in [-1.0, 1.0]:
						for sz in [-1.0, 1.0]:
							lo = minf(lo, (xf * Vector3(h.x * sx, h.y * sy, h.z * sz)).y)
			elif s is SphereShape3D:
				lo = xf.origin.y - (s as SphereShape3D).radius
			elif s is CapsuleShape3D:
				var cap := s as CapsuleShape3D
				var half := cap.height * 0.5 - cap.radius
				lo = minf((xf * Vector3(0, -half, 0)).y, (xf * Vector3(0, half, 0)).y) - cap.radius
			if lo < float(report.get("lowest_body_y_m", 1e9)):
				report["lowest_body_y_m"] = snappedf(lo, 0.0001)
				report["lowest_body"] = bn
				report["lowest_body_at_s"] = snappedf(_sim_time, 0.001)
		var row := {}
		var vmax_t := 0.0
		var vmax_b := ""
		for bone_name: String in bodies:
			var rid: RID = (bodies[bone_name] as PhysicalBone3D).get_rid()
			var v: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			var w: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
			row[bone_name] = [v.length(), w.length()]
			if v.length() > vmax_t:
				vmax_t = v.length()
				vmax_b = bone_name
		# opus-v2 diagnostic: max body speed every 0.25 s (late events vs slow creep)
		var tick := int(round(_sim_time * 60.0))
		if tick % 15 == 0:
			var tr: Array = report.get("speed_trace", [])
			tr.append([snappedf(_sim_time, 0.01), snappedf(vmax_t, 0.001), vmax_b])
			report["speed_trace"] = tr
		_tail.append(row)
		if _tail.size() > 30:
			_tail.pop_front()
	super._physics_process(delta)


func freeze(reason: String) -> void:
	var worst := {}
	for row: Dictionary in _tail:
		for bone_name: String in row:
			var cur: Array = worst.get(bone_name, [0.0, 0.0])
			worst[bone_name] = [maxf(cur[0], row[bone_name][0]), maxf(cur[1], row[bone_name][1])]
	var moving := {}
	for bone_name: String in worst:
		if worst[bone_name][0] >= 0.02 or worst[bone_name][1] >= 0.1:
			moving[bone_name] = [snappedf(worst[bone_name][0], 0.001), snappedf(worst[bone_name][1], 0.001)]
	report["last_0.5s_max_speed_by_body"] = moving
	# root gate 2026-10-02: "falls away from the shot" = the mass centre moves along the shot from the hit (hand-off) to the
	# settle (the head may swing back toward the shooter: the late turn)
	var c1 := _mass_centre()
	var dc := c1 - _com0
	report["com_settle"] = [snappedf(c1.x, 0.001), snappedf(c1.y, 0.001), snappedf(c1.z, 0.001)]
	report["com_shift_along_shot_m"] = snappedf(Vector3(dc.x, 0, dc.z).dot(_shot_h), 0.001)
	report["com_shift_horizontal_m"] = snappedf(Vector3(dc.x, 0, dc.z).length(), 0.001)
	super.freeze(reason)


func _mass_centre() -> Vector3:
	var c := Vector3.ZERO
	var m := 0.0
	for pb: PhysicalBone3D in bodies.values():
		c += pb.global_position * pb.mass
		m += pb.mass
	return c / maxf(m, 1e-6)


func start(unit_basis: Basis, push_dir: Vector3, tile_center: Vector3) -> void:
	_shot_h = Vector3(push_dir.x, 0, push_dir.z).normalized()       # the shot travel direction (before the jitter)
	var handoff: Dictionary = profile["handoff"]
	var var_cfg: Dictionary = handoff.get("variation", {})
	var saved_iv: Dictionary = handoff["initial_velocities_unit_local"]
	var variants: Dictionary = handoff.get("variants", {})
	if variants.has(variant):
		handoff["initial_velocities_unit_local"] = variants[variant]["initial_velocities_unit_local"]
	var d := Vector3(push_dir.x, 0, push_dir.z).normalized()
	var jit := deg_to_rad(float(var_cfg.get("push_yaw_jitter_deg", 0.0)))
	var jitter_deg := 0.0
	if jit > 0.0:
		var a := rng.randf_range(-jit, jit)
		jitter_deg = rad_to_deg(a)
		d = d.rotated(Vector3.UP, a)
	last_push_dir = d
	super.start(unit_basis, d, tile_center)
	handoff["initial_velocities_unit_local"] = saved_iv
	# ground clearance (bodies are already on the hand-off pose)
	var low := _shape_points_min_y() - tile_center.y
	var lift := 0.0
	if low < 0.0:
		lift = -low + 0.002
		for pb: PhysicalBone3D in bodies.values():
			pb.global_position += Vector3.UP * lift
	var push: Dictionary = handoff["extra_push"]
	var dv := _v3(push["delta_v_mps_unit_local"]).length()
	for bone_name: String in push.get("bones", []):
		if bone_name == push["bone"] or not bodies.has(bone_name):
			continue
		var pb: PhysicalBone3D = bodies[bone_name]
		pb.apply_central_impulse(d * dv * pb.mass)
	var spin := float(var_cfg.get("spin_jitter_radps", 0.0))
	var sb: String = var_cfg.get("spin_bone", "")
	var spin_v := 0.0
	if spin > 0.0 and bodies.has(sb):
		var rid: RID = (bodies[sb] as PhysicalBone3D).get_rid()
		var w: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		spin_v = rng.randf_range(-spin, spin)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, w + Vector3.UP * spin_v)
	# whole-body twist toward the shooter (rigid rotation about the vertical through the mass centre)
	if twist_radps != 0.0:
		var com := Vector3.ZERO
		var mtot := 0.0
		for pb: PhysicalBone3D in bodies.values():
			com += pb.global_position * pb.mass
			mtot += pb.mass
		com /= mtot
		var wt := Vector3.UP * twist_radps
		for pb: PhysicalBone3D in bodies.values():
			var rid := pb.get_rid()
			var r := pb.global_position - com
			r.y = 0.0
			var lv: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			var av: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
			PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, lv + wt.cross(r))
			PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, av + wt)
	_yaw_int = 0.0
	_com0 = _mass_centre()
	report["com_handoff"] = [snappedf(_com0.x, 0.001), snappedf(_com0.y, 0.001), snappedf(_com0.z, 0.001)]
	report["variant"] = variant
	report["twist_radps"] = snappedf(twist_radps, 0.001)
	report["push_dir_after_jitter"] = [snappedf(d.x, 0.001), snappedf(d.z, 0.001)]
	report["push_jitter_deg"] = snappedf(jitter_deg, 0.01)
	report["spin_added_radps"] = snappedf(spin_v, 0.001)
	report["ground_lift_m"] = snappedf(lift, 0.0001)
	report["handoff_lowest_shape_y_m"] = snappedf(low, 0.0001)
