shader_type canvas_item;
render_mode blend_add, unshaded;
// Procedural ring / disc: shockwaves, blast radii, danger zones, the boss
// arena wall. The quad spans the outer diameter.
// INSTANCE_CUSTOM = (ring thickness as a fraction of radius, edge softness,
//                    inner fill strength, unused)

varying vec4 v_shape;

void vertex() {
	v_shape = INSTANCE_CUSTOM;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float soft = max(v_shape.y, 0.004);
	float outer = 1.0 - smoothstep(1.0 - soft, 1.0, d);
	float inner = smoothstep(1.0 - v_shape.x - soft, 1.0 - v_shape.x, d);
	float shape = max(outer * inner, outer * v_shape.z);
	COLOR = vec4(COLOR.rgb, COLOR.a * shape);
}
