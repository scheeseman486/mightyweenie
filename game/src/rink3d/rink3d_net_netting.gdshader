// A 3D net's netting (plan 17, MwNet3D): a 1 px stipple, every other rink
// pixel in a checker (UV = rink px on the plane the face faces most; the
// glTF's V runs the other way, which keeps the checker), the outer colour
// seen from outside, the inner colour from inside. Unshaded, two-sided.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://src/rink3d/rink3d_common.gdshaderinc"

uniform int outer = 1;   // line * 16 + colour
uniform int inner = 8;

void fragment() {
	ivec2 p = ivec2(floor(UV));
	if (((p.x + p.y) & 1) != 0) {
		discard;
	}
	ALBEDO = colour_of(FRONT_FACING ? outer : inner);
}
