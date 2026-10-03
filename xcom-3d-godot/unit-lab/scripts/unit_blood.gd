## Species blood for one unit, driven by its `<model>.blood.json` sidecar.
##
## All blood textures are tint-neutral (RGB = thickness luminance, A = coverage). The species colour
## is ONE per-unit parameter (blood.json per_unit_parameter.blood_color_srgb), multiplied in:
##  * hit spray   : independent GPU droplets and soft mist (scripts/blood_particles.gd)
##  * splatter    : floor Decals at the moment of death, thrown along the shot direction
##  * pool        : one Decal under the frozen corpse, grows, kept inside the death tile
##  * wound       : UV0 overlay drawn as next_pass of the skin material (shaders/blood_wound_overlay)
## Decals only project onto the floor's visual layer, never onto units (Decal.cull_mask).
class_name UnitBlood
extends Node

# Sort offsets affect blending only, not projection or physical wound placement.
# The 20 m separation exceeds the bounds of overlapping unit-scale skin decals.
const WOUND_SORT_OFFSET := 10.0
const DRIP_SORT_OFFSET := -10.0
const POOL_SORT_OFFSET := 10.0
const SPLATTER_SORT_OFFSET := -10.0
const DRIP_SIZE_SCALE := 0.65 # Shared width/length scale for blood running down the skin.
const FLOOR_VISUAL_LAYER := 1     # VisualInstance3D layer of walkable floors (decal targets)
const PARTICLES := preload("res://scripts/blood_particles.gd")
const WOUND_SHADER := preload("res://shaders/blood_wound_overlay.gdshader")

var cfg: Dictionary
var color: Color                    # sRGB species colour, e.g. Sectoid #2f650f
var tex: Dictionary = {}            # runtime_files key -> Texture2D
var fx_root: Node3D                 # world-space parent for decals and particles (not the unit)
var spawned: Array[Node] = []       # everything this unit left in the world, for cleanup


## p_cfg: parsed blood.json. model_dir: res:// folder of the glTF (URIs are relative to it).
func setup(p_cfg: Dictionary, model_dir: String, p_fx_root: Node3D) -> void:
	cfg = p_cfg
	fx_root = p_fx_root
	color = Color.html(cfg["per_unit_parameter"]["blood_color_srgb"])
	var files: Dictionary = cfg["runtime_files"]
	for key: String in files:
		if key == "spray_flipbook":
			continue # Retired animation asset; new species need no spray texture.
		var path := model_dir.path_join(files[key]["uri_from_model"]).simplify_path()
		tex[key] = load(path)
		if tex[key] == null:
			push_error("blood texture missing: " + path)


## World-space surface burst. Lifetime and overall size retain the old species profile;
## spray.particles optionally tunes independent droplets/mist, never flipbook frame settings.
func spray(origin: Vector3, dir: Vector3) -> GPUParticles3D:
	return spray_custom(origin, dir, cfg.get("spray", {}).get("runtime", {}))


## Compatibility with older capture scripts; the former flipbook argument is ignored.
func spray_custom(origin: Vector3, dir: Vector3, rt: Dictionary, _flipbook: Texture2D = null) -> GPUParticles3D:
	var tuning: Dictionary = cfg.get("spray", {}).get("particles", {})
	var lifetime := maxf(0.05, float(tuning.get("lifetime_s", rt.get("lifetime_s", 0.4))))
	var size := maxf(0.1, float(tuning.get("size_scale", float(rt.get("particle_quad_m", 0.95)) / 0.95)))
	var drops: GPUParticles3D
	for layer in 5:
		var p := PARTICLES.create(color, dir, lifetime, size, tuning, layer)
		fx_root.add_child(p)
		p.global_position = origin
		spawned.append(p)
		p.finished.connect(func() -> void:
			spawned.erase(p)
			p.queue_free()
		)
		p.emitting = true
		if layer == 4:
			# Taper the new plume's emission; existing particles keep their own smooth fade.
			var emission := p.create_tween()
			emission.tween_property(p, "amount_ratio", 0.0, p.lifetime * (1.0 - p.explosiveness)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if layer == 0:
			drops = p
	return drops


## Floor splatter at the moment of death: a few decals thrown along the shot direction.
func splatter(unit_pos: Vector3, dir: Vector3, rng: RandomNumberGenerator) -> void:
	var d := Vector3(dir.x, 0, dir.z).normalized()
	var side := d.cross(Vector3.UP)
	var size: Array = cfg["decals"]["splat_size_m"]
	var placements := [[0.55, 0.15, "splat01", 0.85], [0.95, -0.2, "splat02", 0.7], [0.25, -0.1, "splat03", 0.55]]
	for pl: Array in placements:
		var pos: Vector3 = unit_pos + d * (pl[0] + rng.randf_range(-0.08, 0.08)) + side * (pl[1] + rng.randf_range(-0.08, 0.08))
		var s: float = float(size[0]) * float(pl[3])
		_decal(pl[2], Vector3(pos.x, unit_pos.y, pos.z), s, atan2(d.x, d.z) + rng.randf_range(-0.6, 0.6))


## Pool under the frozen corpse. `under`: point under the torso. The pool is clamped so its full
## square stays inside the death tile, then grows to full size over `grow_s` seconds.
func pool(under: Vector3, tile_center: Vector3, grow_s := 2.5) -> Decal:
	var full: float = cfg["decals"]["pool_size_m"][0]
	var limit := 1.0 - full * 0.5
	var c := Vector3(clampf(under.x - tile_center.x, -limit, limit), 0.0, clampf(under.z - tile_center.z, -limit, limit))
	var dec := _decal("pool", tile_center + c, full * 0.25, randf() * TAU)
	var depth: float = cfg["decals"]["projection_depth_m"]
	var tw := dec.create_tween()
	tw.tween_property(dec, "size", Vector3(full, depth, full), grow_s).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return dec


func _decal(kind: String, pos: Vector3, size: float, yaw: float) -> Decal:
	var dec := Decal.new()
	dec.name = "Blood_" + kind
	# Keep growing pools above overlapping ground splatters from any camera angle.
	dec.sorting_offset = POOL_SORT_OFFSET if kind == "pool" else SPLATTER_SORT_OFFSET
	dec.texture_albedo = tex[kind + "_albedo"]
	dec.texture_normal = tex[kind + "_normal"]
	dec.texture_orm = tex[kind + "_orm"]
	dec.modulate = color
	dec.albedo_mix = 1.0
	dec.normal_fade = 0.3
	dec.upper_fade = 0.3
	dec.lower_fade = 0.3
	dec.size = Vector3(size, float(cfg["decals"]["projection_depth_m"]), size)
	dec.cull_mask = FLOOR_VISUAL_LAYER
	fx_root.add_child(dec)
	dec.global_position = pos
	dec.rotation.y = yaw
	spawned.append(dec)
	return dec


## Wound overlay in UV0 on the skin surface, faded in over `fade_s`.
func wound(mesh: MeshInstance3D, surface: int, fade_s := 0.6) -> ShaderMaterial:
	var skin := (mesh.get_active_material(surface) as Material).duplicate() as Material
	var overlay := ShaderMaterial.new()
	overlay.shader = WOUND_SHADER
	overlay.set_shader_parameter("overlay", tex["dead_overlay_uv0"])
	overlay.set_shader_parameter("blood_color", color)
	overlay.set_shader_parameter("amount", 0.0)
	skin.next_pass = overlay
	mesh.set_surface_override_material(surface, skin)
	var tw := mesh.create_tween()
	tw.tween_method(func(v: float) -> void: overlay.set_shader_parameter("amount", v), 0.0, 1.0, fade_s)
	return overlay


func clear() -> void:
	for n in spawned:
		if is_instance_valid(n):
			n.queue_free()
	spawned.clear()
