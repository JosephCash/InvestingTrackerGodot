extends RefCounted
class_name ExchangeAssetData

var id: String       
var symbol: String   
var price: float  # Zmieniono z price_usd na price
var last_updated: float 

func _init(_id: String, _symbol: String, _price: float, _time: float = 0.0):
	id = _id
	symbol = _symbol
	price = _price # Zmieniono przypisanie
	
	if _time == 0.0:
		last_updated = Time.get_unix_time_from_system()
	else:
		last_updated = _time
