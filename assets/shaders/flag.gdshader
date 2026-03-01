shader_type spatial;
render_mode cull_disabled, shadows_disabled;

uniform vec4 albedo : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float wave_speed : hint_range(0.0, 10.0) = 4.0;
uniform float wave_strength : hint_range(0.0, 1.0) = 0.3;
uniform float side_drag : hint_range(0.0, 5.0) = 1.0;

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
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.6;
	SPECULAR = 0.2;
}
