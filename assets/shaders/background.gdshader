shader_type canvas_item;
render_mode unshaded;
// Arena floor: a two-scale grid that scrolls with the camera, soft drifting
// colour clouds and a vignette. Entirely procedural - no textures.

uniform vec2 u_offset = vec2(0.0);
uniform vec2 u_view = vec2(720.0, 1280.0);
uniform float u_zoom = 1.0;
uniform float u_time = 0.0;
uniform vec4 u_grid : source_color = vec4(0.086, 0.196, 0.29, 1.0);
uniform vec4 u_accent : source_color = vec4(0.176, 0.886, 1.0, 1.0);
uniform vec4 u_base : source_color = vec4(0.02, 0.027, 0.05, 1.0);
uniform float u_danger = 0.0;
uniform float u_detail = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float grid_line(vec2 world, float spacing, float width) {
	vec2 g = abs(fract(world / spacing - 0.5) - 0.5) * spacing;
	return 1.0 - smoothstep(0.0, width, min(g.x, g.y));
}

void fragment() {
	vec2 screen = (UV - vec2(0.5)) * u_view;
	vec2 world = screen / u_zoom + u_offset;
	float px = 1.0 / u_zoom;

	vec3 col = u_base.rgb;
	if (u_detail > 0.5) {
		// Colour clouds on a slower parallax layer for depth.
		vec2 far = screen / u_zoom + u_offset * 0.45;
		float cloud = vnoise(far / 420.0 + vec2(u_time * 0.012, 0.0));
		cloud *= vnoise(far / 170.0 - vec2(0.0, u_time * 0.02));
		col += u_accent.rgb * cloud * 0.085;
	}
	float fine = grid_line(world, 96.0, 1.5 * px);
	float coarse = grid_line(world, 480.0, 2.4 * px);
	col += u_grid.rgb * (fine * 0.55 + coarse * 0.9);
	// Nodes where the coarse lines cross.
	vec2 node = abs(fract(world / 480.0 - 0.5) - 0.5) * 480.0;
	col += u_accent.rgb * (1.0 - smoothstep(2.0 * px, 7.0 * px, length(node))) * 0.5;

	vec2 centred = (UV - vec2(0.5)) * vec2(1.0, u_view.y / u_view.x);
	float vignette = smoothstep(1.05, 0.25, length(centred));
	col *= mix(0.35, 1.0, vignette);
	// Red wash at the screen edge when the player is in trouble.
	col += vec3(0.9, 0.08, 0.14) * u_danger * (1.0 - vignette) * 0.55;
	COLOR = vec4(col, 1.0);
}
