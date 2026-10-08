// A 3D net's frame and its outline shell (plan 17, MwNet3D): one palette
// colour, unshaded (the 16-bit look: flat faces, each in its own shade). The
// shell's faces point inwards, so back-face culling leaves only its far side,
// round the bars' edges: the outline.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
#include "res://src/rink3d/rink3d_common.gdshaderinc"

uniform int index = 1;   // line * 16 + colour

void fragment() {
	ALBEDO = colour_of(index);
}
