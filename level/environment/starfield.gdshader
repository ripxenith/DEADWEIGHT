shader_type spatial;

render_mode unshaded, cull_disabled;


// ============================================================
// STARFIELD PARAMETERS
// ============================================================

// Overall UV resolution / density
uniform float star_density : hint_range(20.0, 200.0) = 85.0;

// Percentage of cells containing stars
uniform float star_chance : hint_range(0.01, 0.20) = 0.07;

// Chance of a rare bright star
uniform float rare_star_chance : hint_range(0.001, 0.03) = 0.008;


// ============================================================
// BRIGHTNESS
// ============================================================

uniform float min_brightness : hint_range(0.0, 2.0) = 0.35;

uniform float max_brightness : hint_range(0.0, 3.0) = 1.0;

uniform float rare_brightness : hint_range(1.0, 6.0) = 2.5;


// ============================================================
// SIZE
// ============================================================

uniform float min_size : hint_range(0.01, 2.0) = 0.65;

uniform float max_size : hint_range(0.02, 3.0) = 1.25;

uniform float rare_star_size : hint_range(1.0, 3.0) = 1.20;


// ============================================================
// GLOW / EMISSION
// ============================================================

uniform float normal_emission : hint_range(0.0, 10.0) = 2.0;

uniform float rare_emission : hint_range(0.0, 20.0) = 8.0;


// ============================================================
// TWINKLE
// ============================================================

uniform float min_twinkle_speed : hint_range(0.0, 3.0) = 0.25;

uniform float max_twinkle_speed : hint_range(0.0, 5.0) = 0.9;

uniform float twinkle_strength : hint_range(0.0, 1.0) = 0.35;


// ============================================================
// RANDOM
// ============================================================

float random_value(vec2 p)
{
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}


// ============================================================
// MAIN
// ============================================================

void fragment()
{
    vec2 uv = UV * star_density;

    vec2 cell = floor(uv);
    vec2 local = fract(uv);

    float r = random_value(cell);


    // ========================================================
    // STAR SELECTION
    // ========================================================

    float selected = step(
        1.0 - star_chance,
        r
    );

    float rare_star = step(
        1.0 - rare_star_chance,
        r
    );

    selected = max(
        selected,
        rare_star
    );


    // ========================================================
    // STAR POSITION
    // ========================================================

    vec2 center = vec2(0.5);

    float distance_from_center =
        distance(local, center);


    // ========================================================
    // RANDOM STAR SIZE
    // ========================================================

    float size_random = random_value(
        cell + vec2(43.17, 91.63)
    );

    float star_size = mix(
        min_size,
        max_size,
        size_random
    );

    star_size = mix(
        star_size,
        star_size * rare_star_size,
        rare_star
    );


    float inner_radius =
        0.14 * star_size;

    float outer_radius =
        0.45 * star_size;


    float circle = 1.0 - smoothstep(
        inner_radius,
        outer_radius,
        distance_from_center
    );

    float star =
        selected * circle;


    // ========================================================
    // RANDOM BRIGHTNESS
    // ========================================================

    float star_brightness = mix(
        min_brightness,
        max_brightness,
        random_value(
            cell + vec2(17.31, 83.72)
        )
    );


    star_brightness = mix(
        star_brightness,
        rare_brightness,
        rare_star
    );


    star *= star_brightness;


    // ========================================================
    // TWINKLE
    // ========================================================

    float twinkle_speed = mix(
        min_twinkle_speed,
        max_twinkle_speed,
        random_value(
            cell + vec2(61.27, 14.83)
        )
    );

    float twinkle_phase =
        random_value(
            cell + vec2(82.41, 53.19)
        ) * 6.28318;


    float twinkle = sin(
        TIME * twinkle_speed +
        twinkle_phase
    );


    float twinkle_factor = mix(
        1.0 - twinkle_strength,
        1.0 + twinkle_strength,
        twinkle * 0.5 + 0.5
    );


    star *= twinkle_factor;


    // ========================================================
    // STAR COLOR
    // ========================================================

    float color_random =
        random_value(
            cell + vec2(91.42, 37.16)
        );

    vec3 star_color;


    if (color_random < 0.78)
    {
        // White
        star_color = vec3(
            1.0,
            1.0,
            1.0
        );
    }
    else if (color_random < 0.91)
    {
        // Blue-white
        star_color = vec3(
            0.72,
            0.86,
            1.0
        );
    }
    else if (color_random < 0.98)
    {
        // Warm white
        star_color = vec3(
            1.0,
            0.88,
            0.70
        );
    }
    else
    {
        // Orange / red giant
        star_color = vec3(
            1.0,
            0.62,
            0.35
        );
    }


    // ========================================================
    // OUTPUT
    // ========================================================

    ALBEDO =
        star_color *
        star;


    EMISSION =
        star_color *
        star *
        mix(
            normal_emission,
            rare_emission,
            rare_star
        );
}