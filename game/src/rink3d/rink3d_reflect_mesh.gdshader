// A one-sided mesh's reflection in the ice (plan 37): the boards and signs,
// a net's frame. See rink3d_reflect_mesh_body.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, blend_mix, depth_draw_never;
#include "res://src/rink3d/rink3d_reflect_mesh_body.gdshaderinc"
