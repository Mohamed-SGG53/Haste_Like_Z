// Terrain shader for HasteLike - smooth height-based coloring with procedural noise.
// ----------------------------------------------------------------------------
// Colors blend by vertex height: valley -> grass -> dirt -> rock -> snow.
// Steep slopes get a rock tint. Procedural FBM noise adds natural variation.
// Designed to be smooth-shaded across triangle boundaries (no visible facets).
// ----------------------------------------------------------------------------
shader_type spatial;

uniform vec3 valley_color : source_color = vec3(0.18, 0.30, 0.20);
uniform vec3 grass_color : source_color = vec3(0.32, 0.55, 0.22);
uniform vec3 dirt_color : source_color = vec3(0.50, 0.36, 0.22);
uniform vec3 rock_color : source_color = vec3(0.36, 0.34, 0.32);
uniform vec3 snow_color : source_color = vec3(0.96, 0.96, 0.98);

uniform float valley_max_height = -7.0;
uniform float grass_max_height = 2.0;
uniform float dirt_max_height = 7.0;
uniform float rock_max_height = 12.0;
uniform float snow_start_height = 14.0;

uniform float rock_slope_threshold : hint_range(0.0, 1.0) = 0.55;

uniform float noise_scale = 0.12;
uniform float noise_amount = 0.22;
uniform float micro_noise_scale = 1.8;
uniform float micro_noise_amount = 0.05;

uniform float roughness : hint_range(0.0, 1.0) = 0.93;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world_pos;
varying vec3 v_normal;
varying float v_height;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	v_height = v_world_pos.y;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise2d(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec3 normal = normalize(v_normal);
	float slope = 1.0 - abs(normal.y); // 0 = flat, 1 = vertical wall

	// Base color from height (vertical gradient)
	vec3 color = valley_color;
	color = mix(color, grass_color, smoothstep(valley_max_height - 2.0, grass_max_height, v_height));
	color = mix(color, dirt_color, smoothstep(grass_max_height, dirt_max_height, v_height));
	color = mix(color, rock_color, smoothstep(dirt_max_height, rock_max_height, v_height));
	color = mix(color, snow_color, smoothstep(snow_start_height - 1.0, snow_start_height + 3.0, v_height));

	// Steep slopes -> rock (no grass on cliffs)
	color = mix(color, rock_color, smoothstep(rock_slope_threshold * 0.6, rock_slope_threshold, slope));

	// Large FBM noise (regional color variation - patches of darker/lighter ground)
	float n = fbm(v_world_pos.xz * noise_scale);
	n = n * 2.0 - 1.0;
	color *= 1.0 + n * noise_amount;

	// Micro noise (tiny pebble-like variation)
	float mn = noise2d(v_world_pos.xz * micro_noise_scale);
	mn = mn * 2.0 - 1.0;
	color *= 1.0 + mn * micro_noise_amount;

	ALBEDO = color;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	// Slight ambient occlusion darkening in valleys (visual only, cheap)
}
