// Every platform except iOS: the bridge exists so scripts can ask for it, but
// nothing is behind it. Loads fail and consent reports "cannot request ads", so
// the game falls back to its own provider choice.

#include "admob_bridge.h"

using namespace godot;

bool AdMobBridge::is_supported() const { return false; }
String AdMobBridge::get_sdk_version() const { return String(); }
void AdMobBridge::debug_log(const String &) const {}

void AdMobBridge::consent_request_update(int, const PackedStringArray &, bool) {
	emit_later("consent_info_updated", "unsupported");
}
void AdMobBridge::consent_load_and_present_if_required() {
	emit_later("consent_form_dismissed", "unsupported");
}
bool AdMobBridge::consent_can_request_ads() const { return false; }
int AdMobBridge::consent_get_status() const { return CONSENT_UNKNOWN; }
bool AdMobBridge::consent_is_privacy_options_required() const { return false; }
void AdMobBridge::consent_present_privacy_options() {
	emit_later("privacy_options_dismissed", "unsupported");
}
void AdMobBridge::consent_reset() {}
int AdMobBridge::get_tracking_status() const { return TRACKING_NOT_DETERMINED; }

void AdMobBridge::set_test_device_ids(const PackedStringArray &) {}
void AdMobBridge::set_max_ad_content_rating(const String &) {}
void AdMobBridge::set_age_treatment(int) {}
void AdMobBridge::start() {}
bool AdMobBridge::is_started() const { return false; }

void AdMobBridge::load_rewarded(const String &) {
	emit_later("rewarded_failed_to_load", "unsupported");
}
bool AdMobBridge::is_rewarded_loaded() const { return false; }
bool AdMobBridge::show_rewarded() { return false; }

void AdMobBridge::load_interstitial(const String &) {
	emit_later("interstitial_failed_to_load", "unsupported");
}
bool AdMobBridge::is_interstitial_loaded() const { return false; }
bool AdMobBridge::show_interstitial() { return false; }
