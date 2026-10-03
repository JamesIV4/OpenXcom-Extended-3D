## Uses shared UnitBlood droplets and mist, tinted by the species blood sidecar.
class_name MutonV1Blood
extends UnitBlood

var wounds: Array[Node] = []

const V2_SPRAY := {"particle_quad_m": 0.6, "amount": 3, "lifetime_s": 0.4, "spread_deg": 18.0,
	"initial_velocity_mps": [0.5, 1.0], "scale": [0.7, 1.15], "gravity_mps2": -2.0, "up_bias": 0.15,
	"quad_center_offset_u": 0.21}




## Wound decal at `point` on `bone` (blood.json wound_decals). Projection (decal -Y) half-way between the shot and the
## inward normal; decal +X along the shot's tangent on the surface (the grazing wound's streak follows the shot).
func wound_at(skeleton: Skeleton3D, bone: String, point: Vector3, normal: Vector3, shot_dir: Vector3, layer_mask: int, kind: String) -> Decal:
	var wd: Dictionary = cfg["wound_decals"]
	var bi := skeleton.find_bone(bone)
	if bi < 0:
		bi = skeleton.find_bone("spine_03")
		bone = "spine_03"
	var att := BoneAttachment3D.new()
	att.name = "Wound_%d_%s" % [wounds.size(), bone]
	att.bone_name = bone
	skeleton.add_child(att)
	var dec := Decal.new()
	# entry-hole variants (user feedback 2026-10-02): one of wound_decals.variants[kind] at random per hit
	var tk := kind
	var vars: Array = wd.get("variants", {}).get(kind, [])
	if not vars.is_empty():
		tk = vars[randi() % vars.size()]
	dec.name = "WoundDecal_" + tk
	dec.sorting_offset = WOUND_SORT_OFFSET
	dec.texture_albedo = tex[tk + "_albedo"]
	dec.texture_normal = tex[tk + "_normal"]
	dec.texture_orm = tex[tk + "_orm"]
	dec.modulate = color
	dec.albedo_mix = float(wd.get("albedo_mix", 1.0))
	dec.normal_fade = float(wd.get("normal_fade", 0.5))
	dec.upper_fade = float(wd.get("upper_fade", 0.2))
	dec.lower_fade = float(wd.get("lower_fade", 0.2))
	var s := float(wd["size_m"][kind])
	dec.size = Vector3(s, float(wd["projection_depth_m"]), s)
	dec.cull_mask = layer_mask
	att.add_child(dec)
	var d := shot_dir.normalized()
	var n := normal.normalized()
	var y := -(d - n).normalized()                       # decal +Y out of the surface; it projects along -Y
	var x := d - y * d.dot(y)
	if x.length() < 1e-3:
		x = y.cross(Vector3.UP) if absf(y.dot(Vector3.UP)) < 0.9 else y.cross(Vector3.RIGHT)
	x = x.normalized()
	var rr: Dictionary = wd.get("random_roll", {})
	if rr.get("enabled", false) and not (rr.get("except", []) as Array).has(kind):
		x = x.rotated(y, randf() * TAU)                  # random roll about the surface normal: no two holes look stamped
	var z := x.cross(y).normalized()
	var want := Transform3D(Basis(x, y, z), point)
	var bone_xf := skeleton.global_transform * skeleton.get_bone_global_pose(bi)
	dec.transform = bone_xf.affine_inverse() * want      # the attachment snaps to the bone on the next update
	if wd.has("drips"):
		_drip(att, bone_xf, point, n)
	wounds.append(att)
	var cap := int(wd.get("max_per_unit", 6))
	while wounds.size() > cap:
		var old: Node = wounds.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	return dec


func clear() -> void:
	for n in wounds:
		if is_instance_valid(n):
			n.queue_free()
	wounds.clear()
	super.clear()


## Run decal below a wound: local +Z (texture V, down the runs) = world down projected onto the surface at the hit,
## local +Y = the surface normal (projects along -normal). Frozen in the bone frame; grows through the reveal frames.
func _drip(att: BoneAttachment3D, bone_xf: Transform3D, point: Vector3, normal: Vector3) -> Decal:
	var dd: Dictionary = cfg["wound_decals"]["drips"]
	var n := normal.normalized()
	var down := Vector3.DOWN - n * Vector3.DOWN.dot(n)
	if down.length() < float(dd.get("skip_if_projected_down_below", 0.25)):
		return null
	down = down.normalized()
	var x := n.cross(down).normalized()
	var size: Array = dd["size_m"]
	var length := float(size[1]) * DRIP_SIZE_SCALE
	var center := point + down * (length * 0.5 - float(dd.get("top_offset_m", 0.01)) * DRIP_SIZE_SCALE)
	var sets: Array = (dd["sets"] as Dictionary).keys()
	var set_name: String = sets[randi() % sets.size()]
	var sd: Dictionary = dd["sets"][set_name]
	var frames: Array = sd["frames"]
	var dec := Decal.new()
	dec.name = "DripDecal_" + set_name
	dec.sorting_offset = DRIP_SORT_OFFSET
	dec.texture_albedo = tex[frames[0]]
	dec.texture_normal = tex[sd["normal"]]
	dec.texture_orm = tex[sd["orm"]]
	dec.modulate = color
	dec.albedo_mix = 1.0
	dec.normal_fade = float(dd.get("normal_fade", 0.5))
	dec.upper_fade = 0.2
	dec.lower_fade = 0.2
	dec.size = Vector3(float(size[0]) * DRIP_SIZE_SCALE, float(dd["projection_depth_m"]), length)
	dec.cull_mask = (att.get_child(0) as Decal).cull_mask
	att.add_child(dec)
	dec.transform = bone_xf.affine_inverse() * Transform3D(Basis(x, n, down), center)
	dec.set_meta("frame", 0)
	var step := func(pr: float) -> void:
		var k := mini(int(pr * frames.size()), frames.size() - 1)
		if int(dec.get_meta("frame")) != k:
			dec.set_meta("frame", k)
			dec.texture_albedo = tex[frames[k]]
	var tw := dec.create_tween()
	tw.tween_method(step, 0.0, 1.0, float(dd.get("grow_s", 1.5))).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return dec
