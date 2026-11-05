@tool
class_name StoreKitExportPlugin
extends EditorExportPlugin
## The StoreKit bridge contains Swift (StoreKit 2 has no Objective-C API), but
## the Xcode project Godot exports has no Swift files of its own, so Xcode does
## not add the Swift runtime libraries to the linker's search path. This adds
## them: the SDK's Swift libraries and the toolchain's back-deployment ones.
## The libraries themselves come from addons/storekit/storekit.gdextension,
## which tools/build_storekit.sh writes; if it has not been built, the export
## goes ahead without real purchases and says so.

const EXTENSION_PATH := "res://addons/storekit/storekit.gdextension"
const SWIFT_LINKER_FLAGS := "-L$(SDKROOT)/usr/lib/swift -L$(TOOLCHAIN_DIR)/usr/lib/swift/$(PLATFORM_NAME) -Xlinker -rpath -Xlinker /usr/lib/swift"


func _get_name() -> String:
	return "StoreKit"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformIOS


func _export_begin(_features: PackedStringArray, is_debug: bool, _path: String, _flags: int) -> void:
	if not FileAccess.file_exists(EXTENSION_PATH):
		if is_debug:
			push_warning("StoreKit: bridge not built (run tools/build_storekit.sh) - exporting with the test store.")
		else:
			push_error("StoreKit: bridge not built (run tools/build_storekit.sh) - this release export has no real purchases.")
		return
	add_apple_embedded_platform_linker_flags(SWIFT_LINKER_FLAGS)
