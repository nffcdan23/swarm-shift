shader_type canvas_item;
render_mode blend_add, unshaded;
// Instanced atlas sprite, additive. Used for projectiles, beams and glows.
// Textures are "energy maps": white RGB with intensity in alpha. The brightest
// part of any sprite is pushed towards white so it reads as white-hot.
// INSTANCE_CUSTOM = (atlas cell index, extra brightness, cell span, unused)

uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform float grid = 8.0;

varying float v_boost;

void vertex() {
	float idx = INSTANCE_CUSTOM.x;
	float span = max(INSTANCE_CUSTOM.z, 1.0);
	vec2 cell = vec2(mod(idx, grid), floor(idx / grid));
	v_boost = INSTANCE_CUSTOM.y;
	UV = (cell + UV * span) / grid;
}

void fragment() {
	vec4 tex = texture(atlas, UV);
	float hot = smoothstep(0.7, 1.0, tex.a);
	vec3 col = mix(tex.rgb * COLOR.rgb, vec3(1.0), hot * 0.85);
	COLOR = vec4(col, tex.a * COLOR.a * (1.0 + v_boost));
}
