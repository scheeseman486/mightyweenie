// A 3D net's faces never drawn (plan 17, MwNet3D): the feet of the Battle
// Net's spikes on the netting, just inside it - the netting is see-through,
// they would show through it. (The meshes stay closed; these faces just
// never draw.)
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

void fragment() {
	discard;
}
