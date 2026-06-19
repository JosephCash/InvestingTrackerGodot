extends Resource
class_name AssetData

const SCHEMA_VERSION := 2

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
@export var history_last_updated: float = 0.0


func add_price_point(date: String, close: float, currency: String = "", source: String = "") -> Error:
	var clean_date := date.strip_edges()
	var clean_currency := _normalize_currency(currency)
	var clean_source := source.strip_edges()

	if clean_date.is_empty() or close < 0.0:
		return ERR_INVALID_PARAMETER

	if clean_currency.is_empty():
		clean_currency = quote_currency

	var price_point: Dictionary = {
		"date": clean_date,
		"close": close,
		"currency": clean_currency,
		"source": clean_source
	}

	var replaced_existing: bool = false
	for index in range(price_history.size()):
		var existing_point: Dictionary = price_history[index]
		if str(existing_point.get("date", "")) != clean_date:
			continue
		if _normalize_currency(str(existing_point.get("currency", ""))) != clean_currency:
			continue
		if str(existing_point.get("source", "")) != clean_source:
			continue

		price_history[index] = price_point
		replaced_existing = true
		break

	if not replaced_existing:
		price_history.append(price_point)

	_sort_price_history_by_date()

	var now: float = Time.get_unix_time_from_system()
	if clean_source.contains(":history"):
		history_last_updated = now
	else:
		last_updated = now

	return OK


func merge_price_history_from(other: AssetData) -> void:
	if other == null:
		return

	for price_point in other.price_history:
		add_price_point(
			str(price_point.get("date", "")),
			float(price_point.get("close", -1.0)),
			str(price_point.get("currency", other.quote_currency)),
			str(price_point.get("source", ""))
		)

	if other.history_last_updated > history_last_updated:
		history_last_updated = other.history_last_updated


func get_latest_price_point() -> Dictionary:
	if price_history.is_empty():
		return {}

	var latest_current_point: Dictionary = {}
	for price_point in price_history:
		var source: String = str(price_point.get("source", ""))
		if source.contains(":history"):
			continue

		latest_current_point = price_point

	if not latest_current_point.is_empty():
		return latest_current_point.duplicate(true)

	return price_history[price_history.size() - 1].duplicate(true)


func get_history_price_points() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for price_point in price_history:
		var source: String = str(price_point.get("source", ""))
		if source.contains(":history"):
			result.append(price_point.duplicate(true))

	return result


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
		"last_updated": last_updated,
		"history_last_updated": history_last_updated
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
	asset.history_last_updated = float(data.get("history_last_updated", 0.0))
	if asset.history_last_updated > 0.0 and asset.last_updated == asset.history_last_updated:
		if asset._has_history_points() and asset._has_current_price_points():
			asset.last_updated = 0.0

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


func _sort_price_history_by_date() -> void:
	for index in range(price_history.size()):
		var min_index: int = index

		for compare_index in range(index + 1, price_history.size()):
			var compare_date: String = str(price_history[compare_index].get("date", ""))
			var min_date: String = str(price_history[min_index].get("date", ""))
			if compare_date < min_date:
				min_index = compare_index

		if min_index != index:
			var current_point: Dictionary = price_history[index]
			price_history[index] = price_history[min_index]
			price_history[min_index] = current_point


func _has_history_points() -> bool:
	for price_point in price_history:
		var source: String = str(price_point.get("source", ""))
		if source.contains(":history"):
			return true

	return false


func _has_current_price_points() -> bool:
	for price_point in price_history:
		var source: String = str(price_point.get("source", ""))
		if not source.contains(":history"):
			return true

	return false
