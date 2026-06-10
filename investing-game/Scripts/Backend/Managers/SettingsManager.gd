extends Node

# Emitowany, gdy waluta bazowa ulegnie zmianie
signal base_currency_changed(new_currency: String)

var base_currency: String = "usd" # Domyślna waluta bazowa (małymi literami)

func _ready():
	load_settings()

func load_settings():
	var settings = SaveManager.load_settings()
	if settings.has("base_currency"):
		base_currency = settings["base_currency"]

func set_base_currency(new_currency: String):
	new_currency = new_currency.to_lower()
	if base_currency != new_currency:
		base_currency = new_currency
		SaveManager.save_settings({"base_currency": base_currency})
		base_currency_changed.emit(base_currency)
