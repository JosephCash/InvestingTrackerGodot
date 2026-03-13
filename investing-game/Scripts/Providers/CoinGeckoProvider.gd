extends DataProvider
class_name CoinGeckoProvider

const BASE_URL = "https://api.coingecko.com/api/v3/simple/price?ids=%s&vs_currencies=usd"

func fetch_price(asset_id: String) -> void:
	var url = BASE_URL % asset_id
	
	# Tworzymy jednorazowy węzeł do pobrania danych
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	# Podpinamy sygnał i używamy .bind(), aby przekazać ten konkretny węzeł do funkcji odbiorczej
	http_request.request_completed.connect(_on_request_completed.bind(http_request))
	
	var error = http_request.request(url)
	if error != OK:
		fetch_failed.emit("Błąd inicjalizacji zapytania dla: " + asset_id)
		http_request.queue_free() # Usuwamy węzeł w razie błędu

# Zauważ dodany na końcu argument 'http_request', który przyszedł dzięki .bind()
func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest) -> void:
	
	# Od razu usuwamy zużyty węzeł, żeby nie zaśmiecał pamięci!
	http_request.queue_free()
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		fetch_failed.emit("Błąd pobierania z API. Kod: " + str(response_code))
		return
		
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result == OK:
		var data = json.data
		if data.is_empty():
			fetch_failed.emit("Brak danych.")
			return
			
		var first_key = data.keys()[0] 
		var price = data[first_key]["usd"]
		
		var new_asset = ExchangeAssetData.new(first_key, first_key.to_upper(), price)
		fetch_successful.emit(new_asset)
	else:
		fetch_failed.emit("Błąd parsowania JSON")
