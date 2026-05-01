shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

uniform vec4 mist_color : source_color = vec4(0.70, 0.82, 0.90, 0.22);
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 0.20;
uniform float noise_scale : hint_range(0.5, 12.0, 0.05) = 3.4;
uniform float drift_speed : hint_range(0.0, 0.2, 0.001) = 0.018;
uniform float vertical_center : hint_range(0.0, 1.0, 0.01) = 0.48;
uniform float vertical_width : hint_range(0.05, 1.0, 0.01) = 0.42;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += noise(p) * amplitude;
		p = mat2(vec2(1.7, 0.9), vec2(-0.9, 1.7)) * p + vec2(5.3, 2.1);
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 p = UV;
	p.x *= 2.2;
	float haze_noise = fbm(p * noise_scale + vec2(TIME * drift_speed, TIME * drift_speed * 0.18));
	float vertical = 1.0 - smoothstep(vertical_width, vertical_width + 0.24, abs(UV.y - vertical_center));
	float edge = smoothstep(0.0, 0.08, UV.x) * (1.0 - smoothstep(0.92, 1.0, UV.x));
	float alpha = opacity * vertical * edge * smoothstep(0.24, 0.82, haze_noise);
	ALBEDO = mist_color.rgb;
	ALPHA = alpha;
}
