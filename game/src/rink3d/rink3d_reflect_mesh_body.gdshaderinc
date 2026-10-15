// A mesh's reflection in the ice (plan 37, rink3d_reflect.gdshaderinc): a
// mirrored copy of one of the rink's or a net's meshes under the ice
// (MwRinkModel, MwNet3D), drawn as its own shader draws it - [mode] 0: a
// ROM picture (the boards, signs and fence: colour 0 see-through, the paint
// over it, as rink3d_wall / rink3d_fence), 1: one palette colour (a net's
// frame, rink3d_net_flat), 2: a net's netting (rink3d_net_netting's
// stipple), 3: the glass (rink3d_glass_body: its own alpha times the
// reflection's) - each pixel row reflect_alpha * (1 - n / reflect_fade) opaque
// by its height n above the ice (whole pixels: the boards' texels are a
// pixel tall), on the ice only, at the depth of the ice point it shows on.
// rink3d_reflect_mesh (one-sided, as the boards and the nets' frames) and
// rink3d_reflect_mesh_2s (two-sided, as the fence and the netting) set the
// culling; the mirrored instance turns it round.
#include "res://src/rink3d/rink3d_common.gdshaderinc"
#include "res://src/rink3d/rink3d_paint.gdshaderinc"
#include "res://src/rink3d/rink3d_reflect.gdshaderinc"

uniform int mode = 0;
uniform sampler2D picture : filter_nearest, repeat_disable;
#include "res://src/rink3d/rink3d_glass_body.gdshaderinc"
uniform int index = 1;   // mode 1: line * 16 + colour
uniform int outer = 1;   // mode 2: the netting's colour seen from outside
uniform int inner = 8;   // ... and from inside

varying float refl_h;           // px above the ice of the point this one mirrors
varying flat vec3 refl_scale;   // the world's scale (the ortho cameras': sqrt 2 up and north-south)
varying flat vec3 refl_q;       // view space: a point of the ice (world y 0)
varying flat vec3 refl_n;       // view space: the ice's normal

void vertex() {
	refl_scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	refl_h = -w.y / (refl_scale.y * REFLECT_PX);
	refl_q = (VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	refl_n = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	if (refl_h < -0.01) {
		discard;
	}
	float a = reflect_row_alpha(floor(max(refl_h, 0.0)));
	if (a <= 0.0) {
		discard;
	}
	vec3 c;
	if (mode == 0) {
		int i = indexed_at(picture, UV);
		if (i % 16 == 0) {
			discard;
		}
		int k = paint_at(UV2);
		c = k > 0 ? paint_colour(k) : colour_of(i);
	} else if (mode == 1) {
		c = colour_of(index);
	} else if (mode == 3) {
		vec4 g = glass_colour(UV, UV2);
		if (g.a < 0.0) {
			discard;
		}
		c = g.rgb;
		a *= g.a;
	} else {
		ivec2 s = ivec2(floor(UV));
		if (((s.x + s.y) & 1) != 0) {
			discard;
		}
		c = colour_of(FRONT_FACING ? inner : outer);   // mirrored: the faces' sides turn round
	}
	bool ortho = PROJECTION_MATRIX[3][3] != 0.0;
	vec3 p = ray_plane(VERTEX, refl_n, refl_q, ortho);
	if (!reflect_on_ice(p, INV_VIEW_MATRIX, refl_scale)) {
		discard;
	}
	ALBEDO = c;
	ALPHA = a;
	DEPTH = reflect_depth(p, ortho, PROJECTION_MATRIX);
}
