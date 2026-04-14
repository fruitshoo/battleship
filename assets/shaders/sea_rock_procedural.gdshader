shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

uniform vec4 rock_dark : source_color = vec4(0.09, 0.11, 0.10, 1.0);
uniform vec4 rock_mid : source_color = vec4(0.22, 0.24, 0.20, 1.0);
uniform float pattern_scale : hint_range(0.05, 4.0) = 0.72;
uniform float wet_darkening : hint_range(0.0, 1.0) = 0.32;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;

varying vec3 world_pos;
varying vec3 world_normal;


float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}


float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));

	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}


float fbm(vec3 p) {
	float total = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p * freq) * amp;
		freq *= 2.03;
		amp *= 0.5;
	}
	return total;
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}


void fragment() {
	vec3 p = world_pos * pattern_scale;
	vec3 n = normalize(world_normal);

	float large_noise = fbm(p * 0.62 + vec3(3.1, 0.0, 1.7));
	float grain_noise = fbm(p * 1.35 + vec3(11.0, 7.0, 2.0));
	float top_light = smoothstep(-0.15, 0.95, n.y);
	float color_mix = clamp((large_noise * 0.42) + (top_light * 0.18), 0.0, 1.0);

	vec3 rock = mix(rock_dark.rgb, rock_mid.rgb, color_mix);
	rock *= mix(0.92, 1.08, grain_noise);

	float low_wetness = smoothstep(0.65, -1.15, world_pos.y);
	rock *= mix(1.0, 1.0 - wet_darkening, low_wetness);

	ALBEDO = clamp(rock, vec3(0.0), vec3(1.0));
	ROUGHNESS = roughness_value;
	SPECULAR = 0.18;
}
