extends DataProvider
class_name CoinGeckoProvider


func fetch_price(asset_id: String) -> void:
	var normalized_id := asset_id.strip_edges().to_lower()
	var quote_currency := SettingsManager.get_base_currency().to_lower()
	var url := "https://api.coingecko.com/api/v3/simple/price?ids=%s&vs_currencies=%s" % [
		normalized_id.uri_encode(),
		quote_currency.uri_encode()
	]

	var http_request := HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed.bind(http_request, normalized_id, quote_currency.to_upper()))

	var error := http_request.request(url)
	if error != OK:
		fetch_failed.emit(normalized_id, "CoinGecko request initialization failed: %s" % error_string(error))
		http_request.queue_free()


func fetch_history(asset_id: String, range_value: Variant = 365, _interval: String = "1d") -> void:
	var normalized_id: String = asset_id.strip_edges().to_lower()
	if normalized_id.is_empty():
		fetch_history_failed.emit(asset_id, "CoinGecko asset id is empty.")
		return

	var days: int = int(range_value)
	if days < 1:
		days = 1

	var quote_currency: String = SettingsManager.get_base_currency().to_lower()
	var url: String = "https://api.coingecko.com/api/v3/coins/%s/market_chart?vs_currency=%s&days=%d&interval=daily" % [
		normalized_id.uri_encode(),
		quote_currency.uri_encode(),
		days
	]

	var http_request := HTTPRequest.new()
	http_request.timeout = 30.0
	add_child(http_request)
	http_request.request_completed.connect(_on_history_request_completed.bind(http_request, normalized_id, quote_currency.to_upper()))

	var headers := PackedStringArray([
		"Accept: application/json"
	])
	var error := http_request.request(url, headers)
	if error != OK:
		fetch_history_failed.emit(normalized_id, "CoinGecko history request initialization failed: %s" % error_string(error))
		http_request.queue_free()


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http_request: HTTPRequest,
	asset_id: String,
	quote_currency: String
) -> void:
	http_request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		fetch_failed.emit(asset_id, "CoinGecko network error. Result: %s" % result)
		return

	if response_code == 429:
		fetch_failed.emit(asset_id, "CoinGecko rate limit exceeded.")
		return

	if response_code != 200:
		fetch_failed.emit(asset_id, "CoinGecko HTTP error: %s" % response_code)
		return

	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		fetch_failed.emit(asset_id, "CoinGecko JSON parse error.")
		return

	var data_raw: Variant = json.data
	if not (data_raw is Dictionary):
		fetch_failed.emit(asset_id, "CoinGecko response root is invalid.")
		return

	var data: Dictionary = data_raw
	if not data.has(asset_id):
		fetch_failed.emit(asset_id, "CoinGecko response does not contain requested asset.")
		return

	var price_data_raw: Variant = data[asset_id]
	var quote_key := quote_currency.to_lower()
	if not (price_data_raw is Dictionary):
		fetch_failed.emit(asset_id, "CoinGecko response price data is invalid.")
		return

	var price_data: Dictionary = price_data_raw
	if not price_data.has(quote_key):
		fetch_failed.emit(asset_id, "CoinGecko response does not contain quote currency: %s" % quote_currency)
		return

	var asset := AssetData.new()
	asset.id = asset_id
	asset.symbol = asset_id.to_upper()
	asset.name = asset.symbol
	asset.asset_type = AssetData.TYPE_CRYPTO
	asset.quote_currency = quote_currency
	asset.add_price_point(_today_string(), float(price_data[quote_key]), quote_currency, "coingecko")

	fetch_successful.emit(asset)


func _on_history_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http_request: HTTPRequest,
	asset_id: String,
	quote_currency: String
) -> void:
	http_request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		fetch_history_failed.emit(asset_id, "CoinGecko history network error. Result: %s" % result)
		return

	if response_code == 429:
		fetch_history_failed.emit(asset_id, "CoinGecko history rate limit exceeded.")
		return

	if response_code != 200:
		fetch_history_failed.emit(asset_id, "CoinGecko history HTTP error: %s" % response_code)
		return

	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		fetch_history_failed.emit(asset_id, "CoinGecko history JSON parse error.")
		return

	var data_raw: Variant = json.data
	if not (data_raw is Dictionary):
		fetch_history_failed.emit(asset_id, "CoinGecko history response root is invalid.")
		return

	var data: Dictionary = data_raw
	var prices_raw: Variant = data.get("prices", [])
	if not (prices_raw is Array):
		fetch_history_failed.emit(asset_id, "CoinGecko history response does not contain prices.")
		return

	var prices: Array = []
	prices.assign(prices_raw)

	var asset := AssetData.new()
	asset.id = asset_id
	asset.symbol = asset_id.to_upper()
	asset.name = asset.symbol
	asset.asset_type = AssetData.TYPE_CRYPTO
	asset.quote_currency = quote_currency

	for item in prices:
		if not (item is Array):
			continue

		var point: Array = []
		point.assign(item)
		if point.size() < 2:
			continue

		var close_price: float = float(point[1])
		if close_price < 0.0:
			continue

		asset.add_price_point(
			_date_string_from_unix_milliseconds(float(point[0])),
			close_price,
			quote_currency,
			"coingecko:history"
		)

	if asset.price_history.is_empty():
		fetch_history_failed.emit(asset_id, "CoinGecko history response contains no valid price points.")
		return

	fetch_history_successful.emit(asset)


func _today_string() -> String:
	var date_parts := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [
		int(date_parts["year"]),
		int(date_parts["month"]),
		int(date_parts["day"])
	]


func _date_string_from_unix_milliseconds(unix_milliseconds: float) -> String:
	var unix_seconds: int = int(unix_milliseconds / 1000.0)
	var date_parts := Time.get_datetime_dict_from_unix_time(unix_seconds)
	return "%04d-%02d-%02d" % [
		int(date_parts["year"]),
		int(date_parts["month"]),
		int(date_parts["day"])
	]
