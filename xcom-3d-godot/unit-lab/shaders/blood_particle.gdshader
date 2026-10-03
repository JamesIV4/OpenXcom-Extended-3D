// One independent drop or soft puff per particle; no sprite sheet or frame indexing.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, skip_vertex_transform;

uniform vec3 blood_color : source_color;
uniform bool mist = false;
uniform bool conical = false;
varying float particle_alpha;
varying float head_on;
varying vec4 shape;
varying float age;

float hash(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

float smooth_union(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

void vertex() {
	vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 velocity_axis = (MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	float scale = length(MODEL_MATRIX[1].xyz);
	float seed = INSTANCE_CUSTOM.z * 913.7;
	shape = vec4(hash(seed), hash(seed + 2.3), hash(seed + 7.1), hash(seed + 13.9));
	age = INSTANCE_CUSTOM.y;
	vec2 axis = length(velocity_axis.xy) > 0.00001 ? normalize(velocity_axis.xy) : vec2(1.0, 0.0);
	if (!mist) {
		float roll = (shape.w - 0.5) * 0.9;
		axis = mat2(vec2(cos(roll), sin(roll)), vec2(-sin(roll), cos(roll))) * axis;
		VERTEX.x *= mix(0.6, 1.2, shape.y);
	}
	head_on = abs(velocity_axis.z) / max(length(velocity_axis), 0.00001);
	if (mist && !conical) {
		axis = vec2(cos(INSTANCE_CUSTOM.x), sin(INSTANCE_CUSTOM.x));
	}
	VERTEX = center + vec3(axis * VERTEX.x + vec2(-axis.y, axis.x) * VERTEX.y, 0.0) * scale;
	NORMAL = vec3(0.0, 0.0, 1.0);
	particle_alpha = COLOR.a;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float coverage;
	if (mist) {
		// A gently uneven, feathered puff. Random particle roll/scale/flight changes each cloud.
		float edge = r + 0.055 * sin(q.x * 11.0 + q.y * 7.0) * sin(q.y * 9.0 - q.x * 5.0);
		coverage = pow(max(0.0, 1.0 - smoothstep(0.05, 1.0, edge)), 1.7);
		if (conical) {
			// Soft tapered plume: narrow at the wound, opening along outward velocity.
			float wisps = 0.07 * sin(q.x * 9.0 + q.y * 6.0) * sin(q.y * 8.0 - q.x * 4.0);
			float width = mix(0.12, 1.0, smoothstep(0.0, 0.85, UV.x));
			float sides = pow(1.0 - smoothstep(0.0, 1.0, max(0.0, abs(q.y) + wisps) / width), 1.6);
			float ends = smoothstep(0.0, 0.16, UV.x) * (1.0 - smoothstep(0.65, 1.0, UV.x));
			// Looking down the cone sees its round cross-section.
			coverage = mix(sides * ends, coverage, smoothstep(0.75, 0.98, head_on));
		}
	} else {
		// Stable broad lobes, not high-frequency jagged noise or a repeated oval.
		float phase = shape.z * 6.283185;
		float wobble = sin(age * 5.0 + phase) * 0.06 * (1.0 - age);
		vec2 drop = q;
		drop.y += wobble * drop.x;
		float angle = atan(drop.y, drop.x);
		float radius = 0.62 + 0.09 * sin(3.0 * angle + phase) + 0.045 * sin(5.0 * angle - phase);
		float distance_to_drop = length(drop) - radius;
		if (shape.x > 0.32) {
			// A rounded leading mass joined to a narrower, off-centre trailing neck.
			float side = (shape.z - 0.5) * 0.5;
			float head = length((drop - vec2(0.18, side * 0.3)) / vec2(0.95, 1.0)) - 0.48;
			float neck = length((drop - vec2(-0.38, side)) / vec2(1.0, 0.7)) - mix(0.19, 0.34, shape.y);
			distance_to_drop = smooth_union(head, neck, 0.24);
			if (shape.x > 0.72) {
				float lobe = length(drop - vec2(-0.05, -0.36 * sign(side + 0.001))) - 0.25;
				distance_to_drop = smooth_union(distance_to_drop, lobe, 0.18);
			}
			distance_to_drop += 0.035 * sin(angle * 4.0 + phase + age * 1.5);
		}
		float aa = max(fwidth(distance_to_drop), 0.025);
		coverage = 1.0 - smoothstep(-aa, aa, distance_to_drop);
		NORMAL = normalize(vec3(drop * 0.45, 1.0));
	}
	ALBEDO = blood_color * (mist ? 1.0 : mix(0.65, 0.98, max(0.0, 1.0 - r)));
	ALPHA = coverage * particle_alpha;
	ROUGHNESS = mist ? 1.0 : 0.22;
	SPECULAR = mist ? 0.0 : 0.55;
}
