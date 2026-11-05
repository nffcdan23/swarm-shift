// iOS: forwards calls to the Swift StoreKit 2 layer (StoreKitBridge.swift,
// whose generated header is StoreKitBridge-Swift.h) and turns its events into
// Godot dictionaries.

#include "storekit_bridge.h"

#import <Foundation/Foundation.h>
#import "StoreKitBridge-Swift.h"

#include <godot_cpp/variant/array.hpp>

using namespace godot;

static String ns_to_string(NSString *p_text) {
	return p_text == nil ? String() : String::utf8([p_text UTF8String]);
}

static NSString *to_ns(const String &p_text) {
	return [NSString stringWithUTF8String:p_text.utf8().get_data()];
}

static Variant to_variant(id p_value) {
	if (p_value == nil || p_value == [NSNull null]) {
		return Variant();
	}
	if ([p_value isKindOfClass:[NSString class]]) {
		return ns_to_string((NSString *)p_value);
	}
	if ([p_value isKindOfClass:[NSNumber class]]) {
		return [(NSNumber *)p_value doubleValue];
	}
	if ([p_value isKindOfClass:[NSArray class]]) {
		Array out;
		for (id item in (NSArray *)p_value) {
			out.append(to_variant(item));
		}
		return out;
	}
	if ([p_value isKindOfClass:[NSDictionary class]]) {
		Dictionary out;
		NSDictionary *dict = (NSDictionary *)p_value;
		for (id key in dict) {
			out[ns_to_string([key description])] = to_variant(dict[key]);
		}
		return out;
	}
	return ns_to_string([p_value description]);
}

bool StoreKitBridge::is_supported() const {
	return true;
}

void StoreKitBridge::start() {
	[[SKBStore shared] start:^(NSString *name, NSDictionary<NSString *, id> *payload) {
		StoreKitBridge *bridge = StoreKitBridge::get_singleton();
		if (bridge != nullptr) {
			bridge->emit_event(ns_to_string(name), to_variant(payload));
		}
	}];
}

void StoreKitBridge::load_products(const PackedStringArray &p_ids) {
	NSMutableArray<NSString *> *ids = [NSMutableArray array];
	for (int i = 0; i < p_ids.size(); i++) {
		[ids addObject:to_ns(p_ids[i])];
	}
	[[SKBStore shared] loadProducts:ids];
}

void StoreKitBridge::purchase(const String &p_product_id) {
	[[SKBStore shared] purchase:to_ns(p_product_id)];
}

void StoreKitBridge::finish_transaction(const String &p_transaction_id) {
	[[SKBStore shared] finish:to_ns(p_transaction_id)];
}

void StoreKitBridge::request_entitlements() {
	[[SKBStore shared] requestEntitlements];
}

void StoreKitBridge::sync() {
	[[SKBStore shared] sync];
}
