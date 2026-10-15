// The penalty-box side's spear fence and gate rail (plan 14), and the pens'
// walls (bench): seen from both sides alike. Colour 0 (between the bars) is
// see-through; paint (plan 37) shows on the solid parts; the walls darken
// into the hallways (rink3d_arch).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://src/rink3d/rink3d_common.gdshaderinc"
#include "res://src/rink3d/rink3d_paint.gdshaderinc"
#include "res://src/rink3d/rink3d_arch.gdshaderinc"

uniform sampler2D picture : filter_nearest, repeat_disable;

void vertex() {
	ARCH_VERTEX;
}

void fragment() {
	int i = indexed_at(picture, UV);
	if (i % 16 == 0) {
		discard;
	}
	int k = paint_at(UV2);              // plan 37: paint on the solid parts only
	ALBEDO = (k > 0 ? paint_colour(k) : colour_of(i)) * arch_shade();
}
