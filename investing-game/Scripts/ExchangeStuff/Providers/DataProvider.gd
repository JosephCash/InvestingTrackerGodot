extends Node
class_name DataProvider

@warning_ignore("unused_signal")
signal fetch_successful(asset: ExchangeAssetData)

@warning_ignore("unused_signal")
signal fetch_failed(error_message: String)

func fetch_price(_asset_id: String) -> void:
	push_error("Funkcja fetch_price musi zostać nadpisana w klasie dziedziczącej!")
