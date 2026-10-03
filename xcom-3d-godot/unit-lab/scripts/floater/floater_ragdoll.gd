## Floater ragdoll: UnitRagdoll plus what the Floater profile adds (units_opus55, opus-v1):
##  * shape type "convex" (ConvexPolygonShape3D): the pelvis body is the rigid lower torso + skirt +
##    anti-grav ball + tube sleeve, one convex hull;
##  * handoff.extra_push.bones: the attack-direction delta-v goes to several upper-body bodies;
##  * handoff.variation: per-death random yaw jitter of the push and a small vertical spin;
##  * collision_exceptions from the JSON (cape plates vs the torso where they overlap at rest).
class_name FloaterRagdoll
extends UnitRagdoll

var rng := RandomNumberGenerator.new()
var last_push_dir := Vector3.ZERO


func _make_body(b: Dictionary) -> PhysicalBone3D:
	var s: Dictionary = b["shape"]
	if s["type"] != "convex":
		return super._make_body(b)
	var pb := PhysicalBone3D.new()
	pb.name = "PB_" + String(b["bone"])
	pb.bone_name = b["bone"]
	pb.mass = b["mass_kg"]
	pb.friction = b["friction"]
	pb.bounce = b["bounce"]
	pb.collision_layer = BODY_LAYER
	pb.collision_mask = BODY_LAYER | FLOOR_LAYER
	pb.linear_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	pb.angular_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	pb.linear_damp = b["linear_damp"]
	pb.angular_damp = b["angular_damp"]
	pb.body_offset = _xform(b["body_offset"])
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var convex := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for p: Array in s["points"]:
		pts.append(_v3(p))
	convex.points = pts
	cs.shape = convex
	pb.add_child(cs)
	pb.joint_type = JOINT_TYPES[b["joint_type"]]
	if b.has("joint_offset"):
		pb.joint_offset = _xform(b["joint_offset"])
	var jc: Dictionary = b.get("joint_constraints", {})
	for key: String in jc:
		pb.set("joint_constraints/" + key, jc[key])
	return pb


## Hand-off with the attack direction: yaw jitter, then the base push on extra_push.bone, then the
## same delta-v on the other listed bones, then a small random spin.
func start(unit_basis: Basis, push_dir: Vector3, tile_center: Vector3) -> void:
	var handoff: Dictionary = profile["handoff"]
	var var_cfg: Dictionary = handoff.get("variation", {})
	var d := Vector3(push_dir.x, 0, push_dir.z).normalized()
	var jit := deg_to_rad(float(var_cfg.get("push_yaw_jitter_deg", 0.0)))
	if jit > 0.0:
		d = d.rotated(Vector3.UP, rng.randf_range(-jit, jit))
	last_push_dir = d
	super.start(unit_basis, d, tile_center)
	var push: Dictionary = handoff["extra_push"]
	var dv := _v3(push["delta_v_mps_unit_local"]).length()
	for bone_name: String in push.get("bones", []):
		if bone_name == push["bone"] or not bodies.has(bone_name):
			continue
		var pb: PhysicalBone3D = bodies[bone_name]
		pb.apply_central_impulse(d * dv * pb.mass)
	var spin := float(var_cfg.get("spin_jitter_radps", 0.0))
	var sb: String = var_cfg.get("spin_bone", "")
	if spin > 0.0 and bodies.has(sb):
		var rid: RID = (bodies[sb] as PhysicalBone3D).get_rid()
		var w: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, w + Vector3.UP * rng.randf_range(-spin, spin))
	report["push_dir_after_jitter"] = [snappedf(d.x, 0.001), snappedf(d.z, 0.001)]


func shape_points() -> PackedVector3Array:
	var pts := super.shape_points()
	for pb: PhysicalBone3D in bodies.values():
		var cs: CollisionShape3D = pb.get_node("Shape")
		if cs.shape is ConvexPolygonShape3D:
			var xf := pb.global_transform * cs.transform
			for p in (cs.shape as ConvexPolygonShape3D).points:
				pts.append(xf * p)
	return pts
