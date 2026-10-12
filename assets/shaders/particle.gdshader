shader_type canvas_item;
render_mode blend_add, unshaded, skip_vertex_transform;
// Stateless GPU particles. A particle is written to the instance buffer once,
// when it is born; this shader works out where it is from the clock alone, so
// thousands of particles cost the CPU nothing per frame.
//
// The instance transform is used purely as a data carrier (the node sits at
// the world origin with an identity transform):
//   basis.x = (birth time, lifetime)   basis.y = velocity   origin = birth position
// INSTANCE_CUSTOM = (start size, end size, drag, stretch along velocity)

uniform float u_time = 0.0;

varying float v_fade;

void vertex() {
	vec2 born_life = MODEL_MATRIX[0].xy;
	vec2 vel = MODEL_MATRIX[1].xy;
	vec2 origin = MODEL_MATRIX[3].xy;
	float age = u_time - born_life.x;
	float t = age / max(born_life.y, 0.0001);
	float alive = step(0.0, age) * step(t, 1.0);
	float drag = INSTANCE_CUSTOM.z;
	float travel = drag > 0.001 ? (1.0 - exp(-drag * age)) / drag : age;
	float size = mix(INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.y, clamp(t, 0.0, 1.0));
	float stretch = INSTANCE_CUSTOM.w * exp(-drag * age);
	float speed = length(vel);
	vec2 dir = speed > 0.001 ? vel / speed : vec2(1.0, 0.0);
	vec2 side = vec2(-dir.y, dir.x);
	vec2 world = origin + vel * travel + dir * VERTEX.x * size * (1.0 + stretch) + side * VERTEX.y * size;
	VERTEX = world * alive;
	v_fade = (1.0 - t * t) * alive;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = clamp(1.0 - d, 0.0, 1.0);
	COLOR = vec4(COLOR.rgb, COLOR.a * a * a * v_fade);
}
