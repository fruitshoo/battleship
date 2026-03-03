shader_type spatial;
render_mode unshaded;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform float max_depth : hint_range(0.1, 50.0, 0.1) = 10.0; // Max depth to visualize, controls brightness
uniform float water_level : hint_range(-10.0, 10.0, 0.1) = 0.0; // Base height of the water surface

void fragment() {
    float depth = texture(DEPTH_TEXTURE, SCREEN_UV).x; // Reconstruct World Position from Depth Buffer

    vec3 ndc;
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
        // Compatibility (OpenGL) uses a [-1, 1] Z range for NDC
        ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
    #else
        // Forward+ and Mobile (Vulkan) use a [0, 1] Z range for NDC
        ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
    #endif

    // Use inverse matrices to transform from screen space to world space.
    vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    vec3 world_pos = world.xyz / world.w;

    float surface_y = water_level; // Evaluate Water Surface Height

    // Calculate Water Depth (Thickness)
    // Subtract the world position Y from the surface Y.
    float thickness = surface_y - world_pos.y;

    thickness = max(0.0, thickness); // Clamp to 0 so areas above water are black.

    // Output Grayscale Texture
    // Normalize the thickness by the max_depth to get a 0-1 value.
    float grayscale = clamp(thickness / max_depth, 0.0, 1.0);

    ALBEDO = vec3(grayscale);
}
