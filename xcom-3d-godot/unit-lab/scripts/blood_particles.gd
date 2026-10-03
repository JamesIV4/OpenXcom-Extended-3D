## Shared, texture-free blood burst. All distances are metres, durations seconds.
## Species are data: the caller supplies the sidecar colour, lifetime and optional tuning.
extends RefCounted

const SHADER := preload("res://shaders/blood_particle.gdshader")


static func create(color: Color, direction: Vector3, lifetime: float, size: float, tuning: Dictionary, layer: int) -> GPUParticles3D:
	# Three size-linked lifetime bands correlate larger drops with longer survival.
	# Random size, speed and lifetime within each band keep individual drops varied.
	var mist := layer >= 3
	var lingering := layer == 4
	var p := GPUParticles3D.new()
	p.name = ["BloodSpray", "BloodSprayMedium", "BloodSprayLarge", "BloodMist", "BloodMistLingering"][layer]
	p.emitting = false # Position in the world before starting each emitter.
	if mist:
		p.amount = int(tuning.get("large_mist_count" if lingering else "mist_count", 14 if lingering else 7))
	else:
		var total := maxi(3, int(tuning.get("droplet_count", 220)))
		var small := maxi(1, int(total * 0.50))
		var medium := maxi(1, int(total * 0.32))
		p.amount = [small, medium, total - small - medium][layer]
	p.lifetime = lifetime * ([0.65, 0.95, 1.3, 1.0, float(tuning.get("large_mist_lifetime_scale", 1.55))][layer])
	p.one_shot = true
	p.explosiveness = 0.65 if lingering else 1.0
	p.local_coords = false
	p.fixed_fps = 120
	p.interpolate = true
	p.fract_delta = true
	p.use_fixed_seed = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var pm := ParticleProcessMaterial.new()
	pm.direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.UP
	pm.spread = float(tuning.get("mist_spread_deg" if mist else "spread_deg", 18.0 if lingering else (38.0 if mist else 26.0)))
	var velocity: Array = tuning.get("large_mist_velocity_mps" if lingering else ("mist_velocity_mps" if mist else "velocity_mps"), [0.7, 1.5] if lingering else ([0.18, 0.65] if mist else [0.45, 2.6]))
	pm.initial_velocity_min = float(velocity[0]) * size
	pm.initial_velocity_max = float(velocity[1]) * size
	pm.gravity = Vector3(0, -0.8 if lingering else (-0.25 if mist else -3.5), 0) * size
	pm.damping_min = 0.25 if lingering else (0.35 if mist else 0.0)
	pm.damping_max = 0.5 if lingering else (0.8 if mist else 0.25)
	pm.lifetime_randomness = 0.2 if mist else 0.28
	var diameter: Array = tuning.get("large_mist_diameter_m" if lingering else ("mist_diameter_m" if mist else "droplet_diameter_m"), [0.75, 1.35] if lingering else ([0.20, 0.42] if mist else [0.006, 0.075]))
	var low := float(diameter[0])
	var high := float(diameter[1])
	if not mist:
		var cuts := [0.0, 0.20, 0.565, 1.0]
		pm.scale_min = lerpf(low, high, cuts[layer]) * size
		pm.scale_max = lerpf(low, high, cuts[layer + 1]) * size
	else:
		pm.scale_min = low * size
		pm.scale_max = high * size
	pm.particle_flag_align_y = not mist or lingering
	if not mist:
		# INSTANCE_CUSTOM.z carries a stable random shape seed; no flipbook animation.
		pm.anim_offset_min = 0.0
		pm.anim_offset_max = 1.0
	pm.angle_min = -180.0 if mist else 0.0
	pm.angle_max = 180.0 if mist else 0.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0 if lingering else (0.18 if mist else 1.0)))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.15 if mist else 0.65, Color(1, 1, 1, 0.28 if lingering else (0.28 if mist else 1.0)))
	if lingering:
		fade.add_point(0.55, Color(1, 1, 1, 0.07))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.22 if mist else 1.0))
	curve.add_point(Vector2(1, 1.0 if mist else 0.65))
	var growth := CurveTexture.new()
	growth.curve = curve
	pm.scale_curve = growth
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 1.0) if lingering else (Vector2.ONE if mist else Vector2(1.8, 1.0))
	if lingering:
		quad.center_offset = Vector3(0.65, 0, 0) # Narrow end near the emitter; broad end toward the attacker.
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("blood_color", color)
	mat.set_shader_parameter("mist", mist)
	mat.set_shader_parameter("conical", lingering)
	quad.material = mat
	p.draw_pass_1 = quad
	# Conservative bounds include flight, falling droplets and puff radius.
	var extent := maxf(1.0, pm.initial_velocity_max * p.lifetime + 1.75 * size * p.lifetime * p.lifetime + pm.scale_max * (2.0 if lingering else 1.0))
	p.visibility_aabb = AABB(Vector3.ONE * -extent, Vector3.ONE * extent * 2.0)
	return p
