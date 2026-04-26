shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D wake_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(0.86, 0.96, 1.0, 1.0);
uniform float frame = 0.0;
uniform int columns = 8;
uniform int rows = 8;
uniform float alpha = 0.0;
uniform float alpha_power = 1.15;

void fragment() {
	int total_frames = max(columns * rows, 1);
	int frame_index = int(mod(floor(frame), float(total_frames)));
	int frame_x = frame_index % columns;
	int frame_y = frame_index / columns;
	vec2 atlas_size = vec2(float(columns), float(rows));
	vec2 atlas_uv = (UV + vec2(float(frame_x), float(frame_y))) / atlas_size;
	vec4 sample_color = texture(wake_texture, atlas_uv);
	float foam_alpha = pow(sample_color.a, alpha_power) * alpha * tint.a;
	ALBEDO = sample_color.rgb * tint.rgb;
	ALPHA = foam_alpha;
}
