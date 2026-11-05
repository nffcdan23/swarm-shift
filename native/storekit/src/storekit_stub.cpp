// Desktop stub: the class exists so the editor, tests and Mac runs load the
// extension cleanly, but there is no store behind it.

#include "storekit_bridge.h"

using namespace godot;

bool StoreKitBridge::is_supported() const { return false; }
void StoreKitBridge::start() {}
void StoreKitBridge::load_products(const PackedStringArray &p_ids) {}
void StoreKitBridge::purchase(const String &p_product_id) {}
void StoreKitBridge::finish_transaction(const String &p_transaction_id) {}
void StoreKitBridge::request_entitlements() {}
void StoreKitBridge::sync() {}
