@tool
extends EditorPlugin
## Registers the StoreKit export step. Editor-only; nothing here ships in the game.

var _export: StoreKitExportPlugin


func _enter_tree() -> void:
	_export = StoreKitExportPlugin.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null
