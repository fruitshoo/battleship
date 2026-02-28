shader_type spatial;

uniform vec4 primary_color : source_color = vec4(0.1, 0.4, 0.6, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.02, 0.1, 0.2, 1.0);

uniform float roughness : hint_range(0.0, 1.0) = 0.1;

uniform sampler2D normalmap_a : hint_normal;
uniform sampler2D normalmap_b : hint_normal;
uniform float normalmap_a_strength : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float normalmap_b_strength : hint_range(0.0, 1.0, 0.01)= 0.25;
uniform vec2 movement_direction = vec2(0.2, 0.1);
uniform float movement_strength = 0.12;

uniform float uv_scale : hint_range(1.0, 500.0) = 150.0;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, repeat_disable, filter_nearest;
uniform float depth_distance : hint_range(0.0, 50.0, 0.1) = 4.0;
uniform float beers_law : hint_range(0.0, 20.0, 0.1) = 2.0;
uniform float water_transparency : hint_range(0.0, 1.0, 0.01) = 0.1;

vec3 screen(vec3 base, vec3 blend){
	return 1.0 - (1.0 - base) * (1.0 - blend);
}

varying vec3 uv_world_pos;

void vertex() {
	// Called for every vertex the material is visible on.
	uv_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

void fragment() {
	// Called for every pixel the material is visible on.
	float basic_fresnel = fresnel(3.0, NORMAL, VIEW);
	
	// Depth texture magic
	float depth = texture(DEPTH_TEXTURE, SCREEN_UV, 0.0).r;
	
	// 안전하고 표준적인 뷰 공간 선형 깊이(Linear Depth) 계산 방식
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	float linear_depth = -view_pos.z; // 카메라로부터 픽셀까지의 거리
	
	vec4 water_view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, FRAGCOORD.z, 1.0);
	water_view_pos.xyz /= water_view_pos.w;
	float water_depth = -water_view_pos.z; // 카메라로부터 수면까지의 거리
	
	// 스카이박스 감지: 하늘 픽셀은 depth 값이 거의 0 (Vulkan)이거나 1에 가까움
	float depth_diff = 1000.0; // 하늘일 경우 매우 깊은 것으로 처리
	if (depth > 0.0001 && depth < 0.9999) {
		depth_diff = max(0.0, linear_depth - water_depth); // 카메라 기준 수심 계산
	}

	// 깊이 차이 계산
	float depth_blend = clamp(depth_diff / depth_distance, 0.0, 1.0);
	float beers_blend = exp(-depth_diff * (1.0 / max(beers_law, 0.001))); // 0으로 나누기 방지

	// 깊이에 따른 물 색조 혼합
	vec3 water_color = mix(secondary_color.rgb, primary_color.rgb, beers_blend);
	
	// 월드 UV 기반 물결 이동
	vec2 world_uv = uv_world_pos.xz / uv_scale;
	vec2 uv_movement = movement_direction * TIME * movement_strength;
	
	vec3 n1 = texture(normalmap_a, world_uv + uv_movement).rgb;
	vec3 n2 = texture(normalmap_b, world_uv - uv_movement * 0.5).rgb;
	
	// 부적절한 일반 덧셈 대신 올바른 노멀 믹스
	vec3 normal_blend = mix(n1, n2, 0.5);
	
	// 최종 알베도 색상 혼합 (+ 시야각 반사광)
	vec3 final_albedo = mix(water_color, primary_color.rgb, basic_fresnel * 0.5);
	final_albedo += basic_fresnel * 0.2; 
	
	// 출력
	ALBEDO = final_albedo;
	ALPHA = clamp(1.0 - beers_blend + water_transparency, 0.0, 1.0);
	ROUGHNESS = roughness;
	
	NORMAL_MAP = normal_blend;
	NORMAL_MAP_DEPTH = max(normalmap_a_strength, normalmap_b_strength);
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
