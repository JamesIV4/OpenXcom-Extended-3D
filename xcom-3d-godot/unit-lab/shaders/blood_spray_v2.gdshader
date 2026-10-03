// Hit-spray particle v2 (units_opus55, 2026-10-02; copy of blood_spray.gdshader, which is kept):
// velocity-aligned billboard with a 2x2 flipbook, tinted by the species colour, plus a SCREEN-PRESERVING DEPTH PULL.
// User feedback 2026-10-02: the spray must visibly emerge AT the skin where the hit lands. The emitter now sits a little
// INSIDE the skin (blood.json spray.runtime.origin_inset_m) with the flipbook's burst-origin texel on it; the billboard is
// then drawn `depth_pull` metres closer to the camera along the view ray through the particle (same screen position):
//  - seen from the side, the body in front of that depth still hides the root, so the burst starts at the silhouette;
//  - seen from the shooter's side, the burst lies just in front of the wound and overlaps the wound decal.
// Needs ParticleProcessMaterial.particle_flag_align_y = true (particle Y axis = velocity); sprite +X = spray direction.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, skip_vertex_transform, specular_schlick_ggx;

uniform sampler2D flipbook : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 blood_color : source_color = vec3(0.184, 0.396, 0.059);
uniform float h_frames = 2.0;
uniform float v_frames = 2.0;
uniform float roughness = 0.15;
uniform float depth_pull = 0.03;

varying float particle_alpha;

void vertex() {
	vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 vel = (MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	float scale = length(MODEL_MATRIX[1].xyz);
	vec2 screen_dir = length(vel.xy) > 1e-5 ? normalize(vel.xy) : vec2(1.0, 0.0);
	vec3 ax = vec3(screen_dir, 0.0);
	vec3 ay = vec3(-screen_dir.y, screen_dir.x, 0.0);
	// pull the billboard toward the camera, keeping its screen position and size: perspective - scale the view-space
	// position toward the eye (same projection); orthographic (battlescape camera) - move it along view Z
	vec3 v = center + (ax * VERTEX.x + ay * VERTEX.y) * scale;
	if (PROJECTION_MATRIX[3][3] > 0.5) {
		v.z += depth_pull;
	} else {
		float d = length(center);
		v *= d > depth_pull + 0.05 ? (d - depth_pull) / d : 1.0;
	}
	VERTEX = v;
	NORMAL = vec3(0.0, 0.0, 1.0);
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
