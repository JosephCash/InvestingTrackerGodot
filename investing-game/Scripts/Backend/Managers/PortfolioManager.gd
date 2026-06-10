extends Node

signal portfolio_updated(asset: AssetData)
signal asset_fetch_failed(asset_id: String, error_message: String)

const CACHE_DURATION_SECONDS: float = 15.0 * 60.0

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

	fiat_api = NbpProvider.new()
	add_child(fiat_api)
	fiat_api.fetch_successful.connect(_on_asset_fetched)
	fiat_api.fetch_failed.connect(_on_asset_fetch_failed)

	yahoo_api = YahooFinanceProvider.new()
	add_child(yahoo_api)
	yahoo_api.fetch_successful.connect(_on_asset_fetched)
	yahoo_api.fetch_failed.connect(_on_asset_fetch_failed)


func request_crypto_price(crypto_id: String) -> void:
	var cache_key := _cache_key(crypto_id)
	if not _check_cache(cache_key, "coingecko"):
		print("[API] Fetching crypto: ", crypto_id)
		crypto_api.fetch_price(crypto_id)


func request_fiat_price(fiat_id: String) -> void:
	var cache_key := _cache_key(fiat_id)
	if not _check_cache(cache_key, "nbp"):
		print("[API] Fetching fiat: ", fiat_id)
		fiat_api.fetch_price(fiat_id)


func request_stock_price(symbol: String) -> void:
	var resolved_symbol := TickerResolver.resolve_for_yahoo(symbol)
	var yahoo_symbol := str(resolved_symbol["symbol"])
	var cache_key := _cache_key(yahoo_symbol)
	if not _check_cache(cache_key, "yahoo_finance"):
		_print_symbol_resolution(resolved_symbol)
		print("[API] Fetching stock: ", yahoo_symbol)
		yahoo_api.fetch_price_as(yahoo_symbol, AssetData.TYPE_STOCK)


func request_etf_price(symbol: String) -> void:
	var resolved_symbol := TickerResolver.resolve_for_yahoo(symbol)
	var yahoo_symbol := str(resolved_symbol["symbol"])
	var cache_key := _cache_key(yahoo_symbol)
	if not _check_cache(cache_key, "yahoo_finance"):
		_print_symbol_resolution(resolved_symbol)
		print("[API] Fetching ETF: ", yahoo_symbol)
		yahoo_api.fetch_price_as(yahoo_symbol, AssetData.TYPE_ETF)


func _check_cache(cache_key: String, required_source_prefix: String = "") -> bool:
	if not cached_assets.has(cache_key):
		return false

	var asset = cached_assets[cache_key]
	if not (asset is AssetData):
		return false

	if not _cache_source_matches(asset, required_source_prefix):
		return false

	var cache_age_seconds: float = Time.get_unix_time_from_system() - asset.last_updated
	if cache_age_seconds >= CACHE_DURATION_SECONDS:
		return false

	print("[Cache] Fresh data for: ", cache_key, " | age=", int(cache_age_seconds), "s")
	portfolio_updated.emit(asset)
	return true


func _cache_source_matches(asset: AssetData, required_source_prefix: String) -> bool:
	if required_source_prefix.is_empty():
		return true

	var latest_price := asset.get_latest_price_point()
	if latest_price.is_empty() or not latest_price.has("source"):
		return false

	return str(latest_price["source"]).begins_with(required_source_prefix)


func _on_asset_fetched(asset: AssetData) -> void:
	var cache_key := _cache_key(asset.id)
	cached_assets[cache_key] = asset
	SaveManager.save_exchange_cache(cached_assets)
	portfolio_updated.emit(asset)


func _on_asset_fetch_failed(asset_id: String, error_message: String) -> void:
	print("[API Error] ", asset_id, ": ", error_message)
	asset_fetch_failed.emit(asset_id, error_message)


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

	var warnings = resolved_symbol.get("warnings", PackedStringArray())
	if warnings is PackedStringArray:
		for warning in warnings:
			print("[Symbol] ", warning)
