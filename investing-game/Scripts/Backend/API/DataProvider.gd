extends Node
class_name DataProvider

@warning_ignore("unused_signal")
signal fetch_successful(asset: AssetData)

@warning_ignore("unused_signal")
signal fetch_failed(asset_id: String, error_message: String)

@warning_ignore("unused_signal")
signal fetch_history_successful(asset: AssetData)

@warning_ignore("unused_signal")
signal fetch_history_failed(asset_id: String, error_message: String)


func fetch_price(_asset_id: String) -> void:
	push_error("fetch_price must be overridden by a child provider.")


func fetch_history(_asset_id: String, _range_value: Variant = null, _interval: String = "1d") -> void:
	push_error("fetch_history must be overridden by a child provider.")
