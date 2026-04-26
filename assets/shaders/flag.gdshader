shader_type spatial;
render_mode cull_disabled, shadows_disabled;

instance uniform vec4 albedo : source_color;
instance uniform bool is_triangular;
instance uniform bool is_swallowtail;
uniform sampler2D flag_texture : source_color;
uniform bool use_flag_texture = false;
uniform sampler2D emblem_texture : source_color;
uniform bool use_emblem_texture = false;
uniform vec4 emblem_color : source_color = vec4(1.0, 0.92, 0.55, 1.0);
uniform float emblem_strength : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D shape_mask_texture;
uniform bool use_shape_mask = false;
uniform int attachment_edge = 0; // 0: left pole, 1: top yard
uniform float swallowtail_depth : hint_range(0.0, 0.5) = 0.24;
uniform float swallowtail_gap : hint_range(0.0, 0.8) = 0.42;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform bool flip_u = false;
uniform bool flip_v = false;
uniform float wave_speed : hint_range(0.0, 10.0) = 4.0;
uniform float wave_strength : hint_range(0.0, 1.0) = 0.3;
uniform float side_drag : hint_range(0.0, 5.0) = 1.0;

void vertex() {
	float stick_mask = UV.x;
	if (attachment_edge == 1) {
		stick_mask = 1.0 - UV.y;
	}
	stick_mask = clamp(stick_mask, 0.0, 1.0);

	float wave = sin(TIME * wave_speed + UV.x * 5.0 + UV.y * 1.7) * wave_strength * stick_mask;
	VERTEX.y += wave;

	float flutter = cos(TIME * wave_speed * 1.5 + UV.x * 8.0 + UV.y * 2.0) * wave_strength * 0.5 * stick_mask;
	VERTEX.z += flutter;
	VERTEX.z += stick_mask * side_drag * 0.2;
}

void fragment() {
	vec2 sampled_uv = UV * uv_scale + uv_offset;
	if (flip_u) {
		sampled_uv.x = 1.0 - sampled_uv.x;
	}
	if (flip_v) {
		sampled_uv.y = 1.0 - sampled_uv.y;
	}

	if (is_triangular) {
		float center_dist = abs(UV.y - 0.5);
		if (center_dist > (1.0 - UV.x) * 0.5) {
			discard;
		}
	}
	if (is_swallowtail && swallowtail_depth > 0.001 && UV.x > 1.0 - swallowtail_depth) {
		float notch_progress = (UV.x - (1.0 - swallowtail_depth)) / swallowtail_depth;
		float notch_half_gap = swallowtail_gap * 0.5 * notch_progress;
		if (abs(UV.y - 0.5) < notch_half_gap) {
			discard;
		}
	}
	if (use_shape_mask && texture(shape_mask_texture, sampled_uv).a < 0.1) {
		discard;
	}

	vec3 base_color = albedo.rgb;
	if (use_flag_texture) {
		base_color *= texture(flag_texture, sampled_uv).rgb;
	}
	if (use_emblem_texture) {
		vec4 emblem = texture(emblem_texture, sampled_uv);
		base_color = mix(base_color, emblem_color.rgb, emblem.a * emblem_strength);
	}
	ALBEDO = base_color;
	ROUGHNESS = 0.6;
	SPECULAR = 0.2;
}
