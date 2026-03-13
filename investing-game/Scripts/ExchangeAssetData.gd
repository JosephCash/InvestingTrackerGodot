extends RefCounted
class_name ExchangeAssetData

var id: String       
var symbol: String   
var price_usd: float 
var last_updated: float 

# DODALIŚMY '_time: float = 0.0'. Jeśli nikt nie poda czasu, będzie to 0.0
func _init(_id: String, _symbol: String, _price: float, _time: float = 0.0):
	id = _id
	symbol = _symbol
	price_usd = _price
	
	# Jeśli czas to 0.0 (czyli Kucharz właśnie to pobrał z API), dajemy obecny czas
	if _time == 0.0:
		last_updated = Time.get_unix_time_from_system()
	else:
		# Jeśli podaliśmy konkretny czas (bo np. wczytujemy z dysku), użyj tego czasu!
		last_updated = _time
