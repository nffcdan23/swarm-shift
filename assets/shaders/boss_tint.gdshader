shader_type canvas_item;
// Boss parts are drawn in grey with white highlights (tools/generate_art.gd,
// G_BOSS). This maps the grey to the boss's colour, keeps the highlights
// white, and adds the white hit-flash the core uses.

uniform vec4 tint : source_color = vec4(1.0, 0.24, 0.43, 1.0);
uniform float flash = 0.0;

varying vec4 vertex_color;

void vertex() {
	vertex_color = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float lum = max(tex.r, max(tex.g, tex.b));
	vec3 col = tint.rgb * clamp(lum / 0.6, 0.0, 1.0);
	col = mix(col, vec3(1.0), smoothstep(0.7, 1.0, lum));
	col = mix(col, vec3(1.0), flash);
	COLOR = vec4(col, tex.a) * vertex_color;
}
