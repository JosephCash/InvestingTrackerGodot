extends Resource
class_name PortfolioDepositData

const SCHEMA_VERSION := 1

@export var id: String = ""
@export var date: String = ""
@export var money: MoneyData
@export var note: String = ""


static func create(date_value: String, amount: float, currency: String, note_value: String = "") -> PortfolioDepositData:
	var deposit := PortfolioDepositData.new()
	deposit.id = PortfolioDepositData.generate_id("deposit")
	deposit.date = date_value.strip_edges()
	deposit.money = MoneyData.create(amount, currency)
	deposit.note = note_value.strip_edges()
	return deposit


func validate() -> PackedStringArray:
	var errors := PackedStringArray()

	if id.strip_edges().is_empty():
		errors.append("Deposit id is empty.")

	if date.strip_edges().is_empty():
		errors.append("Deposit date is empty.")

	if money == null:
		errors.append("Deposit money is null.")
	else:
		errors.append_array(money.validate(false))

	return errors


func to_dict() -> Dictionary:
	var amount := 0.0
	var currency := ""
	if money != null:
		amount = money.amount
		currency = money.currency

	return {
		"schema_version": SCHEMA_VERSION,
		"id": id,
		"date": date.strip_edges(),
		"amount": amount,
		"currency": MoneyData.normalize_currency(currency),
		"note": note.strip_edges()
	}


static func from_dict(data: Dictionary) -> PortfolioDepositData:
	var deposit := PortfolioDepositData.new()
	deposit.id = str(data.get("id", ""))
	if deposit.id.is_empty():
		deposit.id = PortfolioDepositData.generate_id("deposit")

	deposit.date = str(data.get("date", "")).strip_edges()

	if data.has("money") and data["money"] is Dictionary:
		deposit.money = MoneyData.from_dict(data["money"])
	else:
		deposit.money = MoneyData.create(float(data.get("amount", 0.0)), str(data.get("currency", "PLN")))

	deposit.note = str(data.get("note", "")).strip_edges()
	return deposit


static func generate_id(prefix: String) -> String:
	return "%s_%d_%d" % [
		prefix.strip_edges().to_lower(),
		int(Time.get_unix_time_from_system() * 1000.0),
		randi() % 100000
	]
