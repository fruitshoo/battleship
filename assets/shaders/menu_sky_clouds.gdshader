shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

uniform vec4 cloud_color : source_color = vec4(1.0, 0.96, 0.82, 0.82);
uniform vec4 cloud_shadow_color : source_color = vec4(0.50, 0.66, 0.82, 0.48);
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 0.66;
uniform float cloud_scale : hint_range(0.2, 8.0, 0.05) = 1.35;
uniform float detail_scale : hint_range(1.0, 16.0, 0.05) = 5.2;
uniform float drift_speed : hint_range(0.0, 0.2, 0.001) = 0.01;
uniform float cutoff : hint_range(0.0, 1.0, 0.01) = 0.30;
uniform float softness : hint_range(0.01, 0.5, 0.01) = 0.30;
uniform float veil_strength : hint_range(0.0, 0.5, 0.01) = 0.18;
uniform float lower_fade : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float upper_fade : hint_range(0.0, 1.0, 0.01) = 0.94;

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
	for (int i = 0; i < 5; i++) {
		value += noise(p) * amplitude;
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + vec2(7.1, 2.8);
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 p = UV;
	p.x *= 2.15;
	vec2 wind = vec2(TIME * drift_speed, -TIME * drift_speed * 0.2);
	float body = fbm(p * cloud_scale + wind);
	float detail = fbm(p * detail_scale + wind * 2.2 + vec2(3.7, 5.1));
	float wisps = fbm(vec2(p.x * 3.8, p.y * 1.5) + wind * 1.35);
	float density = body * 0.76 + detail * 0.24 + wisps * 0.14;
	float veil = smoothstep(cutoff - 0.18, cutoff + softness, density);
	float cloud = smoothstep(cutoff, cutoff + softness, density);
	cloud *= smoothstep(0.02, 0.50, body + detail * 0.24);

	float lower_mask = smoothstep(0.0, lower_fade, UV.y);
	float upper_mask = 1.0 - smoothstep(upper_fade, 1.0, UV.y);
	float side_mask = smoothstep(0.0, 0.08, UV.x) * (1.0 - smoothstep(0.92, 1.0, UV.x));
	float alpha = (cloud + veil * veil_strength) * lower_mask * upper_mask * side_mask * opacity;
	float shade = smoothstep(0.34, 0.82, detail);
	vec3 color = mix(cloud_shadow_color.rgb, cloud_color.rgb, shade);

	ALBEDO = color;
	ALPHA = alpha;
}
