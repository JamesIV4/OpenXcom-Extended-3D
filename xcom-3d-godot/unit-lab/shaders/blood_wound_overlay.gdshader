// Dead-state wound overlay, drawn as next_pass of the skin material (same UV0, same skinning).
// The overlay texture is tint-neutral (RGB = thickness luminance, A = coverage).
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, diffuse_burley, specular_schlick_ggx;

uniform sampler2D overlay : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 blood_color : source_color = vec3(0.184, 0.396, 0.059);
uniform float amount : hint_range(0.0, 1.0) = 1.0;   // animated 0 -> 1 when the unit dies

void fragment() {
	vec4 t = texture(overlay, UV);
	ALBEDO = blood_color * t.rgb;
	ALPHA = t.a * amount;
	ROUGHNESS = mix(0.30, 0.08, t.a);  // wet film: glossier where thick
	SPECULAR = 0.6;
	CLEARCOAT = 0.4;
	CLEARCOAT_ROUGHNESS = 0.1;
}
