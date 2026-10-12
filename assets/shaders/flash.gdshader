shader_type canvas_item;
// Plain sprite with a white hit-flash. Used by the player core and the boss.

uniform float flash = 0.0;

void fragment() {
	COLOR.rgb = mix(COLOR.rgb, vec3(1.0), flash);
}
