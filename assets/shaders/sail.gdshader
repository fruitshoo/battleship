shader_type spatial;
render_mode cull_disabled, shadows_disabled;

instance uniform vec4 albedo : source_color = vec4(0.95, 0.95, 0.9, 1.0);
uniform float wave_speed : hint_range(0.0, 10.0) = 3.0;
uniform float wave_strength : hint_range(0.0, 1.0) = 0.2;
instance uniform float wind_strength = 1.0;

void vertex() {
	// For billowing (forward bulge), both top and bottom edges should be pinned to the spars.
	// A sine wave gives us 0 at the top, 1 in the middle, and 0 at the bottom.
	float billow_mask = sin(UV.y * PI);
	
	// For flapping and sagging, the bottom edge is generally looser than the top.
	float loose_mask = UV.y;
	
	// 1. Billow Effect (Forward bulge)
	// Local -Z is the front of the ship. We subtract to bulge forward.
	// We use billow_mask so the bulge is concentrated in the middle.
	float billow = billow_mask * 1.5 * wind_strength;
	VERTEX.z -= billow;
	
	// 2. Sag Effect (Hanging down)
	// Stronger when wind_strength is LOW (close to 0).
	float sag_factor = clamp(1.0 - wind_strength, 0.0, 1.0);
	float sag = sag_factor * 0.6 * sin(UV.x * PI) * loose_mask;
	VERTEX.y -= sag;
	
	// Added a slight Z push back when sagging to look collapsed
	VERTEX.z += sag * 0.2;
	
	// 3. Waving/Flapping Motion
	float flap_limit = 0.15 * wind_strength + 0.05;
	float flap = sin(TIME * wave_speed + VERTEX.y * 2.5) * wave_strength * flap_limit;
	
	// Add some secondary high-frequency ripple
	flap += sin(TIME * wave_speed * 1.8 + VERTEX.x * 2.0) * wave_strength * 0.2 * flap_limit;
	
	VERTEX.z -= flap * loose_mask;
}

void fragment() {
	ALBEDO = albedo.rgb;
	// Basic shading
	ROUGHNESS = 0.8;
}
