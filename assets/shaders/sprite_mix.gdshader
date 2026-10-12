shader_type canvas_item;
render_mode blend_mix, unshaded;
// Instanced atlas sprite, normal alpha blending. Used for enemies and pickups.
// INSTANCE_CUSTOM = (atlas cell index, hit flash 0..1, cell span, unused)

uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform float grid = 8.0;

varying float v_flash;

void vertex() {
	float idx = INSTANCE_CUSTOM.x;
	float span = max(INSTANCE_CUSTOM.z, 1.0);
	vec2 cell = vec2(mod(idx, grid), floor(idx / grid));
	v_flash = INSTANCE_CUSTOM.y;
	UV = (cell + UV * span) / grid;
}

void fragment() {
	vec4 tex = texture(atlas, UV);
	COLOR = vec4(mix(tex.rgb * COLOR.rgb, vec3(1.0), v_flash), tex.a * COLOR.a);
}
