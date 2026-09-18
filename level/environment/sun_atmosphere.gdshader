shader_type spatial;

render_mode
    unshaded,
    cull_disabled,
    blend_add;

uniform vec3 corona_color : source_color =
    vec3(1.0, 0.35, 0.02);

uniform float corona_strength = 2.0;

uniform sampler2D noise_texture;

void fragment() {

    float fresnel =
        1.0 - dot(NORMAL, VIEW);

    float glow =
        pow(fresnel, 3.0);

    float noise =
        texture(
            noise_texture,
            UV * 4.0 + vec2(TIME * 0.01, TIME * 0.005)
        ).r;

    glow *= mix(0.5, 1.5, noise);

    ALBEDO = corona_color;

    EMISSION =
        corona_color *
        corona_strength;

    ALPHA =
        glow * 0.8;
}