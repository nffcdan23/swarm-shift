#pragma once

// AdMobBridge: the Godot-facing side of the Google Mobile Ads + UMP bridge.
//
// One object, registered as the engine singleton "AdMob". GDScript drives it
// with plain calls and listens to its signals; every SDK callback is turned
// into a deferred signal, so handlers always run on the main loop between
// frames. It holds no ad policy: what to show and when is AdsService's job.
//
// The iOS build (admob_ios.mm) talks to the real SDKs. Every other platform
// gets admob_stub.cpp, which reports is_supported() == false, so desktop runs
// and tests see the class without any SDK behind it.

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class AdMobBridge : public Object {
	GDCLASS(AdMobBridge, Object)

	static AdMobBridge *singleton;

protected:
	static void _bind_methods();

public:
	// Values match UMPDebugGeography.
	enum DebugGeography {
		DEBUG_GEOGRAPHY_DISABLED = 0,
		DEBUG_GEOGRAPHY_EEA = 1,
		DEBUG_GEOGRAPHY_REGULATED_US_STATE = 3,
		DEBUG_GEOGRAPHY_OTHER = 4,
	};

	// Values match UMPConsentStatus.
	enum ConsentStatus {
		CONSENT_UNKNOWN = 0,
		CONSENT_REQUIRED = 1,
		CONSENT_NOT_REQUIRED = 2,
		CONSENT_OBTAINED = 3,
	};

	// Values match ATTrackingManagerAuthorizationStatus.
	enum TrackingStatus {
		TRACKING_NOT_DETERMINED = 0,
		TRACKING_RESTRICTED = 1,
		TRACKING_DENIED = 2,
		TRACKING_AUTHORIZED = 3,
	};

	// Values match GADAgeRestrictedTreatment.
	enum AgeTreatment {
		AGE_UNSPECIFIED = 0,
		AGE_CHILD = 1,
		AGE_TEEN = 2,
	};

	static AdMobBridge *get_singleton() { return singleton; }

	AdMobBridge();
	~AdMobBridge();

	// Emits `signal` with up to two arguments on the next idle frame.
	void emit_later(const StringName &p_signal);
	void emit_later(const StringName &p_signal, const Variant &p_arg1);
	void emit_later(const StringName &p_signal, const Variant &p_arg1, const Variant &p_arg2);

	// --- platform (admob_ios.mm / admob_stub.cpp)
	bool is_supported() const;
	String get_sdk_version() const;
	// Writes to the device log (NSLog), which a Mac attached with
	// `devicectl --console` can read; Godot's own print() does not get there.
	void debug_log(const String &p_text) const;

	void consent_request_update(int p_debug_geography, const PackedStringArray &p_test_device_ids, bool p_under_age_of_consent);
	void consent_load_and_present_if_required();
	bool consent_can_request_ads() const;
	int consent_get_status() const;
	bool consent_is_privacy_options_required() const;
	void consent_present_privacy_options();
	void consent_reset();
	int get_tracking_status() const;

	void set_test_device_ids(const PackedStringArray &p_ids);
	void set_max_ad_content_rating(const String &p_rating);
	void set_age_treatment(int p_treatment);
	void start();
	bool is_started() const;

	void load_rewarded(const String &p_unit_id);
	bool is_rewarded_loaded() const;
	bool show_rewarded();

	void load_interstitial(const String &p_unit_id);
	bool is_interstitial_loaded() const;
	bool show_interstitial();
};

} // namespace godot
