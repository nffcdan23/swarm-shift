// iOS implementation of AdMobBridge: Google Mobile Ads SDK + User Messaging
// Platform. Both SDKs call back on the main thread, which is also Godot's on
// iOS; every callback still goes out as a deferred signal so GDScript never
// runs inside an SDK callback.
//
// Every event is also written to the device log (NSLog, prefix "[admob]"),
// which `devicectl device process launch --console` shows on a Mac.

#include "admob_bridge.h"

#include <godot_cpp/classes/engine.hpp>

#import <AVFoundation/AVFoundation.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <GoogleMobileAds/GoogleMobileAds.h>
#import <UIKit/UIKit.h>
#import <UserMessagingPlatform/UserMessagingPlatform.h>

using namespace godot;

static NSString *to_ns(const String &p_text) {
	return [NSString stringWithUTF8String:p_text.utf8().get_data()];
}

static String to_godot(NSString *p_text) {
	return p_text == nil ? String() : String::utf8(p_text.UTF8String);
}

static String describe(NSError *p_error) {
	if (p_error == nil) {
		return String();
	}
	return vformat("%s (%d): %s", to_godot(p_error.domain), (int64_t)p_error.code, to_godot(p_error.localizedDescription));
}

static NSArray<NSString *> *to_ns_array(const PackedStringArray &p_items) {
	NSMutableArray<NSString *> *out = [NSMutableArray arrayWithCapacity:p_items.size()];
	for (int64_t i = 0; i < p_items.size(); i++) {
		[out addObject:to_ns(p_items[i])];
	}
	return out;
}

static void log_line(NSString *p_text) {
	NSLog(@"[admob] %@", p_text);
}

// Logs an SDK event, then emits it as a deferred signal with `p_args` arguments.
static void notify(const String &p_signal, int p_args = 0, const Variant &p_arg1 = Variant(), const Variant &p_arg2 = Variant()) {
	String line = p_signal;
	if (p_args > 0) {
		line += " " + p_arg1.stringify();
	}
	if (p_args > 1) {
		line += " " + p_arg2.stringify();
	}
	log_line(to_ns(line));
	AdMobBridge *bridge = AdMobBridge::get_singleton();
	if (bridge == nullptr) {
		return;
	}
	if (p_args == 0) {
		bridge->emit_later(p_signal);
	} else if (p_args == 1) {
		bridge->emit_later(p_signal, p_arg1);
	} else {
		bridge->emit_later(p_signal, p_arg1, p_arg2);
	}
}

// Godot treats an audio session interruption as losing focus and stops its
// main loop until the interruption ends. After an ad or a form closes, check
// that Godot's frames are still advancing, and say so in the device log.
static void watch_for_stall(NSString *p_after) {
	uint64_t before = Engine::get_singleton()->get_process_frames();
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		uint64_t now = Engine::get_singleton()->get_process_frames();
		log_line([NSString stringWithFormat:@"frames after %@: %llu -> %llu (%@)", p_after, before, now, now > before ? @"running" : @"STALLED"]);
	});
}

// The view controller on top of Godot's window, for UMP forms. (The ads find
// their own: GMA presents from the top view controller when given nil.)
static UIViewController *top_view_controller() {
	UIWindow *window = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) {
			continue;
		}
		for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
			if (candidate.isKeyWindow || window == nil) {
				window = candidate;
			}
		}
	}
	UIViewController *controller = window.rootViewController;
	while (controller.presentedViewController != nil) {
		controller = controller.presentedViewController;
	}
	return controller;
}

// One delegate per format, so dismiss and failure callbacks know which signals
// to emit.
@interface GDAdMobFullScreenDelegate : NSObject <GADFullScreenContentDelegate>
@property(nonatomic, copy) NSString *format;
@end

static GADRewardedAd *rewarded_ad = nil;
static GADInterstitialAd *interstitial_ad = nil;
static GDAdMobFullScreenDelegate *rewarded_delegate = nil;
static GDAdMobFullScreenDelegate *interstitial_delegate = nil;
static bool rewarded_loading = false;
static bool interstitial_loading = false;
static bool started = false;
static bool starting = false;

@implementation GDAdMobFullScreenDelegate

// Logs every audio session interruption with the session state at the time.
+ (void)load {
	[NSNotificationCenter.defaultCenter addObserverForName:AVAudioSessionInterruptionNotification
													object:nil
													 queue:NSOperationQueue.mainQueue
												usingBlock:^(NSNotification *note) {
													NSNumber *type = note.userInfo[AVAudioSessionInterruptionTypeKey];
													NSNumber *reason = note.userInfo[AVAudioSessionInterruptionReasonKey];
													log_line([NSString stringWithFormat:@"audio interruption %@ (reason %@), category %@, other audio %d",
																	   type.integerValue == AVAudioSessionInterruptionTypeBegan ? @"began" : @"ended",
																	   reason, AVAudioSession.sharedInstance.category,
																	   (int)AVAudioSession.sharedInstance.isOtherAudioPlaying]);
												}];
}

- (void)adWillPresentFullScreenContent:(id<GADFullScreenPresentingAd>)ad {
	notify(to_godot(self.format) + "_shown");
}

- (void)ad:(id<GADFullScreenPresentingAd>)ad didFailToPresentFullScreenContentWithError:(NSError *)error {
	[self forget:ad];
	notify(to_godot(self.format) + "_failed_to_show", 1, describe(error));
}

- (void)adDidDismissFullScreenContent:(id<GADFullScreenPresentingAd>)ad {
	[self forget:ad];
	notify(to_godot(self.format) + "_dismissed");
	watch_for_stall([self.format stringByAppendingString:@" dismissed"]);
}

// A full-screen ad can be shown once; drop it so the next load starts clean.
- (void)forget:(id<GADFullScreenPresentingAd>)ad {
	if (ad == rewarded_ad) {
		rewarded_ad = nil;
	} else if (ad == interstitial_ad) {
		interstitial_ad = nil;
	}
}

@end

// ------------------------------------------------------------------ general

bool AdMobBridge::is_supported() const {
	return true;
}

String AdMobBridge::get_sdk_version() const {
	// GADGetStringFromVersionNumber is declared without extern "C", so it cannot
	// be linked from Objective-C++.
	GADVersionNumber version = GADMobileAds.sharedInstance.versionNumber;
	return vformat("%d.%d.%d", (int64_t)version.majorVersion, (int64_t)version.minorVersion, (int64_t)version.patchVersion);
}

void AdMobBridge::debug_log(const String &p_text) const {
	log_line(to_ns(p_text));
}

// ------------------------------------------------------------------ consent

void AdMobBridge::consent_request_update(int p_debug_geography, const PackedStringArray &p_test_device_ids, bool p_under_age_of_consent) {
	UMPRequestParameters *parameters = [[UMPRequestParameters alloc] init];
	parameters.tagForUnderAgeOfConsent = p_under_age_of_consent;
	if (p_debug_geography != DEBUG_GEOGRAPHY_DISABLED || p_test_device_ids.size() > 0) {
		UMPDebugSettings *debug = [[UMPDebugSettings alloc] init];
		debug.geography = (UMPDebugGeography)p_debug_geography;
		debug.testDeviceIdentifiers = to_ns_array(p_test_device_ids);
		parameters.debugSettings = debug;
	}
	[UMPConsentInformation.sharedInstance requestConsentInfoUpdateWithParameters:parameters
															   completionHandler:^(NSError *error) {
																   notify("consent_info_updated", 1, describe(error));
															   }];
}

void AdMobBridge::consent_load_and_present_if_required() {
	[UMPConsentForm loadAndPresentIfRequiredFromViewController:top_view_controller()
											 completionHandler:^(NSError *error) {
												 notify("consent_form_dismissed", 1, describe(error));
												 watch_for_stall(@"consent form");
											 }];
}

bool AdMobBridge::consent_can_request_ads() const {
	return UMPConsentInformation.sharedInstance.canRequestAds;
}

int AdMobBridge::consent_get_status() const {
	return (int)UMPConsentInformation.sharedInstance.consentStatus;
}

bool AdMobBridge::consent_is_privacy_options_required() const {
	return UMPConsentInformation.sharedInstance.privacyOptionsRequirementStatus == UMPPrivacyOptionsRequirementStatusRequired;
}

void AdMobBridge::consent_present_privacy_options() {
	[UMPConsentForm presentPrivacyOptionsFormFromViewController:top_view_controller()
											  completionHandler:^(NSError *error) {
												  notify("privacy_options_dismissed", 1, describe(error));
												  watch_for_stall(@"privacy options");
											  }];
}

// Testing only: forget the stored consent so the form shows again.
void AdMobBridge::consent_reset() {
	[UMPConsentInformation.sharedInstance reset];
}

int AdMobBridge::get_tracking_status() const {
	if (@available(iOS 14, *)) {
		return (int)ATTrackingManager.trackingAuthorizationStatus;
	}
	return TRACKING_AUTHORIZED;
}

// --------------------------------------------------------------------- SDK

void AdMobBridge::set_test_device_ids(const PackedStringArray &p_ids) {
	GADMobileAds.sharedInstance.requestConfiguration.testDeviceIdentifiers = to_ns_array(p_ids);
}

// "G", "PG", "T" or "MA"; anything else clears the cap.
void AdMobBridge::set_max_ad_content_rating(const String &p_rating) {
	GADMaxAdContentRating rating = nil;
	if (p_rating == "G") {
		rating = GADMaxAdContentRatingGeneral;
	} else if (p_rating == "PG") {
		rating = GADMaxAdContentRatingParentalGuidance;
	} else if (p_rating == "T") {
		rating = GADMaxAdContentRatingTeen;
	} else if (p_rating == "MA") {
		rating = GADMaxAdContentRatingMatureAudience;
	}
	GADMobileAds.sharedInstance.requestConfiguration.maxAdContentRating = rating;
}

void AdMobBridge::set_age_treatment(int p_treatment) {
	GADMobileAds.sharedInstance.requestConfiguration.ageRestrictedTreatment = (GADAgeRestrictedTreatment)p_treatment;
}

// Only call once consent_can_request_ads() is true.
void AdMobBridge::start() {
	if (started || starting) {
		return;
	}
	starting = true;
	[GADMobileAds.sharedInstance startWithCompletionHandler:^(GADInitializationStatus *status) {
		started = true;
		starting = false;
		notify("started");
	}];
}

bool AdMobBridge::is_started() const {
	return started;
}

// ---------------------------------------------------------------- rewarded

void AdMobBridge::load_rewarded(const String &p_unit_id) {
	if (rewarded_loading || rewarded_ad != nil) {
		return;
	}
	rewarded_loading = true;
	[GADRewardedAd loadWithAdUnitID:to_ns(p_unit_id)
							request:[GADRequest request]
				  completionHandler:^(GADRewardedAd *ad, NSError *error) {
					  rewarded_loading = false;
					  if (error != nil || ad == nil) {
						  notify("rewarded_failed_to_load", 1, describe(error));
						  return;
					  }
					  if (rewarded_delegate == nil) {
						  rewarded_delegate = [[GDAdMobFullScreenDelegate alloc] init];
						  rewarded_delegate.format = @"rewarded";
					  }
					  rewarded_ad = ad;
					  rewarded_ad.fullScreenContentDelegate = rewarded_delegate;
					  notify("rewarded_loaded");
				  }];
}

bool AdMobBridge::is_rewarded_loaded() const {
	return rewarded_ad != nil;
}

// Returns false if there is nothing to show. On true, expect rewarded_shown,
// then rewarded_earned (only if the reward was earned), then rewarded_dismissed.
bool AdMobBridge::show_rewarded() {
	if (rewarded_ad == nil) {
		return false;
	}
	GADRewardedAd *ad = rewarded_ad;
	[ad presentFromRootViewController:nil
			 userDidEarnRewardHandler:^{
				 notify("rewarded_earned", 2, to_godot(ad.adReward.type), ad.adReward.amount.doubleValue);
			 }];
	return true;
}

// ------------------------------------------------------------ interstitial

void AdMobBridge::load_interstitial(const String &p_unit_id) {
	if (interstitial_loading || interstitial_ad != nil) {
		return;
	}
	interstitial_loading = true;
	[GADInterstitialAd loadWithAdUnitID:to_ns(p_unit_id)
								request:[GADRequest request]
					  completionHandler:^(GADInterstitialAd *ad, NSError *error) {
						  interstitial_loading = false;
						  if (error != nil || ad == nil) {
							  notify("interstitial_failed_to_load", 1, describe(error));
							  return;
						  }
						  if (interstitial_delegate == nil) {
							  interstitial_delegate = [[GDAdMobFullScreenDelegate alloc] init];
							  interstitial_delegate.format = @"interstitial";
						  }
						  interstitial_ad = ad;
						  interstitial_ad.fullScreenContentDelegate = interstitial_delegate;
						  notify("interstitial_loaded");
					  }];
}

bool AdMobBridge::is_interstitial_loaded() const {
	return interstitial_ad != nil;
}

bool AdMobBridge::show_interstitial() {
	if (interstitial_ad == nil) {
		return false;
	}
	[interstitial_ad presentFromRootViewController:nil];
	return true;
}
