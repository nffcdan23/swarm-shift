#pragma once

// StoreKitBridge: the Godot-facing side of the StoreKit 2 purchase bridge.
//
// One object, registered as the engine singleton "StoreKit". GDScript drives
// it with plain calls (start, load_products, purchase, finish_transaction,
// request_entitlements, sync) and listens to a single signal,
// event(name, payload), emitted on the main loop between frames. The events
// and their payloads are listed in StoreKitBridge.swift. It holds no shop
// logic: what a product grants is StoreService's job.
//
// The iOS build (storekit_ios.mm, StoreKitBridge.swift) talks to StoreKit.
// Every other platform gets storekit_stub.cpp, which reports
// is_supported() == false, so desktop runs and tests see the class without
// any store behind it.

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class StoreKitBridge : public Object {
	GDCLASS(StoreKitBridge, Object)

	static StoreKitBridge *singleton;

protected:
	static void _bind_methods();

public:
	static StoreKitBridge *get_singleton() { return singleton; }

	StoreKitBridge();
	~StoreKitBridge();

	// Emits event(name, payload) on the next idle frame.
	void emit_event(const String &p_name, const Dictionary &p_payload);

	// --- platform (storekit_ios.mm / storekit_stub.cpp)
	bool is_supported() const;
	void start();
	void load_products(const PackedStringArray &p_ids);
	void purchase(const String &p_product_id);
	void finish_transaction(const String &p_transaction_id);
	void request_entitlements();
	void sync();
};

} // namespace godot
