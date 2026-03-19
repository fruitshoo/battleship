shader_type spatial;
render_mode cull_disabled, shadows_disabled;

instance uniform vec4 albedo : source_color;
uniform sampler2D flag_texture : source_color;
uniform bool use_flag_texture = false;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform bool flip_u = false;
uniform bool flip_v = false;
uniform float wave_speed : hint_range(0.0, 10.0) = 4.0;
uniform float wave_strength : hint_range(0.0, 1.0) = 0.3;
uniform float side_drag : hint_range(0.0, 5.0) = 1.0;
instance uniform bool is_triangular;

void vertex() {
	// UV.x == 0 points are pinned to the pole. 
	// The flutter strength increases as we move away from the pole (higher UV.x).
	float stick_mask = UV.x;
	
	// Vertical wave (flapping up and down)
	float wave = sin(TIME * wave_speed + UV.x * 5.0) * wave_strength * stick_mask;
	VERTEX.y += wave;
	
	// Side-to-side flutter (more dynamic)
	float flutter = cos(TIME * wave_speed * 1.5 + UV.x * 8.0) * wave_strength * 0.5 * stick_mask;
	VERTEX.z += flutter;
	
	// Wind drag (pushing the flag back)
	VERTEX.z += stick_mask * side_drag * 0.2;
}

void fragment() {
	if (is_triangular) {
		// Calculate triangular (pennant) mask
		// As UV.x increases (away from pole), the allowed UV.y range shrinks.
		float center_dist = abs(UV.y - 0.5);
		if (center_dist > (1.0 - UV.x) * 0.5) {
			discard;
		}
	}
	
	vec2 sampled_uv = UV * uv_scale + uv_offset;
	if (flip_u) {
		sampled_uv.x = 1.0 - sampled_uv.x;
	}
	if (flip_v) {
		sampled_uv.y = 1.0 - sampled_uv.y;
	}
	vec3 base_color = albedo.rgb;
	if (use_flag_texture) {
		base_color *= texture(flag_texture, sampled_uv).rgb;
	}
	ALBEDO = base_color;
	ROUGHNESS = 0.6;
	SPECULAR = 0.2;
}
