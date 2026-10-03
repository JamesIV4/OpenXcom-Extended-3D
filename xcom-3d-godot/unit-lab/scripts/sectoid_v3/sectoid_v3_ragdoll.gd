## Sectoid opus-v3 ragdoll (units_opus55): UnitRagdoll plus what the v3 profile adds (copy of the Floater's additions):
##  * handoff.extra_push.bones: the attack-direction delta-v goes to spine_02, spine_03 and head;
##  * handoff.variation: per-death random yaw jitter of the push and a small vertical spin;
##  * collision_exceptions from the JSON (only pairs that overlap at rest / hand-off; none for the Sectoid);
##  * ground-clearance rule: if any collision shape is under the floor on the hand-off frame, lift all bodies by that
##    depth + 2 mm before they are released (a depenetration launch is worse than a 2 mm drop).
class_name SectoidV3Ragdoll
extends UnitRagdoll

var rng := RandomNumberGenerator.new()
var last_push_dir := Vector3.ZERO
var _tail: Array = []   # per tick {bone: [|v|, |w|]} for the last 30 ticks (settle diagnostics)


## settle_and_freeze.assist (opus-v3): once the fall is over (sim time >= after_s and every body slower than
## below_mps), raise every body's damping so the residual contact jitter of light limbs dies out instead of
## running into the 3 s cap (s3 lab: an arm capsule pinned between the torso and the floor kept rolling at 1 rad/s).
var _assisted := false


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
	if state == State.SIMULATING:
		var row := {}
		for bone_name: String in bodies:
			var rid: RID = (bodies[bone_name] as PhysicalBone3D).get_rid()
			var v: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			var w: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
			row[bone_name] = [v.length(), w.length()]
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
	super.freeze(reason)


func start(unit_basis: Basis, push_dir: Vector3, tile_center: Vector3) -> void:
	var handoff: Dictionary = profile["handoff"]
	var var_cfg: Dictionary = handoff.get("variation", {})
	var d := Vector3(push_dir.x, 0, push_dir.z).normalized()
	var jit := deg_to_rad(float(var_cfg.get("push_yaw_jitter_deg", 0.0)))
	var jitter_deg := 0.0
	if jit > 0.0:
		var a := rng.randf_range(-jit, jit)
		jitter_deg = rad_to_deg(a)
		d = d.rotated(Vector3.UP, a)
	last_push_dir = d
	super.start(unit_basis, d, tile_center)
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
	report["push_dir_after_jitter"] = [snappedf(d.x, 0.001), snappedf(d.z, 0.001)]
	report["push_jitter_deg"] = snappedf(jitter_deg, 0.01)
	report["spin_added_radps"] = snappedf(spin_v, 0.001)
	report["ground_lift_m"] = snappedf(lift, 0.0001)
	report["handoff_lowest_shape_y_m"] = snappedf(low, 0.0001)
