extends DataProvider
class_name CoinGeckoProvider


func fetch_price(asset_id: String) -> void:
	var normalized_id := asset_id.strip_edges().to_lower()
	var quote_currency := SettingsManager.base_currency.to_lower()
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

	var data = json.data
	if not (data is Dictionary) or not data.has(asset_id):
		fetch_failed.emit(asset_id, "CoinGecko response does not contain requested asset.")
		return

	var price_data = data[asset_id]
	var quote_key := quote_currency.to_lower()
	if not (price_data is Dictionary) or not price_data.has(quote_key):
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


func _today_string() -> String:
	var date_parts := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [
		int(date_parts["year"]),
		int(date_parts["month"]),
		int(date_parts["day"])
	]
