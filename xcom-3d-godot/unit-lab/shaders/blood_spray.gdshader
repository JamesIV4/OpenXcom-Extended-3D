// Hit-spray particle: velocity-aligned billboard with a 2x2 flipbook, tinted by the species colour.
// The flipbook is tint-neutral (RGB = thickness luminance, A = coverage); sprite +X = spray direction.
// Needs ParticleProcessMaterial.particle_flag_align_y = true (particle Y axis = velocity).
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, skip_vertex_transform, specular_schlick_ggx;

uniform sampler2D flipbook : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 blood_color : source_color = vec3(0.184, 0.396, 0.059);
uniform float h_frames = 2.0;
uniform float v_frames = 2.0;
uniform float roughness = 0.15;

varying float particle_alpha;

void vertex() {
	vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 vel = (MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	float scale = length(MODEL_MATRIX[1].xyz);
	vec2 screen_dir = length(vel.xy) > 1e-5 ? normalize(vel.xy) : vec2(1.0, 0.0);
	vec3 ax = vec3(screen_dir, 0.0);         // sprite +X follows the on-screen velocity
	vec3 ay = vec3(-screen_dir.y, screen_dir.x, 0.0);
	VERTEX = center + (ax * VERTEX.x + ay * VERTEX.y) * scale;
	NORMAL = vec3(0.0, 0.0, 1.0);
	// Flipbook frame from the particle's animation phase (0..1 over its life).
	float total = h_frames * v_frames;
	float frame = clamp(floor(INSTANCE_CUSTOM.z * total), 0.0, total - 1.0);
	UV = UV / vec2(h_frames, v_frames) + vec2(mod(frame, h_frames) / h_frames, floor(frame / h_frames) / v_frames);
	particle_alpha = COLOR.a;
}

void fragment() {
	vec4 t = texture(flipbook, UV);
	ALBEDO = blood_color * t.rgb;
	ALPHA = t.a * particle_alpha;
	ROUGHNESS = roughness;
	SPECULAR = 0.6;
}
