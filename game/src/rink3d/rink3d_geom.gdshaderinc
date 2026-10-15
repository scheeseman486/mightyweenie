// Plan 40 (R1, R4): the rink's geometry for the 3D shaders, once (included
// by rink3d_common.gdshaderinc, so every rink shader has it): the boards,
// the rink's pixel in view units, the camera's ray meeting a plane, the
// direction level towards the camera. The GDScript side is MwRinkShape and
// MwRink3D.METRES_PER_PX; test_rink_shape checks these literals.

// One rink pixel in view units (MwRink3D.METRES_PER_PX).
const float RINK_PX = 0.05;

// The boards (the physics boundary, rink px): the straight boards' half
// sizes and the rounded corners' radii (MwRinkShape.BOARD, CORNER_FAR,
// CORNER_NEAR), and their top, the far glass's (MwRinkShape.BOARDS_TOP).
const vec2 RINK_BOARD = vec2(185.0, 372.0);
const float RINK_CORNER_FAR = 74.0;
const float RINK_CORNER_NEAR = 48.0;
const float RINK_BOARDS_TOP = 48.0;

// Signed distance (rink px) from the boards' inside line: < 0 on the ice
// (the rounded rectangle, MwRinkShape.rounded_sd).
float rink_sd(vec2 p) {
	float r = p.y < 0.0 ? RINK_CORNER_FAR : RINK_CORNER_NEAR;
	vec2 q = abs(p) - (RINK_BOARD - r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Where the camera's ray through view position v meets the plane through q
// with normal n (view space; ortho: parallel rays along -z) - the
// billboards' depth, the reflections' ice point, the crowd's.
vec3 ray_plane(vec3 v, vec3 n, vec3 q, bool ortho) {
	if (ortho) {
		float nz = abs(n.z) < 1e-6 ? 1e-6 : n.z;
		return v - vec3(0.0, 0.0, dot(n, v - q) / nz);
	}
	float nv = dot(n, v);
	return v * (dot(n, q) / (abs(nv) < 1e-9 ? 1e-9 : nv));
}

// The direction in the model's space level towards the camera (the
// billboards', the crowd's and the flat shadows' basis): the view's back
// vector in the model's space with its height dropped.
vec3 level_toward_camera(mat4 model, mat4 inv_view) {
	vec3 back = (inverse(model) * vec4(inv_view[2].xyz, 0.0)).xyz;
	return normalize(vec3(back.x, 0.0, back.z) + vec3(0.0, 0.0, 1e-6));
}
