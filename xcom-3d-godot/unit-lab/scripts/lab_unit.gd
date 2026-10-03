## One 3D unit in the lab: imported glTF + clips + ragdoll death + species blood.
##
## Data it reads (all next to the glTF, same basename):
##   <model>.gltf           skinned mesh, Skeleton3D, clips Idle Walk Attack Hit Death DeathBaked Kneel
##   <model>.ragdoll.json   bodies, joints, limits, hand-off velocities, settle rule
##   <model>.blood.json     species colour + tint-neutral blood textures
##
## Unit space: glTF Y-up, the unit faces -Z (north) at facing 0, origin = tile centre on the floor.
##
## Death: die(attack_dir) turns the unit to face the attacker, plays the 0.2 s Death lead-in, then
## hands off to the ragdoll with the clip's velocities plus a gentle push along attack_dir, so the
## body falls AWAY from the attacker. When it settles the pose is baked and the bodies deleted.
class_name LabUnit
extends Node3D

signal died(report: Dictionary)

const UNIT_VISUAL_LAYER := 2   # units are not decal targets
const LOOPED_CLIPS := ["Idle", "Walk"]

var model_path := "res://assets/models/units/SECTOID/SECTOID.opus-v2.gltf"
var fx_root: Node3D
var rng := RandomNumberGenerator.new()
var extra_collision_exceptions: Array = []  # passed to UnitRagdoll (experiments only)
## false: build the 16 bodies at spawn (they idle as static bodies while the unit lives).
## true: build them only at the hand-off frame, briefly posing the skeleton at rest so the joints
## still bind at the bind pose (no physics bodies on living units).
var build_ragdoll_on_death := false

var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var body_mesh: MeshInstance3D
var skin_surface := 0
var ragdoll: UnitRagdoll
var blood: UnitBlood
var ragdoll_profile: Dictionary
var blood_profile: Dictionary

var dead := false
var death_report: Dictionary = {}
var _dying := false
var _death_t := 0.0
var _death_len := 0.2
var _attack_dir := Vector3.BACK
var _tile_center := Vector3.ZERO


func _ready() -> void:
	rng.seed = 20261001  # repeatable splatter placement
	model = (load(model_path) as PackedScene).instantiate()
	add_child(model)
	skeleton = _find(model, "Skeleton3D")
	anim = _find(model, "AnimationPlayer")
	body_mesh = _find_skinned_mesh(model)
	for s in body_mesh.mesh.get_surface_count():
		var m := body_mesh.mesh.surface_get_material(s)
		if m and m.resource_name.ends_with("skin"):
			skin_surface = s
	body_mesh.layers = 1 << (UNIT_VISUAL_LAYER - 1)
	# Deterministic stepping: clips advance in the physics tick, like the ragdoll.
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	for clip: String in LOOPED_CLIPS:  # glTF carries no loop flag
		anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	anim.animation_finished.connect(_on_clip_finished)
	_death_len = anim.get_animation("Death").length
	var base := model_path.get_basename()
	ragdoll_profile = JSON.parse_string(FileAccess.get_file_as_string(base + ".ragdoll.json"))
	blood_profile = JSON.parse_string(FileAccess.get_file_as_string(base + ".blood.json"))
	ragdoll = UnitRagdoll.new()
	ragdoll.name = "RagdollController"
	ragdoll.extra_collision_exceptions = extra_collision_exceptions
	add_child(ragdoll)
	if not build_ragdoll_on_death:
		ragdoll.build(skeleton, ragdoll_profile)  # skeleton is still at its bind pose here
	ragdoll.frozen.connect(_on_ragdoll_frozen)
	blood = UnitBlood.new()
	blood.name = "Blood"
	add_child(blood)
	blood.setup(blood_profile, model_path.get_base_dir(), fx_root if fx_root else get_parent())


func play(clip: String) -> void:
	if dead or _dying:
		return
	anim.play(clip)


## Shows a clip at a fixed time (for review captures).
func pose_at(clip: String, t: float) -> void:
	anim.play(clip)
	anim.seek(t, true)
	anim.pause()


## Non-lethal hit: flinch clip + hit spray. attack_dir = travel direction of the shot.
func hit(attack_dir: Vector3) -> void:
	if dead or _dying:
		return
	anim.play("Hit")
	anim.seek(0.0, true)
	blood.spray(chest_point(attack_dir), attack_dir)


## Lethal hit. attack_dir = travel direction of the killing shot (attacker -> this unit).
func die(attack_dir: Vector3) -> void:
	if dead or _dying:
		return
	var d := Vector3(attack_dir.x, 0.0, attack_dir.z).normalized()
	_attack_dir = d
	_tile_center = global_position
	# Face the attacker: the lead-in clip falls backward (+Z local), so backward becomes d.
	global_rotation = Vector3(0.0, atan2(d.x, d.z), 0.0)
	anim.play("Death")
	anim.seek(0.0, true)
	_dying = true
	_death_t = 0.0
	blood.spray(chest_point(d), d)
	blood.splatter(_tile_center, d, rng)
	blood.wound(body_mesh, skin_surface)


func _physics_process(delta: float) -> void:
	if not _dying:
		return
	_death_t += delta
	if _death_t + 1e-4 >= _death_len:
		# Hand-off frame: apply the clip's last frame, hold it, start physics on that pose.
		anim.seek(_death_len, true)
		anim.pause()
		_dying = false
		if build_ragdoll_on_death:
			_build_ragdoll_at_rest()
		ragdoll.start(global_basis, _attack_dir, _tile_center)


## Lazy build: save the hand-off pose, put the skeleton at rest so the joints bind at the bind
## pose, create the bodies, then restore the pose. start() then places the bodies on that pose.
func _build_ragdoll_at_rest() -> void:
	var saved: Array = []
	for i in skeleton.get_bone_count():
		saved.append([skeleton.get_bone_pose_position(i), skeleton.get_bone_pose_rotation(i), skeleton.get_bone_pose_scale(i)])
	ragdoll.build(skeleton, ragdoll_profile)  # resets the skeleton to rest internally
	for i in skeleton.get_bone_count():
		skeleton.set_bone_pose_position(i, saved[i][0])
		skeleton.set_bone_pose_rotation(i, saved[i][1])
		skeleton.set_bone_pose_scale(i, saved[i][2])


func _on_ragdoll_frozen(report: Dictionary) -> void:
	dead = true
	report["attack_dir"] = [snappedf(_attack_dir.x, 0.001), snappedf(_attack_dir.z, 0.001)]
	report["joint_outside_tile_m"] = snappedf(joints_outside_tile(), 0.0001)
	var owner_bone := PackedInt32Array()
	var verts := skinned_vertices(owner_bone)
	var mesh_out := 0.0
	var min_y := 1e9
	var sink := {}  # bone -> deepest vertex below the floor (m), for vertices more than 5 mm under
	for vi in verts.size():
		var v := verts[vi]
		mesh_out = maxf(mesh_out, UnitRagdoll.outside_tile(v, _tile_center))
		min_y = minf(min_y, v.y)
		if v.y < -0.005:
			var bn := skeleton.get_bone_name(owner_bone[vi])
			sink[bn] = snappedf(minf(sink.get(bn, 0.0), v.y), 0.0001)
	report["mesh_outside_tile_m"] = snappedf(mesh_out, 0.0001)
	report["mesh_min_y_m"] = snappedf(min_y, 0.0001)
	report["mesh_below_floor_by_bone_m"] = sink
	report["shape_outside_tile_m"] = snappedf(report["shape_outside_tile_m"], 0.0001)
	var head := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("head")).origin
	var pelvis := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("pelvis")).origin
	report["pelvis_xz"] = [snappedf(pelvis.x, 0.001), snappedf(pelvis.z, 0.001)]
	report["head_xz"] = [snappedf(head.x, 0.001), snappedf(head.z, 0.001)]
	var lie := Vector3(head.x - pelvis.x, 0, head.z - pelvis.z).normalized()
	report["fall_alignment"] = snappedf(lie.dot(_attack_dir), 0.001)  # 1 = head lies along the shot
	var torso := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("spine_03")).origin
	blood.pool((torso + pelvis) * 0.5, _tile_center)
	death_report = report
	died.emit(report)


## Exit-wound point at chest height: the body surface on the far side from the attacker,
## where the spray emerges along the shot.
func chest_point(attack_dir: Vector3) -> Vector3:
	var chest := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("spine_03")).origin
	return chest + Vector3.UP * 0.12 + Vector3(attack_dir.x, 0, attack_dir.z).normalized() * 0.14


## Max horizontal distance of any skeleton joint (bone end) outside the death tile.
func joints_outside_tile() -> float:
	var worst := 0.0
	for i in skeleton.get_bone_count():
		var p := skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
		worst = maxf(worst, UnitRagdoll.outside_tile(p, _tile_center))
	return worst


## CPU-skinned world positions of the visible mesh (for footprint and floor checks).
## If `owner_bone` is given it receives each vertex's most-weighted skeleton bone.
func skinned_vertices(owner_bone: PackedInt32Array = PackedInt32Array()) -> PackedVector3Array:
	var out := PackedVector3Array()
	var skin := body_mesh.skin
	var bind_xf: Array[Transform3D] = []
	var bind_bone := PackedInt32Array()
	for i in skin.get_bind_count():
		var bone := skin.get_bind_bone(i)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(i))
		bind_bone.append(bone)
		bind_xf.append(body_mesh.global_transform * skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(i))
	var mesh := body_mesh.mesh
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var n := bones.size() / verts.size()
		for vi in verts.size():
			var p := Vector3.ZERO
			var best := -1.0
			var best_bone := -1
			for k in n:
				var w := weights[vi * n + k]
				if w > 0.0:
					p += (bind_xf[bones[vi * n + k]] * verts[vi]) * w
					if w > best:
						best = w
						best_bone = bind_bone[bones[vi * n + k]]
			out.append(p)
			owner_bone.append(best_bone)
	return out


func _on_clip_finished(clip: StringName) -> void:
	if clip == &"Hit" and not dead and not _dying:
		anim.play("Idle")


static func _find(root: Node, type_name: String) -> Node:
	if root.is_class(type_name):
		return root
	for c in root.get_children():
		var f := _find(c, type_name)
		if f:
			return f
	return null


static func _find_skinned_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D and (root as MeshInstance3D).skin:
		return root
	for c in root.get_children():
		var f := _find_skinned_mesh(c)
		if f:
			return f
	return null
