extends RefCounted
class_name UiOverlayFx


static func make_vignette_material(
	tint_color: Color,
	focus_point: Vector2,
	vignette_strength: float,
	center_softness: float,
	center_radius: float,
	center_alpha_reduction: float,
	center_lift: Vector3
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform vec4 tint_color : source_color;
uniform vec2 focus_point = vec2(0.5, 0.5);
uniform float vignette_strength = 0.72;
uniform float center_softness = 0.34;
uniform float center_radius = 0.16;
uniform float center_alpha_reduction = 0.26;
uniform vec3 center_lift = vec3(0.03, 0.03, 0.03);

void fragment() {
	vec2 uv = UV;
	float center_distance = distance(uv, focus_point);
	float center_falloff = 1.0 - smoothstep(center_radius, center_radius + center_softness, center_distance);
	float edge_distance = distance(uv, vec2(0.5, 0.5));
	float vignette = smoothstep(0.30, 0.88, edge_distance);
	float alpha = tint_color.a * clamp(0.48 + vignette * vignette_strength - center_falloff * center_alpha_reduction, 0.0, 1.0);
	vec3 color = tint_color.rgb + center_lift * center_falloff;
	COLOR = vec4(color, alpha);
}
"""
	material.shader = shader
	material.set_shader_parameter("tint_color", tint_color)
	material.set_shader_parameter("focus_point", focus_point)
	material.set_shader_parameter("vignette_strength", vignette_strength)
	material.set_shader_parameter("center_softness", center_softness)
	material.set_shader_parameter("center_radius", center_radius)
	material.set_shader_parameter("center_alpha_reduction", center_alpha_reduction)
	material.set_shader_parameter("center_lift", center_lift)
	return material


static func make_radial_darken_material(
	tint_color: Color,
	inner_radius: float,
	outer_radius: float
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform vec4 tint_color : source_color;
uniform float inner_radius = 0.42;
uniform float outer_radius = 0.72;

void fragment() {
	float edge = smoothstep(inner_radius, outer_radius, distance(UV, vec2(0.5)));
	COLOR = vec4(tint_color.rgb, tint_color.a * edge);
}
"""
	material.shader = shader
	material.set_shader_parameter("tint_color", tint_color)
	material.set_shader_parameter("inner_radius", inner_radius)
	material.set_shader_parameter("outer_radius", outer_radius)
	return material


static func make_screen_edge_motion_material(
	edge_vignette: float = 0.18,
	edge_blur: float = 0.92,
	motion_boost: float = 0.0,
	focus_point: Vector2 = Vector2(0.5, 0.55)
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float edge_vignette = 0.18;
uniform float edge_blur = 0.92;
uniform float motion_boost = 0.0;
uniform vec2 focus_point = vec2(0.5, 0.55);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 screen_px = SCREEN_PIXEL_SIZE;
	float center_distance = distance(uv, focus_point);
	float edge_mask = smoothstep(0.14, 0.72, center_distance);
	float blur_amount = clamp(edge_blur + motion_boost, 0.0, 0.98);
	float blur_mix = edge_mask * blur_amount;
	float blur_radius_px = 2.0 + edge_blur * 42.0 + motion_boost * 12.0;
	float blur_lod = clamp(1.0 + edge_blur * 7.0 + motion_boost * 3.0, 0.0, 6.0);
	vec2 blur_offset = screen_px * blur_radius_px;

	vec4 center = texture(screen_tex, uv);
	vec4 tap_blur = center * 0.16;
	tap_blur += texture(screen_tex, uv + vec2(blur_offset.x, 0.0)) * 0.10;
	tap_blur += texture(screen_tex, uv - vec2(blur_offset.x, 0.0)) * 0.10;
	tap_blur += texture(screen_tex, uv + vec2(0.0, blur_offset.y)) * 0.10;
	tap_blur += texture(screen_tex, uv - vec2(0.0, blur_offset.y)) * 0.10;
	tap_blur += texture(screen_tex, uv + blur_offset) * 0.075;
	tap_blur += texture(screen_tex, uv - blur_offset) * 0.075;
	tap_blur += texture(screen_tex, uv + vec2(blur_offset.x, -blur_offset.y)) * 0.075;
	tap_blur += texture(screen_tex, uv + vec2(-blur_offset.x, blur_offset.y)) * 0.075;
	vec4 mip_blur = textureLod(screen_tex, uv, blur_lod);
	vec4 blur = mix(tap_blur, mip_blur, clamp(edge_mask * 0.96, 0.0, 0.96));

	vec3 mixed_rgb = mix(center.rgb, blur.rgb, clamp(blur_mix, 0.0, 0.90));
	float vignette = smoothstep(0.24, 0.94, center_distance);
	float dim_strength = edge_vignette + motion_boost * 0.18;
	mixed_rgb *= 1.0 - vignette * dim_strength;
	mixed_rgb = mix(mixed_rgb, vec3(dot(mixed_rgb, vec3(0.299, 0.587, 0.114))), vignette * motion_boost * 0.08);
	COLOR = vec4(mixed_rgb, 1.0);
}
"""
	material.shader = shader
	set_screen_edge_motion_params(material, edge_vignette, edge_blur, motion_boost, focus_point)
	return material


static func set_screen_edge_motion_params(
	material: ShaderMaterial,
	edge_vignette: float,
	edge_blur: float,
	motion_boost: float,
	focus_point: Vector2 = Vector2(0.5, 0.55)
) -> void:
	if material == null:
		return
	material.set_shader_parameter("edge_vignette", edge_vignette)
	material.set_shader_parameter("edge_blur", edge_blur)
	material.set_shader_parameter("motion_boost", motion_boost)
	material.set_shader_parameter("focus_point", focus_point)
