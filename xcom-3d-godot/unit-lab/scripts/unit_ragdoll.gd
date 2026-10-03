## Ragdoll death for one unit, built from its `<model>.ragdoll.json` profile (schema opus55.ragdoll.v1).
##
## Lifecycle:  build() at bind pose  ->  start() at the end of the Death lead-in clip
##             ->  physics until settled (or time cap)  ->  freeze(): bake pose, delete bodies.
##
## Reference notes (these are the things that are easy to get wrong, also in the C++ port):
##  * body_offset is the collision body's frame in the BONE-LOCAL frame of the Skeleton3D bone;
##    joint_offset is the joint frame in the BODY frame. Godot re-clamps joint_offset.origin to
##    the bone head (PhysicalBone3D::_fix_joint_offset), which is also where the JSON puts it.
##  * JointType: none 0, cone 2, hinge 3 (PhysicalBone3D.JointType). Constraint values go through
##    the "joint_constraints/<key>" properties and are in DEGREES there.
##  * Hinge angle = -(right-hand rotation of the child about joint Z), as in Bullet / GodotPhysics /
##    Jolt-in-Godot. The JSON already picked Z so that the angle reads as flexion, so the limits
##    are passed through unchanged.
##  * Joint limits are relative to the bind pose. PhysicalBone3D binds its joint frames from the
##    CURRENT poses when it enters the tree, so the bodies are created with the skeleton at rest.
##  * Joints do not disable collision between the two bodies: add explicit exceptions.
##  * Bodies start with zero velocity: the JSON's per-body hand-off velocities (unit-local) carry
##    the lead-in clip's motion into the physics.
class_name UnitRagdoll
extends Node

signal frozen(report: Dictionary)

enum State { KINEMATIC, SIMULATING, FROZEN }

const BODY_LAYER := 1   # ragdoll bodies (physics layer 1)
const FLOOR_LAYER := 2  # walkable floor (physics layer 2); bodies collide with both

const JOINT_TYPES := {
	"none": PhysicalBone3D.JOINT_TYPE_NONE,
	"pin": PhysicalBone3D.JOINT_TYPE_PIN,
	"cone": PhysicalBone3D.JOINT_TYPE_CONE,
	"hinge": PhysicalBone3D.JOINT_TYPE_HINGE,
}

var profile: Dictionary
var skeleton: Skeleton3D
var simulator: PhysicalBoneSimulator3D
var bodies: Dictionary = {}        # bone name -> PhysicalBone3D
var body_parent: Dictionary = {}   # bone name -> parent body's bone name ("" for the root body)
var bind_frame_a: Dictionary = {}  # bone name -> joint frame in the parent body frame, as bound at rest
var state := State.KINEMATIC
var report: Dictionary = {}        # filled during the simulation and at freeze
## Optional extra non-colliding pairs beyond parent/child, e.g. [["pelvis", "spine_03"]] (set before build).
var extra_collision_exceptions: Array = []

var _sim_time := 0.0
var _still_time := 0.0
var _tile_center := Vector3.ZERO
var _rules: Dictionary


## Creates the PhysicalBoneSimulator3D and one PhysicalBone3D per simulated bone.
## Must run while the skeleton can be put at its bind pose (before any clip has played this frame).
func build(p_skeleton: Skeleton3D, p_profile: Dictionary) -> void:
	skeleton = p_skeleton
	profile = p_profile
	_rules = profile["settle_and_freeze"]
	skeleton.reset_bone_poses()  # joint frames bind from the current pose: make it the bind pose
	simulator = PhysicalBoneSimulator3D.new()
	simulator.name = "Ragdoll"
	# Add the simulator first so it caches the skeleton's bone list and (rest) poses; the bodies
	# read their start transform from that cache when they enter the tree.
	skeleton.add_child(simulator)
	for b: Dictionary in profile["bones"]:  # the JSON lists parents before children
		var pb := _make_body(b)
		simulator.add_child(pb)
		bodies[b["bone"]] = pb
		body_parent[b["bone"]] = b["parent_physical_bone"] if b["parent_physical_bone"] != null else ""
	for bone_name: String in bodies:
		if body_parent[bone_name] != "":
			(bodies[bone_name] as PhysicalBone3D).add_collision_exception_with(bodies[body_parent[bone_name]])
	for pair: Array in extra_collision_exceptions:
		(bodies[pair[0]] as PhysicalBone3D).add_collision_exception_with(bodies[pair[1]])
	# Diagnostics only: the joint frame in the parent body, the same way the engine computes it.
	for bone_name: String in bodies:
		if body_parent[bone_name] == "":
			continue
		var pb: PhysicalBone3D = bodies[bone_name]
		var pa: PhysicalBone3D = bodies[body_parent[bone_name]]
		bind_frame_a[bone_name] = (pa.global_transform.affine_inverse() * (pb.global_transform * pb.joint_offset)).orthonormalized()


func _make_body(b: Dictionary) -> PhysicalBone3D:
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
	cs.shape = _shape(b["shape"])
	pb.add_child(cs)
	pb.joint_type = JOINT_TYPES[b["joint_type"]]
	if b.has("joint_offset"):
		pb.joint_offset = _xform(b["joint_offset"])
	var jc: Dictionary = b.get("joint_constraints", {})
	for key: String in jc:
		pb.set("joint_constraints/" + key, jc[key])  # degrees
	return pb


## Hand-off: call when the Death lead-in clip has been applied at its last frame.
## unit_basis: the unit's world rotation (the JSON velocities are unit-local, unit faces -Z).
## push_dir: horizontal fall direction in world space (the attack's travel direction).
func start(unit_basis: Basis, push_dir: Vector3, tile_center: Vector3) -> void:
	_tile_center = tile_center
	simulator.physical_bones_start_simulation()
	# Put every body exactly on the current (hand-off) pose. In Godot 4.7 the simulator already does
	# this (measured offset 0 mm): "bodies start at rest" means zero VELOCITY, not the bind pose.
	# Kept as a safety net because the simulator's pose cache is only refreshed on pose_updated.
	var start_offset := 0.0  # how far the simulator's own start placement was from the hand-off pose
	for bone_name: String in bodies:
		var pb: PhysicalBone3D = bodies[bone_name]
		var id := skeleton.find_bone(bone_name)
		var target := (skeleton.global_transform * skeleton.get_bone_global_pose(id) * pb.body_offset).orthonormalized()
		start_offset = maxf(start_offset, pb.global_position.distance_to(target.origin))
		pb.global_transform = target
	var handoff: Dictionary = profile["handoff"]
	var vel: Dictionary = handoff["initial_velocities_unit_local"]
	for bone_name: String in vel:
		var rid: RID = (bodies[bone_name] as PhysicalBone3D).get_rid()
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, unit_basis * _v3(vel[bone_name]["linear_mps"]))
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, unit_basis * _v3(vel[bone_name]["angular_radps"]))
	# Gentle push away from the attacker: the JSON's delta-v (0.15 m/s on spine_03), as an impulse.
	var push: Dictionary = handoff["extra_push"]
	var pushed: PhysicalBone3D = bodies[push["bone"]]
	var dv := _v3(push["delta_v_mps_unit_local"]).length()
	pushed.apply_central_impulse(push_dir.normalized() * dv * pushed.mass)
	state = State.SIMULATING
	_sim_time = 0.0
	_still_time = 0.0
	report = {
		"max_body_speed_mps": 0.0, "max_body_spin_radps": 0.0, "max_joint_separation_m": 0.0,
		"joint_angles_deg": {}, "nan": false, "lowest_shape_y_during_m": 1e9,
		"handoff_joint_angles_deg": _joint_angles(),
		"handoff_joint_gaps_m": _joint_gaps(0.002),
		"simulator_start_offset_m": snappedf(start_offset, 0.0001),
		"peak_by_body": {},  # bone -> [peak speed m/s, peak spin rad/s, time of peak spin s]
		"last_moving_body": "",
	}


func _physics_process(delta: float) -> void:
	if state != State.SIMULATING:
		return
	_sim_time += delta
	var max_v := 0.0
	var max_w := 0.0
	var peaks: Dictionary = report["peak_by_body"]
	for bone_name: String in bodies:
		var pb: PhysicalBone3D = bodies[bone_name]
		var v: Vector3 = PhysicsServer3D.body_get_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var w: Vector3 = PhysicsServer3D.body_get_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		if not (v.is_finite() and w.is_finite() and pb.global_position.is_finite()):
			report["nan"] = true
		max_v = maxf(max_v, v.length())
		max_w = maxf(max_w, w.length())
		var pk: Array = peaks.get(bone_name, [0.0, 0.0, 0.0])
		if w.length() > pk[1]:
			pk = [maxf(pk[0], v.length()), w.length(), snappedf(_sim_time, 0.001)]
		else:
			pk[0] = maxf(pk[0], v.length())
		peaks[bone_name] = pk
		if v.length() >= float(_rules["linear_speed_mps"]) or w.length() >= float(_rules["angular_speed_radps"]):
			report["last_moving_body"] = bone_name
	if not report.has("first_tick_head_velocity"):  # proves the hand-off velocities were applied
		var hv: Vector3 = PhysicsServer3D.body_get_state((bodies["head"] as PhysicalBone3D).get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		report["first_tick_head_velocity"] = [snappedf(hv.x, 0.001), snappedf(hv.y, 0.001), snappedf(hv.z, 0.001)]
	report["max_body_speed_mps"] = maxf(report["max_body_speed_mps"], max_v)
	report["max_body_spin_radps"] = maxf(report["max_body_spin_radps"], max_w)
	_track_joints()
	report["lowest_shape_y_during_m"] = minf(report["lowest_shape_y_during_m"], _shape_points_min_y())
	# Settle-and-freeze rule from the JSON: every body slower than the thresholds for hold_s, or the cap.
	if max_v < float(_rules["linear_speed_mps"]) and max_w < float(_rules["angular_speed_radps"]):
		_still_time += delta
	else:
		_still_time = 0.0
	if report["nan"]:
		freeze("nan")
	elif _still_time >= float(_rules["hold_s"]):
		freeze("settled")
	elif _sim_time >= float(_rules["time_cap_s"]):
		freeze("time_cap")


## Copies the simulated pose into the Skeleton3D, stops the simulation and deletes the bodies.
func freeze(reason: String) -> void:
	report["settle_reason"] = reason
	report["settle_time_s"] = snappedf(_sim_time, 0.001)
	report["joint_separation_final_m"] = _max_joint_separation()
	report["shape_outside_tile_m"] = shape_outside_tile()
	report["lowest_shape_y_final_m"] = _shape_points_min_y()
	report["body_overlaps"] = _body_overlaps()
	report["final_joint_angles_deg"] = _joint_angles()
	# Bake: simulated bones take their body's pose; other bones keep their animated local pose.
	var inv := skeleton.global_transform.affine_inverse()
	var globals := {}
	for bone_name: String in bodies:
		var pb: PhysicalBone3D = bodies[bone_name]
		globals[skeleton.find_bone(bone_name)] = inv * pb.global_transform * pb.body_offset.affine_inverse()
	for i in skeleton.get_bone_count():
		_global_pose(i, globals)
	var locals: Array[Transform3D] = []
	for i in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(i)
		var g: Transform3D = globals[i]
		locals.append(g if parent < 0 else (globals[parent] as Transform3D).affine_inverse() * g)
	simulator.physical_bones_stop_simulation()
	simulator.queue_free()  # static corpse: no physics bodies remain
	simulator = null
	bodies.clear()
	for i in skeleton.get_bone_count():
		skeleton.set_bone_pose_position(i, locals[i].origin)
		skeleton.set_bone_pose_rotation(i, locals[i].basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(i, locals[i].basis.get_scale())
	state = State.FROZEN
	frozen.emit(report)


func _global_pose(i: int, globals: Dictionary) -> Transform3D:
	if globals.has(i):
		return globals[i]
	var parent := skeleton.get_bone_parent(i)
	var g := skeleton.get_bone_pose(i)
	if parent >= 0:
		g = _global_pose(parent, globals) * g
	globals[i] = g
	return g


# ------------------------------------------------------------------ diagnostics

## Joint state per child body: hinge angle (engine convention) or cone swing/twist, in degrees.
func _joint_angles() -> Dictionary:
	var out := {}
	for bone_name: String in bind_frame_a:
		var pb: PhysicalBone3D = bodies[bone_name]
		var pa: PhysicalBone3D = bodies[body_parent[bone_name]]
		var a := (pa.global_basis * (bind_frame_a[bone_name] as Transform3D).basis).orthonormalized()
		var b := (pb.global_basis * pb.joint_offset.basis).orthonormalized()
		if pb.joint_type == PhysicalBone3D.JOINT_TYPE_HINGE:
			# engine hinge angle = atan2(yB . xA, yB . yA) = -(right-hand rotation about Z)
			out[bone_name] = {"hinge": rad_to_deg(atan2(b.y.dot(a.x), b.y.dot(a.y)))}
		else:
			var q := (a.inverse() * b).get_rotation_quaternion()
			var twist := 2.0 * atan2(q.x, q.w)
			if twist > PI:
				twist -= TAU
			elif twist < -PI:
				twist += TAU
			out[bone_name] = {"swing": rad_to_deg(acos(clampf(a.x.dot(b.x), -1.0, 1.0))), "twist": rad_to_deg(twist)}
	return out


func _track_joints() -> void:
	var angles := _joint_angles()
	var acc: Dictionary = report["joint_angles_deg"]
	for bone_name: String in angles:
		var cur: Dictionary = angles[bone_name]
		if not acc.has(bone_name):
			acc[bone_name] = {}
		var r: Dictionary = acc[bone_name]
		for k: String in cur:
			var v: float = cur[k]
			if k == "swing":
				r["swing_max"] = maxf(r.get("swing_max", -1e9), v)
			elif k == "twist":
				r["twist_maxabs"] = maxf(r.get("twist_maxabs", -1e9), absf(v))
			else:
				r["hinge_min"] = minf(r.get("hinge_min", 1e9), v)
				r["hinge_max"] = maxf(r.get("hinge_max", -1e9), v)
	report["max_joint_separation_m"] = maxf(report["max_joint_separation_m"], _max_joint_separation())


## Joint anchor gaps above `min_gap` (the clip may move a joint relative to its parent body,
## e.g. clavicle motion shifts the shoulder; the solver pulls such gaps closed after hand-off).
func _joint_gaps(min_gap: float) -> Dictionary:
	var out := {}
	for bone_name: String in bind_frame_a:
		var pb: PhysicalBone3D = bodies[bone_name]
		var pa: PhysicalBone3D = bodies[body_parent[bone_name]]
		var gap := (pb.global_transform * pb.joint_offset.origin).distance_to(pa.global_transform * (bind_frame_a[bone_name] as Transform3D).origin)
		if gap > min_gap:
			out[bone_name] = snappedf(gap, 0.0001)
	return out


func _max_joint_separation() -> float:
	var worst := 0.0
	for bone_name: String in bind_frame_a:
		var pb: PhysicalBone3D = bodies[bone_name]
		var pa: PhysicalBone3D = bodies[body_parent[bone_name]]
		var anchor_child := pb.global_transform * pb.joint_offset.origin
		var anchor_parent := pa.global_transform * (bind_frame_a[bone_name] as Transform3D).origin
		worst = maxf(worst, anchor_child.distance_to(anchor_parent))
	return worst


## World-space sample points on every collision shape (box corners, sphere/capsule rims).
func shape_points() -> PackedVector3Array:
	var pts := PackedVector3Array()
	var rim: Array[Vector3] = []
	for k in 8:
		var a := TAU * k / 8.0
		rim.append(Vector3(cos(a), 0.0, sin(a)))
	for pb: PhysicalBone3D in bodies.values():
		var cs: CollisionShape3D = pb.get_node("Shape")
		var xf := pb.global_transform * cs.transform
		var s := cs.shape
		if s is BoxShape3D:
			var h: Vector3 = (s as BoxShape3D).size * 0.5
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						pts.append(xf * Vector3(h.x * sx, h.y * sy, h.z * sz))
		elif s is SphereShape3D:
			var r := (s as SphereShape3D).radius
			var c := xf.origin
			for d in rim:
				pts.append(c + d * r)
			pts.append(c + Vector3.DOWN * r)
			pts.append(c + Vector3.UP * r)
		elif s is CapsuleShape3D:
			var cap := s as CapsuleShape3D
			var half := cap.height * 0.5 - cap.radius
			for e in [-half, half]:
				var c := xf * Vector3(0.0, e, 0.0)
				for d in rim:
					pts.append(c + d * cap.radius)
				pts.append(c + Vector3.DOWN * cap.radius)
	return pts


func shape_outside_tile() -> float:
	var worst := 0.0
	for p in shape_points():
		worst = maxf(worst, outside_tile(p, _tile_center))
	return worst


func _shape_points_min_y() -> float:
	var lo := 1e9
	for p in shape_points():
		lo = minf(lo, p.y)
	return lo


## Horizontal distance of a point outside the 2 m x 2 m tile centred on tile_center.
static func outside_tile(p: Vector3, tile_center: Vector3, half := 1.0) -> float:
	var dx := maxf(absf(p.x - tile_center.x) - half, 0.0)
	var dz := maxf(absf(p.z - tile_center.z) - half, 0.0)
	return sqrt(dx * dx + dz * dz)


## Penetration between bodies that are not parent/child (those are allowed to touch at the joint).
## Pairwise shape queries against the body layer only (the floor sits on its own layer).
func _body_overlaps() -> Array:
	var out := []
	var space := skeleton.get_world_3d().direct_space_state
	var names: Array = bodies.keys()
	for i in names.size():
		var pb: PhysicalBone3D = bodies[names[i]]
		var cs: CollisionShape3D = pb.get_node("Shape")
		for j in range(i + 1, names.size()):
			var other: String = names[j]
			if body_parent[other] == names[i] or body_parent[names[i]] == other:
				continue
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cs.shape
			q.transform = pb.global_transform * cs.transform
			q.margin = 0.0
			q.collision_mask = BODY_LAYER
			var exclude: Array[RID] = []
			for n: String in names:
				if n != other:
					exclude.append((bodies[n] as PhysicalBone3D).get_rid())
			q.exclude = exclude
			var hits := space.collide_shape(q, 16)
			var depth := 0.0
			for k in range(0, hits.size() - 1, 2):
				depth = maxf(depth, hits[k].distance_to(hits[k + 1]))
			if depth > 0.005:
				out.append({"a": names[i], "b": other, "depth_m": snappedf(depth, 0.0001)})
	return out


static func _xform(d: Dictionary) -> Transform3D:
	var c: Array = d["basis_columns"]
	return Transform3D(Basis(_v3(c[0]), _v3(c[1]), _v3(c[2])), _v3(d["origin"]))


static func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func _shape(s: Dictionary) -> Shape3D:
	match s["type"]:
		"box":
			var box := BoxShape3D.new()
			box.size = _v3(s["size"])
			return box
		"sphere":
			var sphere := SphereShape3D.new()
			sphere.radius = s["radius"]
			return sphere
		"capsule":
			var capsule := CapsuleShape3D.new()  # axis local Y, height includes the caps
			capsule.radius = s["radius"]
			capsule.height = s["height"]
			return capsule
	push_error("unknown shape type %s" % s["type"])
	return SphereShape3D.new()
