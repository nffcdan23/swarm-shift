class_name AnalyticsProvider
extends RefCounted
## Sink for analytics events. Implement this for Firebase, GameAnalytics, or an
## in-house endpoint and register it with `Analytics.add_provider()`.


func track(_event: String, _props: Dictionary) -> void:
	pass


func set_user_property(_key: String, _value: Variant) -> void:
	pass


func flush() -> void:
	pass
