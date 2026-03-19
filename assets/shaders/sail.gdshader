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
uniform float damage_seed : hint_range(0.0, 1.0) = 0.0;

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
	float edge_mask = 1.0 - smoothstep(0.02, 0.18, edge_distance);
	float seed = damage_seed * 17.0;
	vec2 coarse_offset = vec2(seed * 0.071, seed * 0.053);
	vec2 fine_offset = coarse_offset + vec2(0.31, 0.17);
	float coarse_mask_a = sample_burn_mask_a(base_uv, 1.10, coarse_offset);
	float coarse_mask_b = sample_burn_mask_b(base_uv, 1.24, coarse_offset * 0.83 + vec2(0.11, 0.07));
	float coarse_mask = clamp(max(coarse_mask_a, coarse_mask_b * 0.92), 0.0, 1.0);
	float fine_mask_a = sample_burn_mask_a(base_uv, 1.95, fine_offset);
	float fine_mask_b = sample_burn_mask_b(base_uv, 2.20, fine_offset * 0.91 + vec2(0.19, 0.29));
	float fine_mask = clamp(max(fine_mask_a * 0.82, fine_mask_b), 0.0, 1.0);
	float scorch_amount = smoothstep(0.06, 0.72, sail_damage);
	float fray_amount = smoothstep(0.22, 0.95, sail_damage);
	float edge_fray = step(1.0 - fray_amount * 0.75, coarse_mask) * edge_mask * fray_amount;
	float hole_amount = smoothstep(0.72, 0.98, sail_damage);
	float interior_mask = smoothstep(0.06, 0.22, edge_distance);
	float hole_mask = step(1.0 - hole_amount * 0.55, fine_mask) * interior_mask * hole_amount;
	float damage_alpha = clamp(1.0 - edge_fray * 0.82 - hole_mask * 0.95, 0.0, 1.0);
	float scorch_mask = clamp(edge_fray * 0.62 + hole_mask * 0.35 + scorch_amount * 0.52, 0.0, 1.0);
	float burn_edge = step(1.0 - burn_amount * 0.48, coarse_mask) * edge_mask * burn_amount;
	float burn_scorch_mask = clamp(scorch_mask + burn_edge * 0.95 + burn_amount * 0.32, 0.0, 1.0);
	float burn_alpha = clamp(1.0 - burn_edge * burn_amount * 0.55, 0.0, 1.0);
	damage_alpha *= burn_alpha;

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
	ROUGHNESS = 0.8;
}
