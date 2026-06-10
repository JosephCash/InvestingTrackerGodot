extends Resource
class_name AssetData

const SCHEMA_VERSION := 1

const TYPE_CRYPTO := "crypto"
const TYPE_FIAT := "fiat"
const TYPE_STOCK := "stock"
const TYPE_ETF := "etf"
const TYPE_BOND := "bond"
const TYPE_INDEX := "index"
const TYPE_OTHER := "other"

@export var id: String = ""
@export var symbol: String = ""
@export var name: String = ""
@export var asset_type: String = TYPE_OTHER
@export var quote_currency: String = "PLN"
@export var price_history: Array[Dictionary] = []
@export var last_updated: float = 0.0


func add_price_point(date: String, close: float, currency: String = "", source: String = "") -> Error:
	var clean_date := date.strip_edges()
	var clean_currency := _normalize_currency(currency)

	if clean_date.is_empty() or close < 0.0:
		return ERR_INVALID_PARAMETER

	if clean_currency.is_empty():
		clean_currency = quote_currency

	price_history.append({
		"date": clean_date,
		"close": close,
		"currency": clean_currency,
		"source": source.strip_edges()
	})
	last_updated = Time.get_unix_time_from_system()

	return OK


func get_latest_price_point() -> Dictionary:
	if price_history.is_empty():
		return {}

	return price_history[price_history.size() - 1].duplicate(true)


func validate() -> PackedStringArray:
	var errors := PackedStringArray()

	if id.strip_edges().is_empty():
		errors.append("Asset id is empty.")

	if symbol.strip_edges().is_empty():
		errors.append("Asset symbol is empty.")

	if _normalize_currency(quote_currency).is_empty():
		errors.append("Quote currency is empty.")

	if not _is_supported_type(asset_type):
		errors.append("Unsupported asset type: %s." % asset_type)

	for price_point in price_history:
		if not price_point.has("date") or str(price_point["date"]).strip_edges().is_empty():
			errors.append("Price point has empty date.")
		if not price_point.has("close") or float(price_point["close"]) < 0.0:
			errors.append("Price point has invalid close price.")

	return errors


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"id": id,
		"symbol": symbol.strip_edges().to_upper(),
		"name": name.strip_edges(),
		"asset_type": asset_type.strip_edges().to_lower(),
		"quote_currency": _normalize_currency(quote_currency),
		"price_history": price_history.duplicate(true),
		"last_updated": last_updated
	}


static func from_dict(data: Dictionary) -> AssetData:
	var asset := AssetData.new()

	asset.id = str(data.get("id", ""))
	asset.symbol = str(data.get("symbol", "")).strip_edges().to_upper()
	asset.name = str(data.get("name", ""))
	asset.asset_type = str(data.get("asset_type", TYPE_OTHER)).strip_edges().to_lower()
	asset.quote_currency = AssetData._normalize_currency(str(data.get("quote_currency", "PLN")))
	asset.price_history = AssetData._copy_dictionary_array(data.get("price_history", []))
	asset.last_updated = float(data.get("last_updated", 0.0))

	return asset


static func _normalize_currency(currency: String) -> String:
	return currency.strip_edges().to_upper()


static func _is_supported_type(value: String) -> bool:
	return value.strip_edges().to_lower() in [
		TYPE_CRYPTO,
		TYPE_FIAT,
		TYPE_STOCK,
		TYPE_ETF,
		TYPE_BOND,
		TYPE_INDEX,
		TYPE_OTHER
	]


static func _copy_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	if value is Array:
		for item in value:
			if item is Dictionary:
				result.append(item.duplicate(true))

	return result
