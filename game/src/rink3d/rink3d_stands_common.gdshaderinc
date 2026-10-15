// Shared by the stands and their crowd (plan 16, docs/rink3d.md, Crowd).
//
// * The top rows fade to black: colours multiplied down smoothly by height,
//   from fade_from to fade_to (rink px above the ice), the smoothstep's
//   brightness raised to fade_power (a sharper ramp; MwStands3D.fade).
// * Cutaway for the game's cameras (MwStands3D.cutaway): with the camera
//   beyond the boards at one end, the stands between it and the rink that
//   rise above its line of sight over those boards' top would hide the
//   play; they are not drawn. The plane through the boards' top edge and the
//   camera: cut_origin (a point on the edge) and cut_normal (pointing up),
//   world space; cut_side: the camera's side of the edge along world z.

uniform float fade_from = 92.0;
uniform float fade_to = 212.0;
uniform float fade_power = 2.0;
uniform bool cut_enabled = false;
uniform vec3 cut_origin = vec3(0.0);
uniform vec3 cut_normal = vec3(0.0, 1.0, 0.0);
uniform float cut_side = 1.0;

// The brightness at world height [param y] (m).
float stands_fade(float y) {
	return pow(1.0 - smoothstep(fade_from, fade_to, y / RINK_PX), fade_power);
}

// Whether world point [param w] is cut away (see above).
bool stands_cut(vec3 w) {
	return cut_enabled && (w.z - cut_origin.z) * cut_side > 0.0 && dot(cut_normal, w - cut_origin) > 0.0;
}
