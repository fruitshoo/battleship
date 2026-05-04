shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert, specular_disabled;

uniform vec4 base_color : source_color = vec4(0.86, 0.72, 0.38, 1.0);
uniform sampler2D flag_texture : source_color;
uniform bool use_flag_texture = false;
uniform sampler2D shape_mask_texture;
uniform bool use_shape_mask = false;
uniform float shape_mask_cutoff : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform sampler2D emblem_texture : source_color;
uniform bool use_emblem_texture = true;
uniform float emblem_strength : hint_range(0.0, 1.0) = 1.0;
uniform bool emblem_use_texture_color = true;
uniform vec4 emblem_color : source_color = vec4(1.0, 0.86, 0.25, 1.0);
uniform vec2 emblem_uv_scale = vec2(1.0, 1.0);
uniform vec2 emblem_uv_offset = vec2(0.0, 0.0);
uniform float alpha_cutoff : hint_range(0.0, 0.2) = 0.02;
uniform float wave_speed : hint_range(0.0, 8.0) = 4.2;
uniform float wave_strength : hint_range(0.0, 0.8, 0.01) = 0.13;
uniform float side_drag : hint_range(0.0, 0.8, 0.01) = 0.08;
uniform int pin_mode : hint_enum("Left", "Top", "Left and Top") = 0;
uniform float cloth_roughness : hint_range(0.0, 1.0, 0.01) = 0.96;
uniform float cloth_weave_strength : hint_range(0.0, 0.12, 0.005) = 0.035;
uniform float cloth_weave_scale : hint_range(4.0, 96.0, 1.0) = 42.0;

float get_free_edge(vec2 uv) {
	if (pin_mode == 1) {
		return clamp(uv.y, 0.0, 1.0);
	}
	if (pin_mode == 2) {
		return clamp(uv.x * uv.y, 0.0, 1.0);
	}
	return clamp(uv.x, 0.0, 1.0);
}

vec2 get_wave_axes(vec2 uv) {
	if (pin_mode == 1) {
		return vec2(uv.y, uv.x);
	}
	if (pin_mode == 2) {
		return vec2((uv.x + uv.y) * 0.5, abs(uv.x - uv.y));
	}
	return uv;
}

vec2 get_shape_mask_uv(vec2 uv) {
	if (pin_mode == 1) {
		return vec2(uv.y, uv.x);
	}
	if (pin_mode == 2) {
		return vec2(clamp(uv.x * uv.y, 0.0, 1.0), clamp(max(uv.x, uv.y), 0.0, 1.0));
	}
	return uv;
}

void vertex() {
	float free_edge = get_free_edge(UV);
	vec2 wave_axes = get_wave_axes(UV);
	float wave = sin(TIME * wave_speed + wave_axes.x * 5.5 + wave_axes.y * 2.2) * wave_strength * free_edge;
	float flutter = cos(TIME * wave_speed * 1.37 + wave_axes.x * 9.0 + wave_axes.y * 3.0) * wave_strength * 0.45 * free_edge;
	VERTEX.z += wave + flutter + side_drag * free_edge;
}

void fragment() {
	if (base_color.a <= alpha_cutoff) {
		discard;
	}
	if (use_shape_mask) {
		vec3 mask_sample = texture(shape_mask_texture, get_shape_mask_uv(UV)).rgb;
		float mask_value = dot(mask_sample, vec3(0.3333, 0.3333, 0.3333));
		if (mask_value <= shape_mask_cutoff) {
			discard;
		}
	}
	vec3 color = base_color.rgb;
	if (use_flag_texture) {
		vec4 flag_sample = texture(flag_texture, UV);
		if (flag_sample.a <= alpha_cutoff) {
			discard;
		}
		color = flag_sample.rgb;
	}

	if (use_emblem_texture) {
		vec2 emblem_uv = (UV - vec2(0.5)) * emblem_uv_scale + vec2(0.5) + emblem_uv_offset;
		if (all(greaterThanEqual(emblem_uv, vec2(0.0))) && all(lessThanEqual(emblem_uv, vec2(1.0)))) {
			vec4 emblem = texture(emblem_texture, emblem_uv);
			vec3 emblem_rgb = emblem_use_texture_color ? emblem.rgb : emblem_color.rgb;
			color = mix(color, emblem_rgb, emblem.a * emblem_strength);
		}
	}

	float warp = sin((UV.y + UV.x * 0.17) * cloth_weave_scale);
	float weft = sin((UV.x - UV.y * 0.11) * cloth_weave_scale * 0.62);
	float weave = (warp * 0.55 + weft * 0.45) * cloth_weave_strength;
	color *= clamp(1.0 + weave, 0.88, 1.10);

	ALBEDO = color;
	METALLIC = 0.0;
	ROUGHNESS = cloth_roughness;
	SPECULAR = 0.04;
}
