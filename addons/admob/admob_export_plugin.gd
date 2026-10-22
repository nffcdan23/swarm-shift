@tool
class_name AdMobExportPlugin
extends EditorExportPlugin
## Adds what the Google Mobile Ads SDK needs to an iOS export: the app id,
## the SKAdNetwork list, the App Tracking Transparency prompt text and the
## -ObjC linker flag. The libraries and SDK frameworks themselves come from
## addons/admob/admob.gdextension, which tools/build_admob.sh writes; if it has
## not been built, the export goes ahead without AdMob and says so.

const CONFIG_PATH := "res://addons/admob/admob_export.cfg"
const EXTENSION_PATH := "res://addons/admob/admob.gdextension"
## Google's published sample app id: serves test ads only.
const SAMPLE_APP_ID := "ca-app-pub-3940256099942544~1458002511"


func _get_name() -> String:
	return "AdMob"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformIOS


func _export_begin(_features: PackedStringArray, is_debug: bool, _path: String, _flags: int) -> void:
	if not FileAccess.file_exists(EXTENSION_PATH):
		push_warning("AdMob: bridge not built (run tools/build_admob.sh) - exporting without ads.")
		return
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		push_error("AdMob: cannot read %s - exporting without the AdMob Info.plist keys." % CONFIG_PATH)
		return
	var app_id := str(config.get_value("ios", "application_id", ""))
	if app_id.is_empty():
		push_error("AdMob: ios/application_id is empty in %s." % CONFIG_PATH)
		return
	if app_id == SAMPLE_APP_ID and not is_debug:
		push_warning("AdMob: release export is using Google's sample app id - it will only ever show test ads.")
	add_apple_embedded_platform_plist_content(plist_content(config))
	add_apple_embedded_platform_linker_flags("-ObjC")


static func plist_content(config: ConfigFile) -> String:
	var lines := PackedStringArray()
	lines.append("<key>GADApplicationIdentifier</key>")
	lines.append("<string>%s</string>" % _xml(str(config.get_value("ios", "application_id", ""))))
	lines.append("<key>NSUserTrackingUsageDescription</key>")
	lines.append("<string>%s</string>" % _xml(str(config.get_value("ios", "tracking_usage_description", ""))))
	lines.append("<key>SKAdNetworkItems</key>")
	lines.append("<array>")
	for id: String in config.get_value("ios", "skadnetwork_ids", PackedStringArray()):
		lines.append("<dict><key>SKAdNetworkIdentifier</key><string>%s</string></dict>" % _xml(id))
	lines.append("</array>")
	return "\n".join(lines) + "\n"


static func _xml(text: String) -> String:
	return text.xml_escape(true)
