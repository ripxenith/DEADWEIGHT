shader_type spatial;

render_mode unshaded, cull_disabled, blend_add;


// ============================================================
// GENERAL CLOUD PARAMETERS
// ============================================================

uniform float cloud_scale : hint_range(1.0, 30.0) = 8.0;
uniform float cloud_density : hint_range(0.0, 2.0) = 0.65;
uniform float cloud_contrast : hint_range(0.1, 5.0) = 2.0;
uniform float cloud_brightness : hint_range(0.0, 5.0) = 1.0;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.45;


// ============================================================
// MILKY WAY
// ============================================================

uniform float milky_way_width : hint_range(0.02, 1.0) = 0.22;
uniform float milky_way_strength : hint_range(0.0, 5.0) = 1.5;
uniform float milky_way_density : hint_range(0.5, 8.0) = 3.0;
uniform float milky_way_curve : hint_range(0.0, 2.0) = 0.35;


// ============================================================
// DUST LANES
// ============================================================

uniform float dust_strength : hint_range(0.0, 2.0) = 0.75;
uniform float dust_scale : hint_range(1.0, 30.0) = 5.0;
uniform float dust_contrast : hint_range(0.5, 8.0) = 2.5;


// ============================================================
// GALACTIC CORE
// ============================================================

uniform vec3 galactic_core_direction = vec3(
    0.0,
    0.0,
    1.0
);

uniform float galactic_core_size : hint_range(0.01, 1.0) = 0.18;

uniform float galactic_core_brightness : hint_range(0.0, 10.0) = 3.0;

uniform vec3 galactic_core_color : source_color = vec3(
    1.0,
    0.72,
    0.45
);


// ============================================================
// NEBULAE
// ============================================================

uniform float nebula_strength : hint_range(0.0, 5.0) = 1.2;

uniform float nebula_scale : hint_range(0.5, 10.0) = 2.2;

uniform float nebula_softness : hint_range(0.2, 5.0) = 1.4;

uniform float purple_nebula_strength : hint_range(0.0, 3.0) = 1.0;

uniform float blue_nebula_strength : hint_range(0.0, 3.0) = 0.8;

uniform float pink_nebula_strength : hint_range(0.0, 3.0) = 0.45;


// ============================================================
// NEBULA COLORS
// ============================================================

uniform vec3 purple_nebula_color : source_color = vec3(
    0.55,
    0.08,
    0.85
);

uniform vec3 blue_nebula_color : source_color = vec3(
    0.08,
    0.30,
    1.0
);

uniform vec3 pink_nebula_color : source_color = vec3(
    1.0,
    0.12,
    0.40
);


// ============================================================
// DISTANT DUST CLOUDS
// ============================================================

uniform float distant_dust_strength : hint_range(0.0, 2.0) = 0.35;

uniform float distant_dust_scale : hint_range(0.2, 8.0) = 1.1;

uniform float distant_dust_softness : hint_range(0.2, 5.0) = 1.8;

uniform vec3 distant_dust_color : source_color = vec3(
    0.12,
    0.10,
    0.20
);


// ============================================================
// BASE COLORS
// ============================================================

uniform vec3 cloud_color : source_color = vec3(
    0.25,
    0.08,
    0.35
);

uniform vec3 milky_way_color : source_color = vec3(
    0.55,
    0.65,
    1.0
);


// ============================================================
// WORLD SPACE
// ============================================================

varying vec3 world_direction;


void vertex()
{
    vec3 world_position =
        (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    world_direction =
        normalize(world_position);
}


// ============================================================
// RANDOM
// ============================================================

float random_value(vec3 p)
{
    p = fract(
        p * 0.3183099 +
        vec3(0.1, 0.2, 0.3)
    );

    p *= 17.0;

    return fract(
        p.x *
        p.y *
        p.z *
        (p.x + p.y + p.z)
    );
}


// ============================================================
// 3D VALUE NOISE
// ============================================================

float noise_3d(vec3 p)
{
    vec3 i = floor(p);
    vec3 f = fract(p);

    f = f * f * (3.0 - 2.0 * f);


    float n000 =
        random_value(i + vec3(0.0, 0.0, 0.0));

    float n100 =
        random_value(i + vec3(1.0, 0.0, 0.0));

    float n010 =
        random_value(i + vec3(0.0, 1.0, 0.0));

    float n110 =
        random_value(i + vec3(1.0, 1.0, 0.0));


    float n001 =
        random_value(i + vec3(0.0, 0.0, 1.0));

    float n101 =
        random_value(i + vec3(1.0, 0.0, 1.0));

    float n011 =
        random_value(i + vec3(0.0, 1.0, 1.0));

    float n111 =
        random_value(i + vec3(1.0, 1.0, 1.0));


    float x00 =
        mix(n000, n100, f.x);

    float x10 =
        mix(n010, n110, f.x);

    float x01 =
        mix(n001, n101, f.x);

    float x11 =
        mix(n011, n111, f.x);


    float y0 =
        mix(x00, x10, f.y);

    float y1 =
        mix(x01, x11, f.y);


    return mix(y0, y1, f.z);
}


// ============================================================
// FRACTAL CLOUD NOISE
// ============================================================

float cloud_noise(vec3 p)
{
    float value = 0.0;

    value += noise_3d(p) * 0.55;

    p *= 2.0;
    value += noise_3d(p) * 0.25;

    p *= 2.0;
    value += noise_3d(p) * 0.12;

    p *= 2.0;
    value += noise_3d(p) * 0.06;

    return value;
}


// ============================================================
// MAIN
// ============================================================

void fragment()
{
    vec3 direction =
        world_direction;


    // ========================================================
    // MILKY WAY BAND
    // ========================================================

    float band_position =
        direction.y;


    float curve =
        sin(direction.x * 3.14159)
        * milky_way_curve
        * 0.15;


    band_position += curve;


    float band_distance =
        abs(band_position);


    float band = 1.0 -
        smoothstep(
            milky_way_width * 0.35,
            milky_way_width,
            band_distance
        );


    band = pow(
        band,
        milky_way_density
    );


    // ========================================================
    // MILKY WAY CLOUD DETAIL
    // ========================================================

    vec3 sample_position =
        direction * cloud_scale;


    float noise =
        cloud_noise(sample_position);


    float clouds = smoothstep(
        cloud_density - 0.15,
        cloud_density + 0.15,
        noise
    );


    clouds = pow(
        clouds,
        cloud_contrast
    );


    // ========================================================
    // DUST LANES
    // ========================================================

    vec3 dust_position =
        direction * dust_scale;


    float dust_noise =
        cloud_noise(
            dust_position +
            vec3(17.4, 4.2, 31.7)
        );


    float dust =
        smoothstep(
            0.48,
            0.58,
            dust_noise
        );


    dust =
        pow(
            dust,
            dust_contrast
        );


    dust *= band;


    float dust_mask =
        1.0 -
        dust *
        dust_strength;


    // ========================================================
    // MILKY WAY LIGHT
    // ========================================================

    float milky_way =
        band *
        clouds *
        milky_way_strength *
        dust_mask;


    vec3 final_color =
        milky_way_color *
        milky_way;


    final_color +=
        cloud_color *
        milky_way *
        0.35;


    // ========================================================
    // GALACTIC CORE
    // ========================================================

    vec3 core_direction =
        normalize(
            galactic_core_direction
        );


    float core_distance =
        distance(
            direction,
            core_direction
        );


    float core =
        1.0 -
        smoothstep(
            galactic_core_size * 0.15,
            galactic_core_size,
            core_distance
        );


    core =
        pow(
            core,
            2.5
        );


    final_color +=
        galactic_core_color *
        core *
        galactic_core_brightness;


    // ========================================================
    // NEBULA BASE NOISE
    // ========================================================

    vec3 nebula_position =
        direction * nebula_scale;


    float nebula_noise =
        cloud_noise(
            nebula_position +
            vec3(31.7, 12.4, 51.2)
        );


    nebula_noise =
        smoothstep(
            0.35,
            0.75,
            nebula_noise
        );


    nebula_noise =
        pow(
            nebula_noise,
            nebula_softness
        );


    // ========================================================
    // PURPLE NEBULA
    // ========================================================

    float purple_noise =
        cloud_noise(
            nebula_position +
            vec3(71.3, 21.7, 43.8)
        );


    purple_noise =
        smoothstep(
            0.48,
            0.72,
            purple_noise
        );


    float purple =
        purple_noise *
        nebula_noise *
        purple_nebula_strength;


    final_color +=
        purple_nebula_color *
        purple *
        nebula_strength;


    // ========================================================
    // BLUE NEBULA
    // ========================================================

    float blue_noise =
        cloud_noise(
            nebula_position +
            vec3(14.2, 83.1, 37.6)
        );


    blue_noise =
        smoothstep(
            0.45,
            0.70,
            blue_noise
        );


    float blue =
        blue_noise *
        nebula_noise *
        blue_nebula_strength;


    final_color +=
        blue_nebula_color *
        blue *
        nebula_strength;


    // ========================================================
    // PINK / RED NEBULA
    // ========================================================

    float pink_noise =
        cloud_noise(
            nebula_position +
            vec3(91.4, 27.2, 63.8)
        );


    pink_noise =
        smoothstep(
            0.55,
            0.78,
            pink_noise
        );


    float pink =
        pink_noise *
        nebula_noise *
        pink_nebula_strength;


    final_color +=
        pink_nebula_color *
        pink *
        nebula_strength;


    // ========================================================
    // DISTANT DUST CLOUDS
    // ========================================================

    vec3 distant_dust_position =
        direction * distant_dust_scale;


    float distant_dust_noise =
        cloud_noise(
            distant_dust_position +
            vec3(123.7, 51.2, 87.4)
        );


    distant_dust_noise =
        smoothstep(
            0.40,
            0.72,
            distant_dust_noise
        );


    distant_dust_noise =
        pow(
            distant_dust_noise,
            distant_dust_softness
        );


    final_color +=
        distant_dust_color *
        distant_dust_noise *
        distant_dust_strength;


    // ========================================================
    // FINAL BRIGHTNESS
    // ========================================================

    final_color *=
        cloud_brightness;


    // ========================================================
    // OUTPUT
    // ========================================================

    ALBEDO =
        final_color;


    EMISSION =
        final_color;


    float nebula_alpha =
        max(
            purple,
            max(
                blue,
                pink
            )
        ) *
        nebula_strength;


    ALPHA =
        clamp(
            (
                milky_way +
                core +
                nebula_alpha
            ) *
            cloud_opacity,
            0.0,
            1.0
        );
}