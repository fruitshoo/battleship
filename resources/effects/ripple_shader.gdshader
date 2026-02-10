shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 ripple_color : source_color = vec4(1.0, 1.0, 1.0, 0.8);
uniform float thickness : hint_range(0.0, 0.5) = 0.05;

varying float v_age;

void vertex() {
	// Particle age if using GPUParticles
	v_age = INSTANCE_CUSTOM.y;
	// Quad is XZ plane
}

// --- Noise Function for organic distortion ---
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	
	// Add noise distortion to make it less 
	float n = noise(uv * 3.0 + vec2(TIME * 0.5)) * 0.1;
	float dist = length(uv) + n;
	
	// Ripple 1 (Main)
	float radius1 = v_age;
	float ring1 = smoothstep(radius1 - thickness, radius1, dist) - smoothstep(radius1, radius1 + thickness, dist);
	
	// Ripple 2 (Secondary, slightly delayed/offset)
	float radius2 = clamp(v_age - 0.2, 0.0, 1.0);
	float ring2 = (smoothstep(radius2 - thickness * 0.5, radius2, dist) - smoothstep(radius2, radius2 + thickness * 0.5, dist)) * 0.5;
	
	float ring = clamp(ring1 + ring2, 0.0, 1.0);
	float fade = 1.0 - v_age;
	
	ALBEDO = ripple_color.rgb;
	ALPHA = ring * ripple_color.a * fade;
}
