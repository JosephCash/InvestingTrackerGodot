extends DataProvider
class_name YahooFinanceProvider


func fetch_price(asset_id: String) -> void:
	fetch_price_as(asset_id, AssetData.TYPE_OTHER)


func fetch_price_as(asset_id: String, preferred_asset_type: String) -> void:
	var resolved_symbol := TickerResolver.resolve_for_yahoo(asset_id)
	var symbol := str(resolved_symbol["symbol"])
	if symbol.is_empty():
		fetch_failed.emit(asset_id, "Yahoo Finance symbol is empty.")
		return

	var url := "https://query1.finance.yahoo.com/v8/finance/chart/%s?range=5d&interval=1d" % symbol.uri_encode()
	var headers := PackedStringArray([
		"User-Agent: Mozilla/5.0",
		"Accept: application/json"
	])

	var http_request := HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed.bind(http_request, symbol, preferred_asset_type))

	var error := http_request.request(url, headers)
	if error != OK:
		fetch_failed.emit(symbol, "Yahoo Finance request initialization failed: %s" % error_string(error))
		http_request.queue_free()


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http_request: HTTPRequest,
	symbol: String,
	preferred_asset_type: String
) -> void:
	http_request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		fetch_failed.emit(symbol, "Yahoo Finance network error. Result: %s" % result)
		return

	if response_code == 429:
		fetch_failed.emit(symbol, "Yahoo Finance rate limit exceeded.")
		return

	if response_code == 404:
		fetch_failed.emit(symbol, "Yahoo Finance symbol not found.")
		return

	if response_code != 200:
		fetch_failed.emit(symbol, "Yahoo Finance HTTP error: %s" % response_code)
		return

	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		fetch_failed.emit(symbol, "Yahoo Finance JSON parse error.")
		return

	var data = json.data
	if not (data is Dictionary):
		fetch_failed.emit(symbol, "Yahoo Finance response root is invalid.")
		return

	var chart = data.get("chart", {})
	if not (chart is Dictionary):
		fetch_failed.emit(symbol, "Yahoo Finance response does not contain chart data.")
		return

	var chart_error = chart.get("error", null)
	if chart_error != null:
		fetch_failed.emit(symbol, "Yahoo Finance returned chart error: %s" % str(chart_error))
		return

	var results = chart.get("result", [])
	if not (results is Array) or results.is_empty():
		fetch_failed.emit(symbol, "Yahoo Finance response does not contain chart result.")
		return

	var result_data = results[0]
	if not (result_data is Dictionary):
		fetch_failed.emit(symbol, "Yahoo Finance chart result is invalid.")
		return

	var meta = result_data.get("meta", {})
	if not (meta is Dictionary):
		fetch_failed.emit(symbol, "Yahoo Finance chart metadata is invalid.")
		return

	var price := _extract_latest_price(result_data, meta)
	if price < 0.0:
		fetch_failed.emit(symbol, "Yahoo Finance response does not contain a valid price.")
		return

	var quote_currency := str(meta.get("currency", "USD")).strip_edges().to_upper()
	if quote_currency.is_empty():
		quote_currency = "USD"

	var asset := AssetData.new()
	asset.id = symbol
	asset.symbol = str(meta.get("symbol", symbol)).strip_edges().to_upper()
	asset.name = asset.symbol
	asset.asset_type = _resolve_asset_type(meta, preferred_asset_type)
	asset.quote_currency = quote_currency
	asset.add_price_point(_date_from_meta(meta), price, quote_currency, "yahoo_finance")

	fetch_successful.emit(asset)


func _extract_latest_price(result_data: Dictionary, meta: Dictionary) -> float:
	if meta.has("regularMarketPrice") and meta["regularMarketPrice"] != null:
		return float(meta["regularMarketPrice"])

	var indicators = result_data.get("indicators", {})
	if not (indicators is Dictionary):
		return -1.0

	var quote_list = indicators.get("quote", [])
	if not (quote_list is Array) or quote_list.is_empty():
		return -1.0

	var first_quote = quote_list[0]
	if not (first_quote is Dictionary):
		return -1.0

	var close_values = first_quote.get("close", [])
	if not (close_values is Array) or close_values.is_empty():
		return -1.0

	var index: int = close_values.size() - 1
	while index >= 0:
		var close_value = close_values[index]
		if close_value != null:
			return float(close_value)
		index -= 1

	return -1.0


func _resolve_asset_type(meta: Dictionary, preferred_asset_type: String) -> String:
	var instrument_type := str(meta.get("instrumentType", "")).strip_edges().to_lower()

	if instrument_type == "etf":
		return AssetData.TYPE_ETF
	if instrument_type == "equity":
		return AssetData.TYPE_STOCK
	if not preferred_asset_type.strip_edges().is_empty() and preferred_asset_type != AssetData.TYPE_OTHER:
		return preferred_asset_type

	return AssetData.TYPE_OTHER


func _date_from_meta(meta: Dictionary) -> String:
	if meta.has("regularMarketTime") and meta["regularMarketTime"] != null:
		return _date_string_from_unix_time(float(meta["regularMarketTime"]))

	return _date_string_from_unix_time(Time.get_unix_time_from_system())


func _date_string_from_unix_time(unix_time: float) -> String:
	var date_parts := Time.get_datetime_dict_from_unix_time(int(unix_time))
	return "%04d-%02d-%02d" % [
		int(date_parts["year"]),
		int(date_parts["month"]),
		int(date_parts["day"])
	]
