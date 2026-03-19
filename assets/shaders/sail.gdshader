shader_type spatial;
render_mode cull_disabled, shadows_disabled, depth_draw_opaque;

// Base sail appearance / motion
instance uniform vec4 albedo : source_color = vec4(0.95, 0.95, 0.9, 1.0);
uniform float wave_speed : hint_range(0.0, 10.0) = 3.0;
uniform float wave_strength : hint_range(0.0, 1.0) = 0.2;
instance uniform float wind_strength = 1.0;

// Optional textured sail look
uniform bool use_sail_texture = false;
uniform sampler2D sail_texture : source_color, repeat_enable;

// Burn / damage masks
uniform sampler2D burn_mask_texture_a : source_color, repeat_enable;
uniform sampler2D burn_mask_texture_b : source_color, repeat_enable;
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
uniform vec3 burn_edge_emission_color : source_color = vec3(0.98, 0.30, 0.10);
uniform vec3 burn_core_emission_color : source_color = vec3(1.00, 0.78, 0.34);
uniform float burn_edge_emission_strength : hint_range(0.0, 2.0) = 0.82;

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

float sample_burn_mask_a(vec2 uv, float scale, vec2 offset) {
	return texture(burn_mask_texture_a, uv * scale + offset).a;
}

float sample_burn_mask_b(vec2 uv, float scale, vec2 offset) {
	return texture(burn_mask_texture_b, uv * scale + offset).a;
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
	float coarse_a = sample_burn_mask_a(uv, 1.35, coarse_offset);
	float coarse_b = sample_burn_mask_b(uv, 1.90, coarse_offset * 0.81 + vec2(0.13, 0.21));
	float coarse_c = sample_burn_mask_c(uv, 1.55, coarse_offset * 0.57 + vec2(0.17, 0.09));
	float detail_a = sample_burn_mask_a(uv.yx, 2.65, detail_offset);
	float detail_b = sample_burn_mask_b(uv.yx, 3.35, detail_offset * 0.73 + vec2(0.29, 0.17));
	float detail_c = sample_burn_mask_c(uv.yx, 2.85, detail_offset * 0.68 + vec2(0.23, 0.31));
	return clamp(coarse_a * 0.24 + coarse_b * 0.18 + coarse_c * 0.20 + detail_a * 0.14 + detail_b * 0.12 + detail_c * 0.18, 0.0, 1.0);
}

float get_fiber_field(vec2 uv, float seed) {
	vec2 fiber_offset = vec2(seed * 0.211 + 0.19, seed * 0.167 + 0.31);
	float fiber_a = sample_burn_mask_a(uv * vec2(1.0, 0.72), 4.60, fiber_offset);
	float fiber_b = sample_burn_mask_b(uv * vec2(1.0, 0.84) + vec2(0.21, 0.0), 5.10, fiber_offset * 0.73 + vec2(0.07, 0.13));
	float fiber_c = sample_burn_mask_c(uv * vec2(0.92, 1.0) + vec2(0.13, 0.0), 3.95, fiber_offset * 0.61 + vec2(0.29, 0.17));
	return clamp(max(max(fiber_a * 0.78, fiber_b * 0.84), fiber_c * 0.92), 0.0, 1.0);
}

float get_dissolve_field(vec2 uv, float seed) {
	vec2 primary_offset = vec2(seed * 0.143 + 0.07, seed * 0.117 + 0.19);
	vec2 secondary_offset = vec2(seed * 0.097 + 0.23, seed * 0.173 + 0.11);
	float macro_c = 1.0 - sample_burn_mask_c(uv, 1.05, primary_offset);
	float detail_c = 1.0 - sample_burn_mask_c(uv.yx, 2.10, secondary_offset);
	float support_a = 1.0 - sample_burn_mask_a(uv, 2.60, secondary_offset * 0.71 + vec2(0.17, 0.13));
	float support_b = 1.0 - sample_burn_mask_b(uv.yx, 2.95, primary_offset * 0.64 + vec2(0.29, 0.07));
	return clamp(macro_c * 0.56 + detail_c * 0.24 + support_a * 0.10 + support_b * 0.10, 0.0, 1.0);
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
	
	VERTEX.z -= flap * whole_sail_mask;
}

// Damage / burn appearance
void fragment() {
	vec2 base_uv = UV;
	float edge_distance = min(min(base_uv.x, 1.0 - base_uv.x), min(base_uv.y, 1.0 - base_uv.y));
	float seed = damage_seed * 17.0;
	float edge_bias = 1.0 - smoothstep(0.03, 0.24, edge_distance);
	float edge_fray_mask = 1.0 - smoothstep(0.10, 0.34, edge_distance);
	float erosion_field = get_erosion_field(base_uv, seed);
	float fiber_field = get_fiber_field(base_uv, seed);
	float dissolve_field = get_dissolve_field(base_uv, seed);
	float wear_field = clamp(erosion_field * 0.72 + fiber_field * 0.38 + edge_bias * 0.34, 0.0, 1.0);

	// Stage 1: staining / scorch
	float scorch_progress = clamp(max(sail_damage * 0.92, burn_amount * 1.10), 0.0, 1.0);
	float scorch_threshold = 1.0 - scorch_progress * 0.88;
	float scorch_mask = (1.0 - smoothstep(scorch_threshold - 0.22, scorch_threshold + 0.08, wear_field)) * scorch_progress;

	// Stage 2: edge fray
	float fray_progress = smoothstep(0.18, 0.82, sail_damage);
	float fray_field = clamp(wear_field * 0.74 + edge_bias * 0.46, 0.0, 1.0);
	float fray_threshold = 1.0 - fray_progress * 0.78;
	float fray_mask = (1.0 - smoothstep(fray_threshold - 0.12, fray_threshold + 0.05, fray_field)) * edge_fray_mask * fray_progress;

	// Stage 3: direct dissolve / erosion across the fabric surface.
	// Use the new erosion texture as an actual threshold field so the
	// breakup is easy to read during debug tuning.
	float hole_progress = smoothstep(0.12, 0.92, sail_damage);
	float dissolve_threshold = mix(0.96, 0.42, hole_progress);
	float hole_mask = smoothstep(dissolve_threshold - 0.05, dissolve_threshold + 0.05, dissolve_field) * hole_progress;
	float hole_outer = smoothstep(dissolve_threshold - 0.18, dissolve_threshold + 0.08, dissolve_field) * hole_progress;
	float hole_char_mask = clamp(hole_outer - hole_mask * 0.78, 0.0, 1.0);

	// Keep edge fray additive so the sail still tears along the borders,
	// but let the dissolve dominate the interior silhouette.
	float edge_hole_bias = mix(0.90, 1.0, edge_bias);
	hole_mask *= edge_hole_bias;
	hole_char_mask *= mix(0.84, 1.0, edge_bias);

	// Burn can deepen the char without immediately cutting away the sail.
	float burn_progress = max(burn_amount, sail_damage * 0.35);
	float burn_field = clamp(erosion_field * 0.62 + fiber_field * 0.28 + edge_bias * 0.50, 0.0, 1.0);
	float burn_threshold = 1.0 - burn_progress * 0.86;
	float burn_mask = (1.0 - smoothstep(burn_threshold - 0.16, burn_threshold + 0.06, burn_field)) * mix(0.55, 1.0, edge_bias) * burn_progress;

	float burn_scorch_mask = clamp(max(scorch_mask, burn_mask * 0.90) + hole_char_mask * 1.45 + fray_mask * 0.44, 0.0, 1.0);
	float damage_alpha = clamp(1.0 - fray_mask * 0.38 - hole_mask * 0.995 * hole_alpha_strength, 0.0, 1.0);
	float burn_alpha = clamp(1.0 - burn_mask * burn_amount * 0.18, 0.0, 1.0);
	damage_alpha *= burn_alpha;
	float burn_edge_emission_mask = clamp(hole_char_mask * 1.35 + burn_mask * edge_bias * 0.72 + scorch_mask * edge_bias * 0.18, 0.0, 1.0) * burn_amount;
	float burn_core_emission_mask = clamp(hole_char_mask * 0.58 + burn_mask * edge_bias * 0.36, 0.0, 1.0) * smoothstep(0.18, 1.0, burn_amount);
	float emission_variation = 0.86 + 0.14 * sin(TIME * 4.7 + dissolve_field * 12.0 + fiber_field * 7.0 + damage_seed * 19.0);
	float ember_variation = 0.88 + 0.12 * sin(TIME * 2.9 + erosion_field * 9.0 + damage_seed * 13.0);

	if (use_sail_texture) {
		vec2 sail_uv = get_sail_uv(UV);
		vec4 tex = texture(sail_texture, sail_uv);
		if (use_dark_alpha_cutoff) {
			float luma = dot(tex.rgb, vec3(0.2126, 0.7152, 0.0722));
			float dark_mask = smoothstep(dark_alpha_cutoff, dark_alpha_cutoff + dark_alpha_softness, luma);
			if (tex.a * dark_mask * damage_alpha <= 0.001) {
				discard;
			}
		}
		else if (tex.a * damage_alpha <= 0.001) {
			discard;
		}
		vec3 base_color = tex.rgb * albedo.rgb;
		ALBEDO = mix(base_color, base_color * vec3(0.44, 0.36, 0.26), burn_scorch_mask);
	} else {
		if (damage_alpha <= 0.001) {
			discard;
		}
		ALBEDO = mix(albedo.rgb, albedo.rgb * vec3(0.44, 0.36, 0.26), burn_scorch_mask);
	}
	vec3 burn_edge_emission = burn_edge_emission_color * (burn_edge_emission_mask * burn_edge_emission_strength * ember_variation);
	vec3 burn_core_emission = burn_core_emission_color * (burn_core_emission_mask * burn_edge_emission_strength * 0.72 * emission_variation);
	EMISSION = burn_edge_emission + burn_core_emission;
	ROUGHNESS = 0.8;
}
