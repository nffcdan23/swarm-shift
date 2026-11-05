#include "storekit_bridge.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

StoreKitBridge *StoreKitBridge::singleton = nullptr;

StoreKitBridge::StoreKitBridge() {
	singleton = this;
}

StoreKitBridge::~StoreKitBridge() {
	if (singleton == this) {
		singleton = nullptr;
	}
}

void StoreKitBridge::emit_event(const String &p_name, const Dictionary &p_payload) {
	call_deferred("emit_signal", "event", p_name, p_payload);
}

void StoreKitBridge::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_supported"), &StoreKitBridge::is_supported);
	ClassDB::bind_method(D_METHOD("start"), &StoreKitBridge::start);
	ClassDB::bind_method(D_METHOD("load_products", "ids"), &StoreKitBridge::load_products);
	ClassDB::bind_method(D_METHOD("purchase", "product_id"), &StoreKitBridge::purchase);
	ClassDB::bind_method(D_METHOD("finish_transaction", "transaction_id"), &StoreKitBridge::finish_transaction);
	ClassDB::bind_method(D_METHOD("request_entitlements"), &StoreKitBridge::request_entitlements);
	ClassDB::bind_method(D_METHOD("sync"), &StoreKitBridge::sync);

	ADD_SIGNAL(MethodInfo("event", PropertyInfo(Variant::STRING, "name"), PropertyInfo(Variant::DICTIONARY, "payload")));
}
