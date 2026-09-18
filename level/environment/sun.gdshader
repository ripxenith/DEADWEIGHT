shader_type spatial;

render_mode unshaded;

uniform vec3 sun_color : source_color = vec3(1.0, 0.55, 0.05);

uniform float surface_speed = 0.04;
uniform float surface_detail = 3.0;

uniform float sunspot_strength = 0.75;
uniform float sunspot_scale = 5.0;

uniform float emission_strength = 3.0;

uniform sampler2D noise_texture;


void fragment() {

    // -------------------------
    // SURFACE MOVEMENT
    // -------------------------

    vec2 uv = UV;

    uv.x += TIME * surface_speed;

    float large_noise =
        texture(noise_texture, uv * surface_detail).r;

    float small_noise =
        texture(
            noise_texture,
            uv * surface_detail * 3.0 + vec2(TIME * 0.02, 0.0)
        ).r;

    float plasma =
        large_noise * 0.7 +
        small_noise * 0.3;


    // -------------------------
    // SUNSPOTS
    // -------------------------

    vec2 spot_uv = UV;

    spot_uv.x += TIME * surface_speed * 0.5;

    float spots =
        texture(
            noise_texture,
            spot_uv * sunspot_scale
        ).r;

    // Turn smooth noise into distinct dark regions
    spots = smoothstep(0.25, 0.45, spots);

    // Invert it so low-noise areas become spots
    float sunspots = 1.0 - spots;

    // Control how dark the spots become
    plasma -= sunspots * sunspot_strength;


    // -------------------------
    // SUN COLOR
    // -------------------------

    vec3 deep_orange =
        vec3(1.0, 0.18, 0.01);

    vec3 orange =
        vec3(1.0, 0.40, 0.02);

    vec3 yellow =
        vec3(1.0, 0.85, 0.20);

    vec3 surface_color =
        mix(deep_orange, yellow, plasma);


    // -------------------------
    // EDGE GLOW
    // -------------------------

    float fresnel =
        1.0 - dot(NORMAL, VIEW);

    float edge_glow =
        pow(fresnel, 2.5);

    surface_color +=
        vec3(1.0, 0.45, 0.05) *
        edge_glow *
        1.5;


    // -------------------------
    // OUTPUT
    // -------------------------

    ALBEDO = surface_color;

    EMISSION =
        surface_color *
        emission_strength;
}