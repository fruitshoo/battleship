shader_type spatial;

uniform vec4 primary_color : source_color = vec4(0.1, 0.4, 0.6, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.02, 0.1, 0.2, 1.0);

uniform float roughness : hint_range(0.0, 1.0) = 0.125;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

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

// Wave parameters (New)
uniform float sea_height : hint_range(0.0, 5.0) = 0.6;
uniform float sea_choppy : hint_range(0.0, 10.0) = 4.0;
uniform float sea_speed : hint_range(0.0, 5.0) = 0.8;
uniform float sea_freq : hint_range(0.0, 0.5) = 0.16;
uniform int ITER_GEOMETRY = 3;
uniform int ITER_FRAGMENT = 5;
const mat2 octave_m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));

// FOAM UNIFORMS
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float foam_depth_start : hint_range(0.0, 5.0, 0.01) = 0.8;
uniform float foam_depth_end : hint_range(0.0, 5.0, 0.01) = 0.0;
uniform float foam_noise_scale : hint_range(0.0, 10.0, 0.01) = 2.0;
uniform float foam_noise_speed : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float foam_cutoff : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float foam_crest_threshold : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float foam_crest_amount : hint_range(0.0, 10.0, 0.1) = 2.0;

// NEW FOAM DETAILS (Texture & Outline)
uniform sampler2D foam_texture : filter_linear_mipmap, repeat_enable;
uniform vec3 foam_edge_color : source_color = vec3(0.0, 0.0, 0.05);
uniform vec2 foam_edge_offset = vec2(0.02, 0.02);

// CAUSTICS UNIFORMS
uniform sampler2D caustics_texture : filter_linear_mipmap, repeat_enable;
uniform float caustics_scale : hint_range(0.1, 10.0, 0.1) = 2.0;
uniform float caustics_speed : hint_range(0.0, 1.0, 0.01) = 0.1;
uniform float caustics_intensity : hint_range(0.0, 2.0, 0.1) = 0.8;
uniform float caustics_depth_fade : hint_range(0.0, 1.0, 0.01) = 0.7;

// UNDERWATER FOG UNIFORMS
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform vec3 underwater_fog_color : source_color = vec3(0.0, 0.05, 0.1);
uniform float underwater_fade_start_depth : hint_range(0.0, 50.0, 0.1) = 0.5;

// Refraction & Smoothing Settings
uniform float refraction_strength : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float refraction_distance_fade : hint_range(0.0, 100.0, 1.0) = 5.0;
uniform float normal_epsilon : hint_range(0.001, 1.0) = 0.01;
uniform float normal_smoothness_dist : hint_range(0.0, 1000.0) = 50.0;
uniform float max_depth : hint_range(0.1, 50.0, 0.1) = 10.0;

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

// (Procedural Voronoi removed - using texture instead)

float noise(in vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return -1.0 + 2.0 * mix(mix(hash12(i + vec2(0.0, 0.0)), hash12(i + vec2(1.0, 0.0)), u.x),
                            mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float sea_octave(vec2 uv, float choppy) {
    uv += noise(uv);
    vec2 wv = 1.0 - abs(sin(uv));
    vec2 swv = abs(cos(uv));
    wv = mix(wv, swv, wv);
    return pow(1.0 - pow(wv.x * wv.y, 0.65), choppy);
}

float map(vec3 p, float time) {
    float freq = sea_freq;
    float amp = sea_height;
    float choppy = sea_choppy;
    vec2 uv = p.xz;
    uv.x *= 0.75;
    float h = 0.0;
    for (int i = 0; i < ITER_GEOMETRY; i++) {
        float d = sea_octave((uv + time * sea_speed) * freq, choppy);
        d += sea_octave((uv - time * sea_speed) * freq, choppy);
        h += d * amp;
        uv *= octave_m;
        freq *= 1.9;
        amp *= 0.22;
        choppy = mix(choppy, 1.0, 0.2);
    }
    return p.y - h;
}

float map_detailed(vec3 p, float time) {
    float freq = sea_freq;
    float amp = sea_height;
    float choppy = sea_choppy;
    vec2 uv = p.xz;
    uv.x *= 0.75;
    float h = 0.0;
    for (int i = 0; i < ITER_FRAGMENT; i++) {
        float d = sea_octave((uv + time * sea_speed) * freq, choppy);
        d += sea_octave((uv - time * sea_speed) * freq, choppy);
        h += d * amp;
        uv *= octave_m;
        freq *= 1.9;
        amp *= 0.22;
        choppy = mix(choppy, 1.0, 0.2);
    }
    return p.y - h;
}

vec3 get_normal_detailed(vec3 p, float eps, float time) {
    vec3 n;
    n.y = map_detailed(p, time);
    n.x = map_detailed(vec3(p.x + eps, p.y, p.z), time) - n.y;
    n.z = map_detailed(vec3(p.x, p.y, p.z + eps), time) - n.y;
    n.y = eps;
    return normalize(n);
}
// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

varying vec3 world_vert;
varying float wave_height;
varying vec3 vertex_normal_world;

// -----------------------------------------------------------------------------
// GET LINEAR DEPTH FROM DEPTH TEXTURE
float get_linear_depth(sampler2D d_tex, vec2 uv, mat4 inv_proj) {
    float depth = texture(d_tex, uv).x;
    vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    ndc.z = depth * 2.0 - 1.0;
#endif
    vec4 view = inv_proj * vec4(ndc, 1.0);
    return -view.z / view.w;
}

void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    wave_height = -map(world_pos, TIME);
    VERTEX.y = wave_height;
    world_vert = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    
    float vertex_eps = 0.1;
    float h_center = wave_height;
    float h_x = -map(world_pos + vec3(vertex_eps, 0.0, 0.0), TIME);
    float h_z = -map(world_pos + vec3(0.0, 0.0, vertex_eps), TIME);
    vec3 n_geom = normalize(vec3(h_center - h_x, vertex_eps, h_center - h_z));
    vertex_normal_world = n_geom;
}

float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

void fragment() {
	// Called for every pixel the material is visible on.
	float basic_fresnel = fresnel(3.0, NORMAL, VIEW);
	
    // Linear depth of the water surface itself
    float water_linear_depth = -VERTEX.z;
    // Linear depth of what's behind the water
    float bg_linear_depth = get_linear_depth(DEPTH_TEXTURE, SCREEN_UV, INV_PROJECTION_MATRIX);
    float thickness = max(0.0, bg_linear_depth - water_linear_depth);
    
    // -------------------------------------------------------------------------
    // NORMALS & DISTANCE SMOOTHING
    // -------------------------------------------------------------------------
    float dist_to_cam = length(VERTEX);
    float lod_eps = max(normal_epsilon, dist_to_cam * 0.005);
    vec3 animated_detailed_normal = get_normal_detailed(world_vert, lod_eps, TIME);
    float smooth_factor = clamp((dist_to_cam - normal_smoothness_dist) / 200.0, 0.0, 1.0);
    vec3 final_normal = mix(animated_detailed_normal, vertex_normal_world, smooth_factor);
    NORMAL = (VIEW_MATRIX * vec4(final_normal, 0.0)).xyz;
    
    // -------------------------------------------------------------------------
    // REFRACTION (굴절)
    // -------------------------------------------------------------------------
    vec3 view_vertex_normal = (VIEW_MATRIX * vec4(vertex_normal_world, 0.0)).xyz;
    vec2 normal_offset = NORMAL.xy - view_vertex_normal.xy;
    float ref_dist_factor = clamp(refraction_distance_fade / max(0.1, dist_to_cam), 0.0, 1.0);
    float ref_depth_mask = smoothstep(0.0, max_depth, thickness);
    vec2 refraction_offset = normal_offset * refraction_strength * ref_dist_factor * ref_depth_mask * 0.05;

    vec2 distorted_uv = SCREEN_UV + refraction_offset; // Apply Offset

    // Fix ghosting: 굴절된 UV의 깊이가 수면보다 앞쪽이면 굴절 취소
    float distorted_bg_depth = get_linear_depth(DEPTH_TEXTURE, distorted_uv, INV_PROJECTION_MATRIX);
    if (distorted_bg_depth < water_linear_depth - 0.001) {
        distorted_uv = SCREEN_UV;
        distorted_bg_depth = bg_linear_depth;
    }

    vec3 screen_color = texture(SCREEN_TEXTURE, distorted_uv).rgb;
    thickness = max(0.0, distorted_bg_depth - water_linear_depth);

    // Legacy support for other parts of the shader
    float depth_diff = thickness;

    // 깊이 차이(수심) 기반 블렌딩 계수
	float depth_blend = clamp(depth_diff / depth_distance, 0.0, 1.0);
	float beers_blend = exp(-depth_diff * (1.0 / max(beers_law, 0.001)));

    // -------------------------------------------------------------------------
    // CAUSTICS (수중 일렁임)
    // -------------------------------------------------------------------------
    // 굴절된 UV를 기반으로 바닥 월드 좌표 복원 (가장 정확한 위치에 투사)
    vec4 bg_ndc = vec4(distorted_uv * 2.0 - 1.0, texture(DEPTH_TEXTURE, distorted_uv).x, 1.0);
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    bg_ndc.z = bg_ndc.z * 2.0 - 1.0;
    #endif
    vec4 bg_world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * bg_ndc;
    vec3 bg_world_pos = bg_world.xyz / bg_world.w;

    if (thickness > 0.0) {
        vec3 bg_normal = normalize(cross(dFdx(bg_world_pos), dFdy(bg_world_pos)));
        vec3 blending = abs(bg_normal);
        blending = normalize(max(blending, 0.00001)); // Prevent divide by zero
        float b = (blending.x + blending.y + blending.z);
        blending /= vec3(b, b, b); // Normalize weights

        // XZ Projection (Top/Bottom)
        vec2 uv_xz = bg_world_pos.xz * caustics_scale;
        vec2 uv_xz2 = bg_world_pos.xz * caustics_scale * 0.7;
        uv_xz.x += TIME * caustics_speed;
        uv_xz2.y -= TIME * caustics_speed * 0.8;
        float c_xz = texture(caustics_texture, uv_xz).r * texture(caustics_texture, uv_xz2).r;

        // XY Projection (Front/Back)
        vec2 uv_xy = bg_world_pos.xy * caustics_scale;
        vec2 uv_xy2 = bg_world_pos.xy * caustics_scale * 0.7;
        uv_xy.x += TIME * caustics_speed;
        uv_xy2.y -= TIME * caustics_speed * 0.8;
        float c_xy = texture(caustics_texture, uv_xy).r * texture(caustics_texture, uv_xy2).r;

        // ZY Projection (Left/Right)
        vec2 uv_zy = bg_world_pos.zy * caustics_scale;
        vec2 uv_zy2 = bg_world_pos.zy * caustics_scale * 0.7;
        uv_zy.x += TIME * caustics_speed;
        uv_zy2.y -= TIME * caustics_speed * 0.8;
        float c_zy = texture(caustics_texture, uv_zy).r * texture(caustics_texture, uv_zy2).r;

        // Blend all projections based on unlit surface normal
        float caustics_value = c_xz * blending.y + c_xy * blending.z + c_zy * blending.x;
        
        float caustics_fade = 1.0 - clamp(thickness * caustics_depth_fade, 0.0, 1.0);
        // SCREEN_COLOR에 직접 더하여 바닥 지형이 일렁이게 함
        screen_color += caustics_value * caustics_intensity * caustics_fade;
    }

    // 깊이에 따른 물 색조 혼합
    vec3 water_color = mix(secondary_color.rgb, primary_color.rgb, beers_blend);
	
	// 월드 UV 기반 물결 이동
	vec2 world_uv = world_vert.xz / uv_scale;
	vec2 uv_movement = movement_direction * TIME * movement_strength;
	
	vec3 n1 = texture(normalmap_a, world_uv + uv_movement).rgb;
	vec3 n2 = texture(normalmap_b, world_uv - uv_movement * 0.5).rgb;
	
	// 부적절한 일반 덧셈 대신 올바른 노멀 믹스
	vec3 normal_blend = mix(n1, n2, 0.5);
	
    float basic_fresnel_real = fresnel(3.0, NORMAL, VIEW);

    // 최종 알베도 색상 혼합 (+ 프레넬)
    vec3 water_base = mix(water_color, primary_color.rgb, basic_fresnel_real * 0.5);
    vec3 final_albedo = water_base + (basic_fresnel_real * 0.2);

    // -------------------------------------------------------------------------
    // UNDERWATER FOG (수중 안개/탁도)
    // -------------------------------------------------------------------------
    float fog_fade_range = max(0.001, max_depth - underwater_fade_start_depth);
    float fog_depth_ratio = clamp((depth_diff - underwater_fade_start_depth) / fog_fade_range, 0.0, 1.0);
    vec3 albedo_with_fog = mix(final_albedo, underwater_fog_color, fog_depth_ratio);

    // Apply Refracted Screen Color
    float transparency_factor = clamp(beers_blend + water_transparency, 0.0, 1.0);
    ALBEDO = mix(albedo_with_fog, screen_color, transparency_factor);

    // -------------------------------------------------------------------------
    // FOAM (물 가장자리 거품)
    // -------------------------------------------------------------------------
    float foam_mask_primary = 0.0;
    float foam_mask_shadow  = 0.0;

    // To create swirling, flowing motion that mimics foam being carried by water currents, we use domain warping
    vec2 flow_uv = world_vert.xz * 0.5 + TIME * 0.05 * foam_noise_speed;
    vec2 warp = vec2(
        noise(flow_uv),
        noise(flow_uv + vec2(5.2, 1.3))
    ) * 1.5; // Warping 강도 대폭 증가

    // 깎아지른 절벽이나 직육면체(큐브)의 모서리(꼭짓점)가 너무 선명하게 직각으로 떨어지는 것을 방지하기 위해,
    // 깊이 판정 자체를 노이즈로 울퉁불퉁하게 왜곡(Distort)하여 곡선형으로 만듭니다.
    float base_foam_contact = 1.0 - smoothstep(0.0, foam_depth_start, depth_diff);
    
    // 꼭짓점/직선을 둥글게 허물기 위한 노이즈 결합
    float edge_mask = smoothstep(0.0, 0.5, base_foam_contact);
    float distorted_contact = base_foam_contact + (warp.x * 0.8 * edge_mask) + (warp.y * 0.4 * edge_mask);

    // 기준점(0.5)을 넓게 넘는 곳만 거품 영역으로 취급하여 경계를 부드럽게 퍼뜨립니다.
    float depth_foam_factor = clamp(distorted_contact, 0.0, 1.0);
    
    // 파도 마루에 따른 폼
    float wave_crest_factor = smoothstep(foam_crest_threshold, foam_crest_threshold - 0.1, final_normal.y);
    wave_crest_factor *= foam_crest_amount;
    
    float foam_level = clamp(depth_foam_factor + wave_crest_factor, 0.0, 1.0);

    if (distorted_bg_depth > water_linear_depth) {
        // 두 개의 서로 다른 스케일과 속도를 가진 방향으로 텍스처를 읽어와 섞습니다. (Tiling/격자 무늬 숨기기)
        vec2 foam_uv1 = world_vert.xz * foam_noise_scale + warp;
        foam_uv1 += vec2(TIME * 0.03 * foam_noise_speed, TIME * 0.02 * foam_noise_speed);
        
        vec2 foam_uv2 = world_vert.xz * foam_noise_scale * 0.7 - warp * 0.8;
        foam_uv2 += vec2(TIME * -0.02 * foam_noise_speed, TIME * 0.04 * foam_noise_speed);

        // Emergence (Pulsing/Clumping)
        float emergence_noise = noise3d(vec3(world_vert.xz * 0.5, TIME * 0.2 * foam_noise_speed));
        emergence_noise = smoothstep(0.0, 1.0, emergence_noise * 0.5 + 0.5);

        float effective_emergence = mix(emergence_noise, 1.0, foam_level);

        // Main Foam Sample using Dual Textures
        float tex1 = texture(foam_texture, foam_uv1).r;
        float tex2 = texture(foam_texture, foam_uv2).r;
        float foam_noise_val = max(tex1, tex2 * 0.8) * effective_emergence;

        // Shadow Sample using Dual Textures
        vec2 shadow_offset = foam_edge_offset;
        float tex_shadow1 = texture(foam_texture, foam_uv1 + shadow_offset).r;
        float tex_shadow2 = texture(foam_texture, foam_uv2 + shadow_offset).r;
        float foam_noise_shadow_val = max(tex_shadow1, tex_shadow2 * 0.8) * effective_emergence;

        // 다시 '더하기' 임계값 판정으로 복구하여 가장자리 거품의 두께와 풍성함을 살립니다.
        float combined_noise  = foam_noise_val + foam_level;
        float combined_shadow = foam_noise_shadow_val + foam_level;

        float noise_mask = smoothstep(foam_cutoff + 0.6, foam_cutoff + 0.9, combined_noise);
        float shadow_noise_mask = smoothstep(foam_cutoff + 0.5, foam_cutoff + 0.9, combined_shadow);

        // 깊은 바다 무조건 차단 (if the fragment lacks foam level entirely, kill it)
        float isolation_mask = smoothstep(0.01, 0.1, foam_level); 
        
        foam_mask_primary = noise_mask * isolation_mask;
        float shadow_shape = shadow_noise_mask * isolation_mask;
        
        foam_mask_shadow = clamp(shadow_shape - foam_mask_primary, 0.0, 1.0);
    }

    // Apply foam
    ALBEDO = mix(ALBEDO, foam_edge_color, foam_mask_shadow);
    ALBEDO = mix(ALBEDO, foam_color, foam_mask_primary);

    ALPHA = clamp(1.0 - (beers_blend * 0.85) + water_transparency + foam_mask_primary, 0.0, 1.0);

    // Make foam rougher
    ROUGHNESS = mix(roughness, 0.8, foam_mask_primary + foam_mask_shadow);

    SPECULAR = specular;
    METALLIC = metallic;
}
