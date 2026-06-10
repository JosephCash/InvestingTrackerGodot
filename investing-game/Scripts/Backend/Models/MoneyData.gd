extends Resource
class_name MoneyData

const SCHEMA_VERSION := 1

@export var amount: float = 0.0
@export var currency: String = "PLN"


static func create(value: float, currency_code: String) -> MoneyData:
	var money := MoneyData.new()
	money.amount = value
	money.currency = MoneyData.normalize_currency(currency_code)
	return money


func validate(allow_zero: bool = true) -> PackedStringArray:
	var errors := PackedStringArray()

	if allow_zero:
		if amount < 0.0:
			errors.append("Money amount cannot be negative.")
	else:
		if amount <= 0.0:
			errors.append("Money amount must be greater than zero.")

	if normalize_currency(currency).is_empty():
		errors.append("Money currency is empty.")

	return errors


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"amount": amount,
		"currency": normalize_currency(currency)
	}


static func from_dict(data: Dictionary) -> MoneyData:
	var money := MoneyData.new()
	money.amount = float(data.get("amount", 0.0))
	money.currency = MoneyData.normalize_currency(str(data.get("currency", "PLN")))
	return money


static func normalize_currency(currency_code: String) -> String:
	return currency_code.strip_edges().to_upper()
