#include "storekit_bridge.h"

#include <gdextension_interface.h>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

static StoreKitBridge *bridge = nullptr;

static void initialize_storekit(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(StoreKitBridge);
	bridge = memnew(StoreKitBridge);
	Engine::get_singleton()->register_singleton("StoreKit", bridge);
}

static void uninitialize_storekit(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	Engine::get_singleton()->unregister_singleton("StoreKit");
	memdelete(bridge);
	bridge = nullptr;
}

extern "C" {

GDExtensionBool GDE_EXPORT storekit_bridge_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_storekit);
	init_obj.register_terminator(uninitialize_storekit);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}

}
