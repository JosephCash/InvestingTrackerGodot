extends DataProvider
class_name FrankfurterProvider

# Link prosi o przeliczenie 1 jednostki danej waluty (np. EUR) na USD
const BASE_URL = "https://api.frankfurter.app/latest?from=%s&to=USD"

func fetch_price(asset_id: String) -> void:
	# Frankfurter oczekuje symboli wielkimi literami (np. EUR, PLN)
	var symbol = asset_id.to_upper()
	var url = BASE_URL % symbol
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed.bind(http_request, asset_id))
	
	var error = http_request.request(url)
	if error != OK:
		fetch_failed.emit("Błąd sieci Frankfurter dla: " + asset_id)
		http_request.queue_free()

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest, original_id: String) -> void:
	http_request.queue_free()
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		fetch_failed.emit("Błąd Frankfurter API. Kod: " + str(response_code))
		return
		
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result == OK:
		var data = json.data
		# Frankfurter zwraca: {"amount":1.0, "base":"EUR", "date":"...", "rates":{"USD":1.08}}
		if data.has("rates") and data["rates"].has("USD"):
			var price_in_usd = data["rates"]["USD"]
			
			# Tworzymy nasz standardowy talerz danych
			var new_asset = ExchangeAssetData.new(original_id, original_id.to_upper(), price_in_usd)
			fetch_successful.emit(new_asset)
		else:
			fetch_failed.emit("Nie znaleziono kursu dla: " + original_id)
