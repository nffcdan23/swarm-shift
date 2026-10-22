#include "admob_bridge.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

AdMobBridge *AdMobBridge::singleton = nullptr;

AdMobBridge::AdMobBridge() {
	singleton = this;
}

AdMobBridge::~AdMobBridge() {
	if (singleton == this) {
		singleton = nullptr;
	}
}

void AdMobBridge::emit_later(const StringName &p_signal) {
	call_deferred("emit_signal", p_signal);
}

void AdMobBridge::emit_later(const StringName &p_signal, const Variant &p_arg1) {
	call_deferred("emit_signal", p_signal, p_arg1);
}

void AdMobBridge::emit_later(const StringName &p_signal, const Variant &p_arg1, const Variant &p_arg2) {
	call_deferred("emit_signal", p_signal, p_arg1, p_arg2);
}

void AdMobBridge::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_supported"), &AdMobBridge::is_supported);
	ClassDB::bind_method(D_METHOD("get_sdk_version"), &AdMobBridge::get_sdk_version);
	ClassDB::bind_method(D_METHOD("debug_log", "text"), &AdMobBridge::debug_log);

	ClassDB::bind_method(D_METHOD("consent_request_update", "debug_geography", "test_device_ids", "under_age_of_consent"), &AdMobBridge::consent_request_update);
	ClassDB::bind_method(D_METHOD("consent_load_and_present_if_required"), &AdMobBridge::consent_load_and_present_if_required);
	ClassDB::bind_method(D_METHOD("consent_can_request_ads"), &AdMobBridge::consent_can_request_ads);
	ClassDB::bind_method(D_METHOD("consent_get_status"), &AdMobBridge::consent_get_status);
	ClassDB::bind_method(D_METHOD("consent_is_privacy_options_required"), &AdMobBridge::consent_is_privacy_options_required);
	ClassDB::bind_method(D_METHOD("consent_present_privacy_options"), &AdMobBridge::consent_present_privacy_options);
	ClassDB::bind_method(D_METHOD("consent_reset"), &AdMobBridge::consent_reset);
	ClassDB::bind_method(D_METHOD("get_tracking_status"), &AdMobBridge::get_tracking_status);

	ClassDB::bind_method(D_METHOD("set_test_device_ids", "ids"), &AdMobBridge::set_test_device_ids);
	ClassDB::bind_method(D_METHOD("set_max_ad_content_rating", "rating"), &AdMobBridge::set_max_ad_content_rating);
	ClassDB::bind_method(D_METHOD("set_age_treatment", "treatment"), &AdMobBridge::set_age_treatment);
	ClassDB::bind_method(D_METHOD("start"), &AdMobBridge::start);
	ClassDB::bind_method(D_METHOD("is_started"), &AdMobBridge::is_started);

	ClassDB::bind_method(D_METHOD("load_rewarded", "unit_id"), &AdMobBridge::load_rewarded);
	ClassDB::bind_method(D_METHOD("is_rewarded_loaded"), &AdMobBridge::is_rewarded_loaded);
	ClassDB::bind_method(D_METHOD("show_rewarded"), &AdMobBridge::show_rewarded);
	ClassDB::bind_method(D_METHOD("load_interstitial", "unit_id"), &AdMobBridge::load_interstitial);
	ClassDB::bind_method(D_METHOD("is_interstitial_loaded"), &AdMobBridge::is_interstitial_loaded);
	ClassDB::bind_method(D_METHOD("show_interstitial"), &AdMobBridge::show_interstitial);

	// Consent. `error` is empty on success.
	ADD_SIGNAL(MethodInfo("consent_info_updated", PropertyInfo(Variant::STRING, "error")));
	ADD_SIGNAL(MethodInfo("consent_form_dismissed", PropertyInfo(Variant::STRING, "error")));
	ADD_SIGNAL(MethodInfo("privacy_options_dismissed", PropertyInfo(Variant::STRING, "error")));
	ADD_SIGNAL(MethodInfo("started"));

	ADD_SIGNAL(MethodInfo("rewarded_loaded"));
	ADD_SIGNAL(MethodInfo("rewarded_failed_to_load", PropertyInfo(Variant::STRING, "error")));
	ADD_SIGNAL(MethodInfo("rewarded_shown"));
	ADD_SIGNAL(MethodInfo("rewarded_failed_to_show", PropertyInfo(Variant::STRING, "error")));
	ADD_SIGNAL(MethodInfo("rewarded_earned", PropertyInfo(Variant::STRING, "type"), PropertyInfo(Variant::FLOAT, "amount")));
	ADD_SIGNAL(MethodInfo("rewarded_dismissed"));

	ADD_SIGNAL(MethodInfo("interstitial_loaded"));
	ADD_SIGNAL(MethodInfo("interstitial_failed_to_load", PropertyInfo(Variant::STRING, "error")));
	ADD_SIGNAL(MethodInfo("interstitial_shown"));
	ADD_SIGNAL(MethodInfo("interstitial_failed_to_show", PropertyInfo(Variant::STRING, "error")));
	ADD_SIGNAL(MethodInfo("interstitial_dismissed"));

	BIND_CONSTANT(DEBUG_GEOGRAPHY_DISABLED);
	BIND_CONSTANT(DEBUG_GEOGRAPHY_EEA);
	BIND_CONSTANT(DEBUG_GEOGRAPHY_REGULATED_US_STATE);
	BIND_CONSTANT(DEBUG_GEOGRAPHY_OTHER);
	BIND_CONSTANT(CONSENT_UNKNOWN);
	BIND_CONSTANT(CONSENT_REQUIRED);
	BIND_CONSTANT(CONSENT_NOT_REQUIRED);
	BIND_CONSTANT(CONSENT_OBTAINED);
	BIND_CONSTANT(TRACKING_NOT_DETERMINED);
	BIND_CONSTANT(TRACKING_RESTRICTED);
	BIND_CONSTANT(TRACKING_DENIED);
	BIND_CONSTANT(TRACKING_AUTHORIZED);
	BIND_CONSTANT(AGE_UNSPECIFIED);
	BIND_CONSTANT(AGE_CHILD);
	BIND_CONSTANT(AGE_TEEN);
}
