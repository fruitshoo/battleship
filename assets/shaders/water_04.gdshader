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

// Wave uniforms
uniform float wave_speed : hint_range(0.0, 5.0) = 1.2;
uniform float wave_freq : hint_range(0.0, 2.0) = 0.05;
uniform float wave_amp : hint_range(0.0, 5.0) = 0.5;

// FOAM UNIFORMS
uniform vec3 foam_color : source_color = vec3(0.9, 0.95, 1.0);
uniform float foam_depth_start : hint_range(0.0, 5.0, 0.01) = 0.0;
uniform float foam_depth_end : hint_range(0.0, 15.0, 0.01) = 0.3;
uniform float foam_noise_scale : hint_range(0.0, 10.0, 0.01) = 2.0;
uniform float foam_noise_speed : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float foam_cutoff : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float foam_crest_threshold : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float foam_crest_amount : hint_range(0.0, 10.0, 0.1) = 0.3;

// NEW FOAM DETAILS (Voronoi & Outline)
uniform vec3 foam_edge_color : source_color = vec3(0.05, 0.1, 0.2);
uniform vec2 foam_edge_offset = vec2(0.02, 0.02);
uniform float voronoi_scale : hint_range(0.0, 50.0) = 9.0;
uniform float voronoi_strength : hint_range(0.0, 8.0) = 0.8;

// CAUSTICS UNIFORMS
uniform sampler2D caustics_texture : filter_linear_mipmap, repeat_enable;
uniform float caustics_scale : hint_range(0.1, 10.0, 0.1) = 2.0;
uniform float caustics_speed : hint_range(0.0, 1.0, 0.01) = 0.1;
uniform float caustics_intensity : hint_range(0.0, 2.0, 0.1) = 0.8;
uniform float caustics_depth_fade : hint_range(0.0, 1.0, 0.01) = 0.7;

vec3 screen(vec3 base, vec3 blend){
	return 1.0 - (1.0 - base) * (1.0 - blend);
}

// -----------------------------------------------------------------------------
// NOISE & VORONOI FUNCTIONS FOR FOAM
// -----------------------------------------------------------------------------
float hash12(vec2 p) {
    uvec2 q = uvec2(ivec2(p)) * uvec2(1597334677u, 3812015801u);
    uint n = (q.x ^ q.y) * 1597334677u;
    return float(n) * (1.0 / 4294967295.0);
}

float hash13(vec3 p) {
    uvec3 q = uvec3(ivec3(p)) * uvec3(1597334677u, 3812015801u, 2798796415u);
    uint n = (q.x ^ q.y ^ q.z) * 1597334677u;
    return float(n) * (1.0 / 4294967295.0);
}

float hash3d(vec3 p) { return hash13(p); }

vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

float noise(in vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return -1.0 + 2.0 * mix(mix(hash12(i + vec2(0.0, 0.0)), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float noise3d(in vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(
            mix(hash3d(i + vec3(0.0, 0.0, 0.0)), hash3d(i + vec3(1.0, 0.0, 0.0)), f.x),
            mix(hash3d(i + vec3(0.0, 1.0, 0.0)), hash3d(i + vec3(1.0, 1.0, 0.0)), f.x),
            f.y
        ),
        mix(
            mix(hash3d(i + vec3(0.0, 0.0, 1.0)), hash3d(i + vec3(1.0, 0.0, 1.0)), f.x),
            mix(hash3d(i + vec3(0.0, 1.0, 1.0)), hash3d(i + vec3(1.0, 1.0, 1.0)), f.x),
            f.y
        ),
        f.z
    );
}

// 2D Voronoi noise for cell-like patterns (foam clumps/bubbles)
float voronoi(vec2 uv) {
    vec2 n = floor(uv);
    vec2 f = fract(uv);
    float m_dist = 1.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = hash22(n + g);
            // Animate the point within the cell
            o = 0.5 + 0.5 * sin(TIME * foam_noise_speed + 6.2831 * o);
            vec2 r = g - f + o;
            float d = dot(r, r);
            m_dist = min(m_dist, d);
        }
    }
    return m_dist;
}

float fbm_voronoi(vec2 uv) {
    float v = 0.0;
    float a = 0.5;
    vec2 shift = vec2(100.0);
    mat2 rot = mat2(vec2(cos(0.5), sin(0.5)), vec2(-sin(0.5), cos(0.5)));
    for (int i = 0; i < 3; i++) {
        float val = 1.0 - voronoi(uv);
        val = pow(val, 2.0); // Sharpen bubbles
        v += a * val;
        uv = rot * uv * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}
// -----------------------------------------------------------------------------

varying vec3 uv_world_pos;

void vertex() {
	// Called for every vertex the material is visible on.
	uv_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// 거스트너/사인 하이브리드 부드러운 파도
	float time = TIME * wave_speed;
	float w1 = sin(uv_world_pos.x * wave_freq + time) * wave_amp;
	float w2 = cos(uv_world_pos.z * wave_freq * 0.82 + time * 1.1) * wave_amp * 0.8;
	
	// 대각선 방향 파도 추가로 자연스러움 극대화
	float w3 = sin((uv_world_pos.x + uv_world_pos.z) * wave_freq * 0.6 - time * 0.9) * wave_amp * 0.5;
	
	float wave_height = w1 + w2 + w3;
	VERTEX.y += wave_height;
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

	// -------------------------------------------------------------------------
	// CAUSTICS (수중 일렁임)
	// -------------------------------------------------------------------------
	vec3 bg_world_pos = (INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0)).xyz;
	// 동차 좌표 나누기
	vec4 bg_world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	bg_world_pos = bg_world.xyz / bg_world.w;
	
	float caustics_added = 0.0;
	if (depth_diff > 0.0) {
		vec2 caustics_uv1 = bg_world_pos.xz * caustics_scale;
		caustics_uv1.x += TIME * caustics_speed;
		
		vec2 caustics_uv2 = bg_world_pos.xz * caustics_scale * 0.7;
		caustics_uv2.y -= TIME * caustics_speed * 0.8;
		
		float caustics_sample1 = texture(caustics_texture, caustics_uv1).r;
		float caustics_sample2 = texture(caustics_texture, caustics_uv2).r;
		float caustics_value = caustics_sample1 * caustics_sample2;
		
		float caustics_fade = 1.0 - clamp(depth_diff * caustics_depth_fade, 0.0, 1.0);
		caustics_added = caustics_value * caustics_intensity * caustics_fade;
	}

	// 깊이에 따른 물 색조 혼합
	vec3 water_color = mix(secondary_color.rgb, primary_color.rgb, beers_blend);
	water_color += vec3(caustics_added); // Add caustics
	
	// 월드 UV 기반 물결 이동
	vec2 world_uv = uv_world_pos.xz / uv_scale;
	vec2 uv_movement = movement_direction * TIME * movement_strength;
	
	vec3 n1 = texture(normalmap_a, world_uv + uv_movement).rgb;
	vec3 n2 = texture(normalmap_b, world_uv - uv_movement * 0.5).rgb;
	
	// 부적절한 일반 덧셈 대신 올바른 노멀 믹스
	vec3 normal_blend = mix(n1, n2, 0.5);
	
	// -------------------------------------------------------------------------
	// FOAM (물 가장자리 거품)
	// -------------------------------------------------------------------------
	float foam_mask_primary = 0.0;
	float foam_mask_shadow = 0.0;
	
	// 깊이가 얕을수록(0.0에 가까울수록) 값이 1.0(거품 생성)에 가까워짐
	float depth_foam_factor = 1.0 - smoothstep(foam_depth_start, foam_depth_end, depth_diff);
	float wave_crest_factor = smoothstep(foam_crest_threshold, foam_crest_threshold - 0.1, NORMAL.y);
	wave_crest_factor *= foam_crest_amount;
	float foam_level = clamp(depth_foam_factor + wave_crest_factor, 0.0, 1.0);
	
	// 거품 워핑용
	vec2 flow_uv = uv_world_pos.xz * 0.5 + TIME * 0.05 * foam_noise_speed;
	vec2 warp = vec2(
		noise(flow_uv),
		noise(flow_uv + vec2(5.2, 1.3))
	) * 0.5;
	
	// 스카이박스가 아닌 얕은 지형 위에서 또는 겹쳤을 때
	if (depth > 0.0001 && depth < 0.9999) {
		vec2 foam_uv = uv_world_pos.xz * foam_noise_scale + warp;
		// Emergence (Pulsing/Clumping)
		float emergence_noise = noise3d(vec3(uv_world_pos.xz * 0.5, TIME * 0.2 * foam_noise_speed));
		emergence_noise = smoothstep(0.0, 1.0, emergence_noise * 0.5 + 0.5);
		
		float effective_emergence = mix(emergence_noise, 1.0, foam_level);
		
		// Main Foam
		float foam_noise_val = fbm_voronoi(foam_uv);
		foam_noise_val *= effective_emergence;
		
		// Shadow Foam
		vec2 foam_uv_shadow = (uv_world_pos.xz + foam_edge_offset) * foam_noise_scale + warp;
		float foam_noise_shadow_val = fbm_voronoi(foam_uv_shadow);
		foam_noise_shadow_val *= effective_emergence;
		
		// Clumping / Mask Generation
		float combined_noise = foam_noise_val + foam_level;
		float combined_shadow = foam_noise_shadow_val + foam_level;
		
		foam_mask_primary = smoothstep(foam_cutoff + 0.5, foam_cutoff + 0.6, combined_noise);
		float shadow_shape = smoothstep(foam_cutoff + 0.5, foam_cutoff + 0.6, combined_shadow);
		foam_mask_shadow = clamp(shadow_shape - foam_mask_primary, 0.0, 1.0);
	}
	
	// Bubbles inside
	float voronoi_val = 1.0 - sqrt(voronoi(uv_world_pos.xz * voronoi_scale + warp));
	voronoi_val = smoothstep(0.2, 0.8, voronoi_val);
	float bubble_alpha = 1.0 - clamp((1.0 - voronoi_val) * voronoi_strength, 0.0, 1.0);

	// 최종 알베도 색상 혼합 (+ 시야각 반사광)
	vec3 water_base = mix(water_color, primary_color.rgb, basic_fresnel * 0.5);
	vec3 final_albedo = water_base + (basic_fresnel * 0.2);
	
	// 거품 마스크에서 ALPHA 부스트 (거품이 얕아서 투명해지지 않도록)
	float primary_foam_alpha = foam_mask_primary * bubble_alpha;
	float final_alpha = clamp(1.0 - (beers_blend * 0.85) + water_transparency + primary_foam_alpha, 0.0, 1.0);
	
	// Apply Foam
	final_albedo = mix(final_albedo, foam_edge_color, foam_mask_shadow);
	final_albedo = mix(final_albedo, foam_color, primary_foam_alpha);
	
	// 출력
	ALBEDO = final_albedo;
	// 깊을수록 점진적으로 불투명해짐 (0.85 배수로 표면 근처에서 물의 부피감이 느껴지게 함)
	ALPHA = final_alpha;
	
	// Make foam rougher
	ROUGHNESS = mix(roughness, 0.8, primary_foam_alpha + foam_mask_shadow);
	
	NORMAL_MAP = normal_blend;
	NORMAL_MAP_DEPTH = max(normalmap_a_strength, normalmap_b_strength);
}
