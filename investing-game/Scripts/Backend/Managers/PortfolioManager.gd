extends Node

signal portfolio_updated(asset: AssetData)
signal asset_fetch_failed(asset_id: String, error_message: String)
signal asset_history_updated(asset: AssetData)
signal asset_history_fetch_failed(asset_id: String, error_message: String)

const CACHE_DURATION_SECONDS: float = 15.0 * 60.0
const HISTORY_CACHE_DURATION_SECONDS: float = 24.0 * 60.0 * 60.0

var cached_assets: Dictionary = {}

var crypto_api: CoinGeckoProvider
var fiat_api: NbpProvider
var yahoo_api: YahooFinanceProvider


func _ready() -> void:
	cached_assets = SaveManager.load_exchange_cache()

	SettingsManager.base_currency_changed.connect(_on_base_currency_changed)

	crypto_api = CoinGeckoProvider.new()
	add_child(crypto_api)
	crypto_api.fetch_successful.connect(_on_asset_fetched)
	crypto_api.fetch_failed.connect(_on_asset_fetch_failed)
	crypto_api.fetch_history_successful.connect(_on_asset_history_fetched)
	crypto_api.fetch_history_failed.connect(_on_asset_history_fetch_failed)

	fiat_api = NbpProvider.new()
	add_child(fiat_api)
	fiat_api.fetch_successful.connect(_on_asset_fetched)
	fiat_api.fetch_failed.connect(_on_asset_fetch_failed)

	yahoo_api = YahooFinanceProvider.new()
	add_child(yahoo_api)
	yahoo_api.fetch_successful.connect(_on_asset_fetched)
	yahoo_api.fetch_failed.connect(_on_asset_fetch_failed)
	yahoo_api.fetch_history_successful.connect(_on_asset_history_fetched)
	yahoo_api.fetch_history_failed.connect(_on_asset_history_fetch_failed)


func request_crypto_price(crypto_id: String) -> void:
	var cache_key := _cache_key(crypto_id)
	if not _check_cache(cache_key, "coingecko"):
		print("[API] Fetching crypto: ", crypto_id)
		crypto_api.fetch_price(crypto_id)


func request_crypto_history(crypto_id: String, days: int = 365) -> void:
	var resolved_asset: Dictionary = TickerResolver.resolve_for_coingecko(crypto_id)
	var asset_id: String = str(resolved_asset.get("symbol", ""))
	var cache_key: String = _cache_key(asset_id)
	if not _check_history_cache(cache_key, "coingecko:history"):
		print("[API] Fetching crypto history: %s | days=%d" % [asset_id, days])
		crypto_api.fetch_history(asset_id, days)


func request_fiat_price(fiat_id: String) -> void:
	var cache_key := _cache_key(fiat_id)
	if not _check_cache(cache_key, "nbp"):
		print("[API] Fetching fiat: ", fiat_id)
		fiat_api.fetch_price(fiat_id)


func request_stock_price(symbol: String) -> void:
	request_yahoo_price(symbol, AssetData.TYPE_STOCK)


func request_yahoo_price(symbol: String, preferred_asset_type: String = AssetData.TYPE_OTHER) -> void:
	var resolved_symbol := TickerResolver.resolve_for_yahoo(symbol)
	var yahoo_symbol := str(resolved_symbol["symbol"])
	var cache_key := _cache_key(yahoo_symbol)
	if not _check_cache(cache_key, "yahoo_finance"):
		_print_symbol_resolution(resolved_symbol)
		print("[API] Fetching Yahoo asset: %s | type=%s" % [yahoo_symbol, preferred_asset_type])
		yahoo_api.fetch_price_as(yahoo_symbol, preferred_asset_type)


func request_stock_history(symbol: String, range_value: String = "1y", interval: String = "1d") -> void:
	request_yahoo_history(symbol, AssetData.TYPE_STOCK, range_value, interval)


func request_etf_price(symbol: String) -> void:
	request_yahoo_price(symbol, AssetData.TYPE_ETF)


func request_etf_history(symbol: String, range_value: String = "1y", interval: String = "1d") -> void:
	request_yahoo_history(symbol, AssetData.TYPE_ETF, range_value, interval)


func request_index_price(symbol: String) -> void:
	request_yahoo_price(symbol, AssetData.TYPE_INDEX)


func request_index_history(symbol: String, range_value: String = "1y", interval: String = "1d") -> void:
	request_yahoo_history(symbol, AssetData.TYPE_INDEX, range_value, interval)


func request_yahoo_history(
	symbol: String,
	preferred_asset_type: String = AssetData.TYPE_OTHER,
	range_value: String = "1y",
	interval: String = "1d"
) -> void:
	var resolved_symbol: Dictionary = TickerResolver.resolve_for_yahoo(symbol)
	var yahoo_symbol: String = str(resolved_symbol.get("symbol", ""))
	var cache_key: String = _cache_key(yahoo_symbol)
	if not _check_history_cache(cache_key, "yahoo_finance:history"):
		_print_symbol_resolution(resolved_symbol)
		print("[API] Fetching Yahoo history: %s | type=%s | range=%s | interval=%s" % [
			yahoo_symbol,
			preferred_asset_type,
			range_value,
			interval
		])
		yahoo_api.fetch_history_as(yahoo_symbol, preferred_asset_type, range_value, interval)


func convert_amount(amount: float, source_currency: String, target_currency: String) -> OperationResult:
	var service := CurrencyConversionService.new()
	return service.convert_amount(amount, source_currency, target_currency, cached_assets, CACHE_DURATION_SECONDS)


func convert_money(money: MoneyData, target_currency: String) -> OperationResult:
	var service := CurrencyConversionService.new()
	return service.convert_money(money, target_currency, cached_assets, CACHE_DURATION_SECONDS)


func get_cached_assets_snapshot() -> Dictionary:
	return cached_assets.duplicate(true)


func _check_cache(cache_key: String, required_source_prefix: String = "") -> bool:
	if not cached_assets.has(cache_key):
		return false

	var asset_raw: Variant = cached_assets[cache_key]
	if not (asset_raw is AssetData):
		return false

	var asset: AssetData = asset_raw as AssetData
	if asset == null:
		return false

	if not _cache_source_matches(asset, required_source_prefix):
		return false

	var cache_age_seconds: float = Time.get_unix_time_from_system() - asset.last_updated
	if cache_age_seconds >= CACHE_DURATION_SECONDS:
		return false

	print("[Cache] Fresh data for: ", cache_key, " | age=", int(cache_age_seconds), "s")
	portfolio_updated.emit(asset)
	return true


func _check_history_cache(cache_key: String, required_source_prefix: String, min_points: int = 2) -> bool:
	if not cached_assets.has(cache_key):
		return false

	var asset_raw: Variant = cached_assets[cache_key]
	if not (asset_raw is AssetData):
		return false

	var asset: AssetData = asset_raw as AssetData
	if asset == null:
		return false

	if _history_point_count(asset, required_source_prefix) < min_points:
		return false

	var cache_age_seconds: float = Time.get_unix_time_from_system() - asset.history_last_updated
	if cache_age_seconds < 0.0 or cache_age_seconds >= HISTORY_CACHE_DURATION_SECONDS:
		return false

	print("[Cache] Fresh history for: ", cache_key, " | age=", int(cache_age_seconds), "s")
	asset_history_updated.emit(asset)
	return true


func _cache_source_matches(asset: AssetData, required_source_prefix: String) -> bool:
	if required_source_prefix.is_empty():
		return true

	var latest_price := asset.get_latest_price_point()
	if latest_price.is_empty() or not latest_price.has("source"):
		return false

	var source: String = str(latest_price["source"])
	if source.contains(":history") and not required_source_prefix.contains(":history"):
		return false

	return source.begins_with(required_source_prefix)


func _history_point_count(asset: AssetData, required_source_prefix: String) -> int:
	var count: int = 0

	for price_point in asset.price_history:
		var source: String = str(price_point.get("source", ""))
		if source.begins_with(required_source_prefix):
			count += 1

	return count


func _on_asset_fetched(asset: AssetData) -> void:
	var stored_asset: AssetData = _store_asset_in_cache(asset)
	SaveManager.save_exchange_cache(cached_assets)
	portfolio_updated.emit(stored_asset)


func _on_asset_history_fetched(asset: AssetData) -> void:
	var stored_asset: AssetData = _store_asset_in_cache(asset)
	SaveManager.save_exchange_cache(cached_assets)
	asset_history_updated.emit(stored_asset)


func _on_asset_fetch_failed(asset_id: String, error_message: String) -> void:
	print("[API Error] ", asset_id, ": ", error_message)
	asset_fetch_failed.emit(asset_id, error_message)


func _on_asset_history_fetch_failed(asset_id: String, error_message: String) -> void:
	print("[API Error] ", asset_id, " history: ", error_message)
	asset_history_fetch_failed.emit(asset_id, error_message)


func _store_asset_in_cache(asset: AssetData) -> AssetData:
	var cache_key: String = _cache_key(asset.id)
	var stored_asset: AssetData = asset

	if cached_assets.has(cache_key):
		var existing_raw: Variant = cached_assets[cache_key]
		if existing_raw is AssetData:
			var existing_asset: AssetData = existing_raw as AssetData
			if existing_asset != null:
				existing_asset.id = asset.id
				existing_asset.symbol = asset.symbol
				existing_asset.name = asset.name
				existing_asset.asset_type = asset.asset_type
				existing_asset.quote_currency = asset.quote_currency
				existing_asset.merge_price_history_from(asset)
				stored_asset = existing_asset

	cached_assets[cache_key] = stored_asset
	return stored_asset


func _on_base_currency_changed(_new_currency: String) -> void:
	print("[PortfolioManager] Base currency changed. Clearing exchange cache.")
	cached_assets.clear()
	SaveManager.save_exchange_cache(cached_assets)


func _cache_key(asset_id: String) -> String:
	return asset_id.strip_edges().to_lower()


func _print_symbol_resolution(resolved_symbol: Dictionary) -> void:
	var input_symbol := str(resolved_symbol.get("input", ""))
	var provider_symbol := str(resolved_symbol.get("symbol", ""))
	if input_symbol.to_upper() != provider_symbol:
		print("[Symbol] Yahoo Finance symbol normalized: ", input_symbol.to_upper(), " -> ", provider_symbol)

	var warnings_raw: Variant = resolved_symbol.get("warnings", PackedStringArray())
	if warnings_raw is PackedStringArray:
		var warnings: PackedStringArray = warnings_raw
		for warning in warnings:
			print("[Symbol] ", warning)
