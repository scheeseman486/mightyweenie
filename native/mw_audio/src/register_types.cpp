// mightyweenie - audio GDExtension (native/mw_audio).
// Copyright (c) 2026 the mightyweenie authors. BSD-3-Clause
// (see LICENSE).
//
// Extension entry point (entry_symbol in game/addons/mw_audio/mw_audio.gdextension).
#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "mw_chips.h"

using namespace godot;

static void initialize_mw_audio(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(mw::MwChips);
}

static void uninitialize_mw_audio(ModuleInitializationLevel p_level) {
	(void)p_level;
}

extern "C" {
GDExtensionBool GDE_EXPORT mw_audio_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_mw_audio);
	init_obj.register_terminator(uninitialize_mw_audio);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
