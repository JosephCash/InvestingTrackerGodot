extends Resource
class_name BondLotData

const SCHEMA_VERSION := 1

const TYPE_FIXED_RATE := "fixed_rate"
const TYPE_INFLATION_INDEXED := "inflation_indexed"

@export var id: String = ""
@export var code: String = ""
@export var name: String = ""
@export var interest_type: String = TYPE_FIXED_RATE
@export var purchase_date: String = ""
@export var maturity_date: String = ""
@export var quantity: int = 0
@export var nominal_value: float = 100.0
@export var purchase_price_per_bond: float = 100.0
@export var currency: String = "PLN"
@export var fixed_annual_rate: float = 0.0
@export var first_year_rate: float = 0.0
@export var inflation_margin: float = 0.0
@export var tax_rate: float = 19.0
@export var note: String = ""


static func create_fixed_rate(
	code_value: String,
	purchase_date_value: String,
	maturity_date_value: String,
	quantity_value: int,
	fixed_rate_value: float,
	name_value: String = ""
) -> BondLotData:
	var bond := BondLotData.new()
	bond.id = BondLotData.generate_id("bond")
	bond.code = code_value.strip_edges().to_upper()
	bond.name = name_value.strip_edges()
	bond.interest_type = TYPE_FIXED_RATE
	bond.purchase_date = purchase_date_value.strip_edges()
	bond.maturity_date = maturity_date_value.strip_edges()
	bond.quantity = quantity_value
	bond.fixed_annual_rate = fixed_rate_value
	return bond


static func create_inflation_indexed(
	code_value: String,
	purchase_date_value: String,
	maturity_date_value: String,
	quantity_value: int,
	first_year_rate_value: float,
	inflation_margin_value: float,
	name_value: String = ""
) -> BondLotData:
	var bond := BondLotData.new()
	bond.id = BondLotData.generate_id("bond")
	bond.code = code_value.strip_edges().to_upper()
	bond.name = name_value.strip_edges()
	bond.interest_type = TYPE_INFLATION_INDEXED
	bond.purchase_date = purchase_date_value.strip_edges()
	bond.maturity_date = maturity_date_value.strip_edges()
	bond.quantity = quantity_value
	bond.first_year_rate = first_year_rate_value
	bond.inflation_margin = inflation_margin_value
	return bond


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var normalized_type := interest_type.strip_edges().to_lower()

	if id.strip_edges().is_empty():
		errors.append("Bond lot id is empty.")

	if code.strip_edges().is_empty():
		errors.append("Bond code is empty.")

	if [TYPE_FIXED_RATE, TYPE_INFLATION_INDEXED].has(normalized_type) == false:
		errors.append("Unsupported bond interest type: %s" % interest_type)

	if purchase_date.strip_edges().is_empty():
		errors.append("Bond purchase date is empty.")

	if maturity_date.strip_edges().is_empty():
		errors.append("Bond maturity date is empty.")

	if quantity <= 0:
		errors.append("Bond quantity must be greater than zero.")

	if nominal_value <= 0.0:
		errors.append("Bond nominal value must be greater than zero.")

	if purchase_price_per_bond <= 0.0:
		errors.append("Bond purchase price must be greater than zero.")

	if MoneyData.normalize_currency(currency).is_empty():
		errors.append("Bond currency is empty.")

	if tax_rate < 0.0 or tax_rate > 100.0:
		errors.append("Bond tax rate must be between 0 and 100.")

	if normalized_type == TYPE_FIXED_RATE and fixed_annual_rate < 0.0:
		errors.append("Fixed annual rate cannot be negative.")

	if normalized_type == TYPE_INFLATION_INDEXED:
		if first_year_rate < 0.0:
			errors.append("First year rate cannot be negative.")
		if inflation_margin < 0.0:
			errors.append("Inflation margin cannot be negative.")

	return errors


func get_principal() -> float:
	return float(quantity) * nominal_value


func get_purchase_cost() -> float:
	return float(quantity) * purchase_price_per_bond


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"id": id,
		"code": code.strip_edges().to_upper(),
		"name": name.strip_edges(),
		"interest_type": interest_type.strip_edges().to_lower(),
		"purchase_date": purchase_date.strip_edges(),
		"maturity_date": maturity_date.strip_edges(),
		"quantity": quantity,
		"nominal_value": nominal_value,
		"purchase_price_per_bond": purchase_price_per_bond,
		"currency": MoneyData.normalize_currency(currency),
		"fixed_annual_rate": fixed_annual_rate,
		"first_year_rate": first_year_rate,
		"inflation_margin": inflation_margin,
		"tax_rate": tax_rate,
		"note": note.strip_edges()
	}


static func from_dict(data: Dictionary) -> BondLotData:
	var bond := BondLotData.new()
	bond.id = str(data.get("id", ""))
	if bond.id.is_empty():
		bond.id = BondLotData.generate_id("bond")

	bond.code = str(data.get("code", "")).strip_edges().to_upper()
	bond.name = str(data.get("name", "")).strip_edges()
	bond.interest_type = str(data.get("interest_type", TYPE_FIXED_RATE)).strip_edges().to_lower()
	bond.purchase_date = str(data.get("purchase_date", "")).strip_edges()
	bond.maturity_date = str(data.get("maturity_date", "")).strip_edges()
	bond.quantity = int(data.get("quantity", 0))
	bond.nominal_value = float(data.get("nominal_value", 100.0))
	bond.purchase_price_per_bond = float(data.get("purchase_price_per_bond", 100.0))
	bond.currency = MoneyData.normalize_currency(str(data.get("currency", "PLN")))
	bond.fixed_annual_rate = float(data.get("fixed_annual_rate", 0.0))
	bond.first_year_rate = float(data.get("first_year_rate", 0.0))
	bond.inflation_margin = float(data.get("inflation_margin", 0.0))
	bond.tax_rate = float(data.get("tax_rate", 19.0))
	bond.note = str(data.get("note", "")).strip_edges()
	return bond


static func generate_id(prefix: String) -> String:
	return "%s_%d_%d" % [
		prefix.strip_edges().to_lower(),
		int(Time.get_unix_time_from_system() * 1000.0),
		randi() % 100000
	]
