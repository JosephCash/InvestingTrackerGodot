extends Node

const CACHE_SCHEMA_VERSION := 2
const CACHE_FILE_PATH := "user://exchange_cache.json"
const INFLATION_CACHE_FILE_PATH := "user://inflation_cache.json"
const MONTHLY_INFLATION_CACHE_FILE_PATH := "user://inflation_monthly_cache.json"
const SETTINGS_FILE_PATH := "user://settings.json"


func save_exchange_cache(cached_assets: Dictionary) -> void:
	var dict_to_save := {
		"schema_version": CACHE_SCHEMA_VERSION,
		"cache_currency": SettingsManager.base_currency,
		"assets": {}
	}

	for key in cached_assets:
		var asset = cached_assets[key]
		if asset is AssetData:
			dict_to_save["assets"][key] = asset.to_dict()

	var file := FileAccess.open(CACHE_FILE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] Cannot open exchange cache file for writing.")
		return

	file.store_string(JSON.stringify(dict_to_save))
	print("[SaveManager] Saved exchange cache for currency: ", SettingsManager.base_currency)


func load_exchange_cache() -> Dictionary:
	var restored_assets: Dictionary = {}

	if not FileAccess.file_exists(CACHE_FILE_PATH):
		print("[SaveManager] No exchange cache file. Starting with empty cache.")
		return restored_assets

	var file := FileAccess.open(CACHE_FILE_PATH, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] Cannot open exchange cache file for reading.")
		return restored_assets

	var parsed_data = JSON.parse_string(file.get_as_text())
	if not (parsed_data is Dictionary):
		push_error("[SaveManager] Exchange cache JSON is invalid.")
		return restored_assets

	if not parsed_data.has("cache_currency") or not parsed_data.has("assets"):
		print("[SaveManager] Unsupported exchange cache format. Ignoring file.")
		return restored_assets

	if parsed_data["cache_currency"] != SettingsManager.base_currency:
		print("[SaveManager] Cache currency differs from current currency. Ignoring old cache.")
		return restored_assets

	var assets_data = parsed_data["assets"]
	if not (assets_data is Dictionary):
		push_error("[SaveManager] Exchange cache assets section is invalid.")
		return restored_assets

	var schema_version := int(parsed_data.get("schema_version", 1))

	for key in assets_data:
		var asset_data = assets_data[key]
		if not (asset_data is Dictionary):
			continue

		var restored_asset: AssetData
		if schema_version >= 2:
			restored_asset = AssetData.from_dict(asset_data)
		else:
			restored_asset = _migrate_legacy_exchange_asset(asset_data)

		if restored_asset != null:
			restored_assets[str(key)] = restored_asset

	print("[SaveManager] Loaded ", restored_assets.size(), " exchange cache assets.")
	return restored_assets


func save_inflation_cache(inflation: InflationData) -> Error:
	if inflation == null:
		push_error("[SaveManager] Cannot save null inflation data.")
		return ERR_INVALID_PARAMETER

	var validation_errors := inflation.validate()
	if not validation_errors.is_empty():
		push_error("[SaveManager] Cannot save invalid inflation data: %s" % str(validation_errors))
		return ERR_INVALID_DATA

	var file := FileAccess.open(INFLATION_CACHE_FILE_PATH, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		push_error("[SaveManager] Cannot open inflation cache file for writing: %s" % error_string(open_error))
		return open_error

	file.store_string(JSON.stringify(inflation.to_dict()))
	file.flush()
	print("[SaveManager] Saved inflation cache: ", inflation.year)
	return OK


func save_monthly_inflation_cache(inflation: InflationData) -> Error:
	if inflation == null:
		push_error("[SaveManager] Cannot save null monthly inflation data.")
		return ERR_INVALID_PARAMETER

	var validation_errors := inflation.validate()
	if not validation_errors.is_empty():
		push_error("[SaveManager] Cannot save invalid monthly inflation data: %s" % str(validation_errors))
		return ERR_INVALID_DATA

	var file := FileAccess.open(MONTHLY_INFLATION_CACHE_FILE_PATH, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		push_error("[SaveManager] Cannot open monthly inflation cache file for writing: %s" % error_string(open_error))
		return open_error

	file.store_string(JSON.stringify(inflation.to_dict()))
	file.flush()
	print("[SaveManager] Saved monthly inflation cache: ", inflation.get_period_label())
	return OK


func load_inflation_cache() -> InflationData:
	if not FileAccess.file_exists(INFLATION_CACHE_FILE_PATH):
		print("[SaveManager] No inflation cache file.")
		return null

	var file := FileAccess.open(INFLATION_CACHE_FILE_PATH, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] Cannot open inflation cache file for reading.")
		return null

	var parsed_data = JSON.parse_string(file.get_as_text())
	if not (parsed_data is Dictionary):
		push_error("[SaveManager] Inflation cache JSON is invalid.")
		return null

	var inflation := InflationData.from_dict(parsed_data)
	var validation_errors := inflation.validate()
	if not validation_errors.is_empty():
		push_error("[SaveManager] Loaded inflation cache is invalid: %s" % str(validation_errors))
		return null

	print("[SaveManager] Loaded inflation cache: ", inflation.year)
	return inflation


func load_monthly_inflation_cache() -> InflationData:
	if not FileAccess.file_exists(MONTHLY_INFLATION_CACHE_FILE_PATH):
		print("[SaveManager] No monthly inflation cache file.")
		return null

	var file := FileAccess.open(MONTHLY_INFLATION_CACHE_FILE_PATH, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] Cannot open monthly inflation cache file for reading.")
		return null

	var parsed_data = JSON.parse_string(file.get_as_text())
	if not (parsed_data is Dictionary):
		push_error("[SaveManager] Monthly inflation cache JSON is invalid.")
		return null

	var inflation := InflationData.from_dict(parsed_data)
	var validation_errors := inflation.validate()
	if not validation_errors.is_empty():
		push_error("[SaveManager] Loaded monthly inflation cache is invalid: %s" % str(validation_errors))
		return null

	print("[SaveManager] Loaded monthly inflation cache: ", inflation.get_period_label())
	return inflation


func save_settings(settings_dict: Dictionary) -> void:
	var file := FileAccess.open(SETTINGS_FILE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] Cannot open settings file for writing.")
		return

	file.store_string(JSON.stringify(settings_dict))
	print("[SaveManager] Saved settings.")


func load_settings() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS_FILE_PATH):
		return {}

	var file := FileAccess.open(SETTINGS_FILE_PATH, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] Cannot open settings file for reading.")
		return {}

	var parsed_data = JSON.parse_string(file.get_as_text())
	if parsed_data is Dictionary:
		return parsed_data

	return {}


func save_portfolio(portfolio: PortfolioData) -> Error:
	var result := PortfolioRepository.new().save_portfolio(portfolio)
	if not result.is_ok():
		push_error("[SaveManager] %s" % result.message)
		return result.error_code

	print("[SaveManager] Saved portfolio: ", portfolio.id)
	return result.error_code


func load_portfolio(portfolio_id: String) -> PortfolioData:
	var result := PortfolioRepository.new().load_portfolio(portfolio_id)
	if not result.is_ok():
		print("[SaveManager] ", result.message)
		return null

	var portfolio: PortfolioData = result.data
	print("[SaveManager] Loaded portfolio: ", portfolio.id)
	return portfolio


func load_all_portfolios() -> Array[PortfolioData]:
	var result := PortfolioRepository.new().load_all_portfolios()
	if not result.is_ok():
		push_error("[SaveManager] %s" % result.message)
		return []

	var portfolios: Array[PortfolioData] = []
	if result.data is Array:
		for item in result.data:
			if item is PortfolioData:
				portfolios.append(item)

	return portfolios


func delete_portfolio(portfolio_id: String) -> Error:
	var result := PortfolioRepository.new().delete_portfolio(portfolio_id)
	if not result.is_ok():
		push_error("[SaveManager] %s" % result.message)
		return result.error_code

	print("[SaveManager] Deleted portfolio: ", portfolio_id)
	return OK


func _migrate_legacy_exchange_asset(data: Dictionary) -> AssetData:
	if not data.has("id") or not data.has("symbol") or not data.has("price"):
		return null

	var asset := AssetData.new()
	asset.id = str(data["id"])
	asset.symbol = str(data["symbol"]).to_upper()
	asset.name = asset.symbol
	asset.asset_type = _guess_legacy_asset_type(asset.id)
	asset.quote_currency = SettingsManager.base_currency.to_upper()
	asset.last_updated = float(data.get("last_updated", 0.0))

	var price_date := _date_string_from_unix_time(asset.last_updated)
	asset.price_history.append({
		"date": price_date,
		"close": float(data["price"]),
		"currency": asset.quote_currency,
		"source": "legacy cache"
	})

	return asset


func _guess_legacy_asset_type(asset_id: String) -> String:
	var normalized_id := asset_id.strip_edges().to_lower()
	if normalized_id in ["eur", "usd", "pln", "gbp", "chf", "jpy"]:
		return AssetData.TYPE_FIAT
	if normalized_id in ["bitcoin", "ethereum"]:
		return AssetData.TYPE_CRYPTO

	return AssetData.TYPE_OTHER


func _date_string_from_unix_time(unix_time: float) -> String:
	var timestamp := int(unix_time)
	if timestamp <= 0:
		timestamp = int(Time.get_unix_time_from_system())

	var date_parts := Time.get_datetime_dict_from_unix_time(timestamp)
	return "%04d-%02d-%02d" % [
		int(date_parts["year"]),
		int(date_parts["month"]),
		int(date_parts["day"])
	]
