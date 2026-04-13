shader_type spatial;
render_mode cull_disabled, shadows_disabled, blend_mix, depth_draw_never;

// Base sail appearance / motion
instance uniform vec4 albedo : source_color = vec4(0.95, 0.95, 0.9, 1.0);
uniform float wave_speed : hint_range(0.0, 10.0) = 3.0;
uniform float wave_strength : hint_range(0.0, 1.0) = 0.2;
instance uniform float wind_strength = 1.0;
instance uniform float flutter_strength = 0.0;
instance uniform float flutter_phase = 0.0;
instance uniform float view_fade_alpha = 1.0;

// Optional textured sail look
uniform bool use_sail_texture = false;
uniform sampler2D sail_texture : source_color, repeat_enable;

// Burn / damage masks
uniform sampler2D burn_mask_texture_c : source_color, repeat_enable;

// Texture alpha cleanup
uniform bool use_dark_alpha_cutoff = true;
uniform float dark_alpha_cutoff : hint_range(0.0, 0.5) = 0.12;
uniform float dark_alpha_softness : hint_range(0.001, 0.25) = 0.04;

// UV transform
uniform vec2 sail_uv_scale = vec2(1.0, 1.0);
uniform vec2 sail_uv_offset = vec2(0.0, 0.0);
uniform bool swap_uv_axes = false;
uniform bool flip_u = false;
uniform bool flip_v = false;

// Damage state
uniform float sail_damage : hint_range(0.0, 1.0) = 0.0;
uniform float burn_amount : hint_range(0.0, 1.0) = 0.0;
uniform float hole_alpha_strength : hint_range(0.0, 2.0) = 1.0;
uniform float damage_seed : hint_range(0.0, 1.0) = 0.0;
uniform vec3 burn_edge_emission_color : source_color = vec3(0.46, 0.10, 0.04);
uniform vec3 burn_core_emission_color : source_color = vec3(0.72, 0.24, 0.08);
uniform float burn_edge_emission_strength : hint_range(0.0, 2.0) = 0.28;

// Geometry bounds for deformation
uniform vec3 deform_bounds_min = vec3(-2.0, -3.0, 0.0);
uniform vec3 deform_bounds_size = vec3(4.0, 6.0, 0.001);
uniform float bottom_width_scale : hint_range(0.35, 1.25) = 1.0;

vec2 apply_sail_uv_transform(vec2 source_uv, vec2 uv_scale, vec2 uv_offset) {
	vec2 sail_uv = source_uv;
	if (swap_uv_axes) {
		sail_uv = sail_uv.yx;
	}
	if (flip_u) {
		sail_uv.x = 1.0 - sail_uv.x;
	}
	if (flip_v) {
		sail_uv.y = 1.0 - sail_uv.y;
	}
	return sail_uv * uv_scale + uv_offset;
}

vec2 get_sail_uv(vec2 source_uv) {
	return apply_sail_uv_transform(source_uv, sail_uv_scale, sail_uv_offset);
}

float sample_burn_mask_c(vec2 uv, float scale, vec2 offset) {
	vec3 tex = texture(burn_mask_texture_c, uv * scale + offset).rgb;
	return dot(tex, vec3(0.3333, 0.3333, 0.3333));
}

// Reinterpret the existing burn masks as layered erosion fields instead of
// direct "hole cutout" masks. This gives us softer, staged fabric wear.
float get_erosion_field(vec2 uv, float seed) {
	vec2 coarse_offset = vec2(seed * 0.071, seed * 0.053);
	vec2 detail_offset = vec2(seed * 0.163 + 0.11, seed * 0.127 + 0.07);
	float coarse_c = sample_burn_mask_c(uv, 0.82, coarse_offset * 0.57 + vec2(0.17, 0.09));
	float detail_c = sample_burn_mask_c(uv.yx, 1.46, detail_offset * 0.68 + vec2(0.23, 0.31));
	return clamp(coarse_c * 0.72 + detail_c * 0.28, 0.0, 1.0);
}

float get_fiber_field(vec2 uv, float seed) {
	vec2 fiber_offset = vec2(seed * 0.211 + 0.19, seed * 0.167 + 0.31);
	float fiber_c = sample_burn_mask_c(uv * vec2(0.92, 1.0) + vec2(0.13, 0.0), 2.35, fiber_offset * 0.61 + vec2(0.29, 0.17));
	return clamp(fiber_c, 0.0, 1.0);
}

float get_dissolve_field(vec2 uv, float seed) {
	vec2 primary_offset = vec2(seed * 0.143 + 0.07, seed * 0.117 + 0.19);
	vec2 secondary_offset = vec2(seed * 0.097 + 0.23, seed * 0.173 + 0.11);
	float macro_c = 1.0 - sample_burn_mask_c(uv, 1.05, primary_offset);
	float detail_c = 1.0 - sample_burn_mask_c(uv.yx, 2.10, secondary_offset);
	return clamp(macro_c * 0.7 + detail_c * 0.3, 0.0, 1.0);
}

// Sail motion
void vertex() {
	vec3 base_vertex = VERTEX;
	float width = max(deform_bounds_size.x, 0.001);
	float height = max(deform_bounds_size.y, 0.001);
	float horizontal = clamp((base_vertex.x - deform_bounds_min.x) / width, 0.0, 1.0);
	float vertical = clamp((base_vertex.y - deform_bounds_min.y) / height, 0.0, 1.0);
	float center_x = deform_bounds_min.x + width * 0.5;
	float width_scale = mix(bottom_width_scale, 1.0, vertical);
	VERTEX.x = center_x + (base_vertex.x - center_x) * width_scale;
	float bottom_loose_mask = pow(1.0 - vertical, 0.8);
	float whole_sail_mask = mix(0.35, 1.0, bottom_loose_mask);
	float middle_billow_mask = sin(vertical * PI);

	// For billowing (forward bulge), both top and bottom edges should be pinned to the spars.
	// A sine wave gives us 0 at the top, 1 in the middle, and 0 at the bottom.
	
	// 1. Billow Effect (Forward bulge)
	// Local -Z is the front of the ship. We subtract to bulge forward.
	// We use billow_mask so the bulge is concentrated in the middle.
	float billow = middle_billow_mask * (0.45 + wind_strength * 1.05);
	VERTEX.z -= billow;
	
	// 2. Sag Effect (Hanging down)
	// Stronger when wind_strength is LOW (close to 0).
	float sag_factor = clamp(1.0 - wind_strength, 0.0, 1.0);
	float sag = sag_factor * 0.35 * sin(horizontal * PI) * whole_sail_mask;
	VERTEX.y -= sag;
	
	// Added a slight Z push back when sagging to look collapsed
	VERTEX.z += sag * 0.25;
	
	// 3. Waving/Flapping Motion
	float flap_limit = 0.32 * wind_strength + 0.10;
	float flap = sin(TIME * wave_speed + vertical * 7.0 + horizontal * 2.0) * wave_strength * flap_limit;
	
	// Add some secondary high-frequency ripple
	flap += sin(TIME * wave_speed * 1.9 + vertical * 12.0 + horizontal * 5.0) * wave_strength * 0.35 * flap_limit;
	flap += sin(TIME * wave_speed * 1.25 + vertical * 4.0) * wave_strength * 0.28 * flap_limit;

	// 4. Flag-like fabric flutter
	// Keep the broad billow readable, but let the free edges chatter as the wind slips across the cloth.
	float side_edge_mask = pow(abs(horizontal - 0.5) * 2.0, 1.65);
	float lower_edge_mask = pow(1.0 - vertical, 1.35) * 0.55;
	float flutter_mask = clamp(max(side_edge_mask, lower_edge_mask) * whole_sail_mask, 0.0, 1.0);
	float flutter_time = TIME * (wave_speed * 2.65 + flutter_strength * 2.0) + flutter_phase;
	float traveling_ripple = sin(flutter_time + horizontal * 16.0 + vertical * 3.5);
	traveling_ripple += sin(flutter_time * 1.37 + horizontal * 25.0 - vertical * 6.0) * 0.42;
	float flutter = traveling_ripple * wave_strength * flutter_strength * 0.18 * flutter_mask;
	VERTEX.x += flutter * 0.18 * side_edge_mask;
	VERTEX.y += flutter * 0.10 * lower_edge_mask;
	flap += flutter;
	
	VERTEX.z -= flap * whole_sail_mask;
}

// Damage / burn appearance
void fragment() {
	vec2 base_uv = UV;
	float seed = damage_seed * 17.0;
	float erosion_field = get_erosion_field(base_uv, seed);
	float fiber_field = get_fiber_field(base_uv, seed);
	float erosion_basis = clamp(erosion_field * 0.9 + fiber_field * 0.1, 0.0, 1.0);
	float damage_pattern = smoothstep(0.30, 0.82, erosion_basis);
	float damage_mask = clamp(sail_damage * mix(0.10, 1.0, damage_pattern), 0.0, 1.0);

	// Stage 1: staining / scorch
	// sail_damage defines where the sail is weakened.
	// burn_amount only deepens color on those weakened zones.
	float scorch_progress = smoothstep(0.18, 0.46, sail_damage);
	float scorch_mask = clamp(damage_mask * scorch_progress, 0.0, 1.0);

	// Stage 2: fray follows the same damage map, only becoming visible after
	// the sail is already somewhat weakened.
	float fray_progress = smoothstep(0.12, 0.60, sail_damage);
	float fray_mask = clamp(damage_mask * fray_progress, 0.0, 1.0);

	// Stage 3: holes are driven by the same damage map, but only where the sail
	// is already strongly weakened. hole_alpha_strength controls how much of
	// those zones become true cutouts.
	float hole_progress = smoothstep(0.38, 0.60, sail_damage);
	float hole_field = damage_pattern;
	float hole_openness = clamp(hole_alpha_strength / 2.0, 0.0, 1.0);
	float hole_mask = clamp(smoothstep(0.74, 0.92, hole_field) * hole_progress * hole_openness, 0.0, 1.0);
	float hole_outer = clamp(smoothstep(0.58, 0.84, hole_field) * hole_progress * hole_openness * 0.64, 0.0, 1.0);
	float hole_char_mask = clamp(hole_outer - hole_mask * 0.78, 0.0, 1.0);
	float hole_alpha_mask = clamp(hole_mask + hole_outer, 0.0, 1.0);

	// Burn follows the same broad damage pattern, but its intensity should be
	// readable independently from sail_damage.
	float burn_progress = burn_amount;
	float burn_pattern = smoothstep(0.24, 0.78, damage_pattern);
	float burn_mask = clamp(burn_progress * mix(0.10, 1.0, burn_pattern), 0.0, 1.0);

	float burn_scorch_mask = clamp(max(scorch_mask * 0.72, burn_mask) + hole_char_mask * 1.45 + fray_mask * 0.44, 0.0, 1.0);
	float damage_alpha = clamp(1.0 - hole_alpha_mask * mix(0.0, 1.48, hole_openness), 0.0, 1.0);
	damage_alpha = clamp(damage_alpha, 0.0, 1.0);
	float burn_edge_emission_mask = clamp(hole_char_mask * 0.76 + burn_mask * 0.24 + scorch_mask * 0.08, 0.0, 1.0) * burn_amount;
	float burn_core_emission_mask = clamp(hole_char_mask * 0.22 + burn_mask * 0.12, 0.0, 1.0) * smoothstep(0.32, 1.0, burn_amount);
	float emission_variation = 0.86 + 0.14 * sin(TIME * 4.7 + damage_pattern * 12.0 + fiber_field * 7.0 + damage_seed * 19.0);
	float ember_variation = 0.88 + 0.12 * sin(TIME * 2.9 + erosion_basis * 9.0 + damage_seed * 13.0);

	if (use_sail_texture) {
		vec2 sail_uv = get_sail_uv(UV);
		vec4 tex = texture(sail_texture, sail_uv);
		float texture_alpha = tex.a * damage_alpha;
		if (use_dark_alpha_cutoff) {
			float luma = dot(tex.rgb, vec3(0.2126, 0.7152, 0.0722));
			float dark_mask = smoothstep(dark_alpha_cutoff, dark_alpha_cutoff + dark_alpha_softness, luma);
			texture_alpha *= dark_mask;
			if (tex.a * dark_mask * damage_alpha <= 0.14) {
				discard;
			}
		}
		else if (tex.a * damage_alpha <= 0.14) {
			discard;
		}
		vec3 base_color = tex.rgb * albedo.rgb;
		vec3 char_color = base_color * vec3(0.26, 0.18, 0.14);
		vec3 ember_tint = base_color * vec3(0.56, 0.22, 0.12);
		ALBEDO = mix(base_color, mix(char_color, ember_tint, burn_mask * 0.28), burn_scorch_mask);
		ALPHA = clamp(texture_alpha * view_fade_alpha, 0.0, 1.0);
	} else {
		if (damage_alpha <= 0.14) {
			discard;
		}
		vec3 char_color = albedo.rgb * vec3(0.26, 0.18, 0.14);
		vec3 ember_tint = albedo.rgb * vec3(0.56, 0.22, 0.12);
		ALBEDO = mix(albedo.rgb, mix(char_color, ember_tint, burn_mask * 0.28), burn_scorch_mask);
		ALPHA = clamp(damage_alpha * view_fade_alpha, 0.0, 1.0);
	}
	vec3 burn_edge_emission = burn_edge_emission_color * (burn_edge_emission_mask * burn_edge_emission_strength * ember_variation);
	vec3 burn_core_emission = burn_core_emission_color * (burn_core_emission_mask * burn_edge_emission_strength * 0.72 * emission_variation);
	EMISSION = burn_edge_emission + burn_core_emission;
	ROUGHNESS = 0.8;
}
