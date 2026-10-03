## The Sectoid opus-v3 in the unit lab (units_opus55). Same contract as LabUnit; differences:
##  * looping clips are exported as "<name>-loop" (Godot imports them as Idle / IdleArmed / Walk / WalkArmed, looping);
##    play("Idle") etc. work with either spelling;
##  * runtime contract: the unit TURNS toward the attacker during the Hit clip and during the Death lead-in
##    (smoothstep over turn_s), never a snap on the lethal frame; the turn is logged for the lab report;
##  * SectoidV3Ragdoll (attack-direction push on several bodies, per-death variation, ground-clearance lift);
##  * SectoidV3Blood (spray parameters from the sidecar);
##  * a stand-in pistol on the weapon_r socket bone, shown in the armed clips and Attack.
## model_path may be set before the node enters the tree (e.g. the opus-v2 model for colour comparisons).
class_name SectoidV3LabUnit
extends LabUnit

const ARMED := ["IdleArmed", "WalkArmed", "IdleArmed-loop", "WalkArmed-loop", "Attack"]
const LOOPING := ["Idle", "IdleArmed", "Walk", "WalkArmed"]

var weapon: Node3D
var turn_s := 0.2
var turn_log: Dictionary = {}
var _turning := false
var _turn_t := 0.0
var _turn_from := 0.0
var _turn_delta := 0.0
var _ticks_since_lethal := -1


func _init() -> void:
	model_path = "res://assets/models/units/SECTOID/SECTOID.opus-v3.gltf"


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
	body_mesh.layers = 1 << (UNIT_VISUAL_LAYER - 1)
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
	var rd := SectoidV3Ragdoll.new()
	rd.rng.seed = rng.seed + 7
	ragdoll = rd
	ragdoll.name = "RagdollController"
	ragdoll.extra_collision_exceptions = extra_collision_exceptions + ragdoll_profile.get("collision_exceptions", [])
	add_child(ragdoll)
	if not build_ragdoll_on_death:
		ragdoll.build(skeleton, ragdoll_profile)
	ragdoll.frozen.connect(_on_ragdoll_frozen)
	blood = SectoidV3Blood.new()
	blood.name = "Blood"
	add_child(blood)
	blood.setup(blood_profile, model_path.get_base_dir(), fx_root if fx_root else get_parent())
	if skeleton.find_bone("weapon_r") >= 0:
		_make_weapon()


## Stand-in one-handed weapon (dark grey grip + slide) on the socket bone: +Y barrel, +Z top.
func _make_weapon() -> void:
	var att := BoneAttachment3D.new()
	att.name = "WeaponSocket"
	att.bone_name = "weapon_r"
	skeleton.add_child(att)
	weapon = Node3D.new()
	att.add_child(weapon)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.20, 0.23)
	mat.metallic = 0.6
	mat.roughness = 0.4
	for part: Array in [[Vector3(0.035, 0.05, 0.10), Vector3(0, 0.0, -0.03)], [Vector3(0.03, 0.17, 0.045), Vector3(0, 0.06, 0.035)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[0]
		bm.material = mat
		mi.mesh = bm
		mi.position = part[1]
		mi.layers = 1 << (UNIT_VISUAL_LAYER - 1)
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


## Starts the turn toward the attacker: the unit faces the shot's origin, i.e. its back points along attack_dir.
func _start_turn(attack_dir: Vector3) -> void:
	var d := Vector3(attack_dir.x, 0.0, attack_dir.z).normalized()
	var target := atan2(d.x, d.z)
	_turn_from = rotation.y
	_turn_delta = wrapf(target - _turn_from, -PI, PI)
	_turn_t = 0.0
	_turning = absf(_turn_delta) > 1e-4
	turn_log = {"yaw_start_deg": snappedf(rad_to_deg(_turn_from), 0.1), "yaw_target_deg": snappedf(rad_to_deg(_turn_from + _turn_delta), 0.1),
		"turn_deg": snappedf(rad_to_deg(_turn_delta), 0.1), "turn_s": turn_s}


func hit(attack_dir: Vector3) -> void:
	if dead or _dying:
		return
	_start_turn(attack_dir)
	anim.play(_clip("Hit"))
	anim.seek(0.0, true)
	blood.spray(chest_point(attack_dir), attack_dir)


func die(attack_dir: Vector3) -> void:
	if dead or _dying:
		return
	if weapon:
		weapon.visible = false
	var d := Vector3(attack_dir.x, 0.0, attack_dir.z).normalized()
	_attack_dir = d
	_tile_center = global_position
	_start_turn(d)                      # no snap: the lead-in turns the unit over turn_s
	turn_log["yaw_at_lethal_frame_deg"] = snappedf(rad_to_deg(rotation.y), 0.1)
	_ticks_since_lethal = 0
	anim.play(_clip("Death"))
	anim.seek(0.0, true)
	_dying = true
	_death_t = 0.0
	blood.spray(chest_point(d), d)
	blood.splatter(_tile_center, d, rng)
	blood.wound(body_mesh, skin_surface)


func _physics_process(delta: float) -> void:
	if _turning:
		_turn_t += delta
		var k := clampf(_turn_t / turn_s, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		rotation.y = _turn_from + _turn_delta * k
		if _turn_t >= turn_s:
			_turning = false
			turn_log["turn_done_s"] = snappedf(_turn_t, 0.001)
	if _ticks_since_lethal >= 0:
		_ticks_since_lethal += 1
		if _ticks_since_lethal == 1:
			turn_log["yaw_after_1_tick_deg"] = snappedf(rad_to_deg(rotation.y), 0.1)
	var was_dying := _dying
	super._physics_process(delta)
	if was_dying and not _dying:
		turn_log["yaw_at_handoff_deg"] = snappedf(rad_to_deg(rotation.y), 0.1)
		turn_log["handoff_s"] = snappedf(_death_t, 0.001)
		turn_log["turning_at_handoff"] = _turning


func _on_ragdoll_frozen(report: Dictionary) -> void:
	report["turn"] = turn_log.duplicate()
	super._on_ragdoll_frozen(report)


func _on_v3_clip_finished(clip: StringName) -> void:
	if clip == &"Hit" and not dead and not _dying:
		play("Idle")
