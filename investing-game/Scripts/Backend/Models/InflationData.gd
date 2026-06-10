extends Resource
class_name InflationData

const SCHEMA_VERSION := 1
const PERIOD_ANNUAL := "annual"
const PERIOD_MONTHLY := "monthly"

@export var id: String = "poland_cpi_annual"
@export var name: String = "Poland CPI annual"
@export var country_code: String = "PL"
@export var period: String = PERIOD_ANNUAL
@export var year: int = 0
@export var month: int = 0
@export var index_value: float = 0.0
@export var inflation_rate: float = 0.0
@export var month_over_month_index: float = 0.0
@export var month_over_month_rate: float = 0.0
@export var year_over_year_index: float = 0.0
@export var year_over_year_rate: float = 0.0
@export var source: String = "gus_bdl"
@export var source_variable_id: String = ""
@export var last_updated: float = 0.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var normalized_period := period.strip_edges().to_lower()

	if id.strip_edges().is_empty():
		errors.append("Inflation id is empty.")

	if country_code.strip_edges().is_empty():
		errors.append("Country code is empty.")

	if [PERIOD_ANNUAL, PERIOD_MONTHLY].has(normalized_period) == false:
		errors.append("Inflation period is unsupported: %s" % period)

	if year <= 0:
		errors.append("Inflation year is invalid.")

	if normalized_period == PERIOD_MONTHLY and (month < 1 or month > 12):
		errors.append("Inflation month is invalid.")

	if index_value <= 0.0:
		errors.append("Inflation index value is invalid.")

	if normalized_period == PERIOD_MONTHLY and month_over_month_index <= 0.0 and year_over_year_index <= 0.0:
		errors.append("Monthly inflation does not contain any CPI index.")

	return errors


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"id": id,
		"name": name,
		"country_code": country_code.strip_edges().to_upper(),
		"period": period.strip_edges().to_lower(),
		"year": year,
		"month": month,
		"index_value": index_value,
		"inflation_rate": inflation_rate,
		"month_over_month_index": month_over_month_index,
		"month_over_month_rate": month_over_month_rate,
		"year_over_year_index": year_over_year_index,
		"year_over_year_rate": year_over_year_rate,
		"source": source,
		"source_variable_id": source_variable_id,
		"last_updated": last_updated
	}


func get_period_label() -> String:
	if period.strip_edges().to_lower() == PERIOD_MONTHLY:
		return "%04d-%02d" % [year, month]

	return str(year)


static func from_dict(data: Dictionary) -> InflationData:
	var inflation := InflationData.new()

	inflation.id = str(data.get("id", "poland_cpi_annual"))
	inflation.name = str(data.get("name", "Poland CPI annual"))
	inflation.country_code = str(data.get("country_code", "PL")).strip_edges().to_upper()
	inflation.period = str(data.get("period", "annual")).strip_edges().to_lower()
	inflation.year = int(data.get("year", 0))
	inflation.month = int(data.get("month", 0))
	inflation.index_value = float(data.get("index_value", 0.0))
	inflation.inflation_rate = float(data.get("inflation_rate", inflation.index_value - 100.0))
	inflation.month_over_month_index = float(data.get("month_over_month_index", 0.0))
	inflation.month_over_month_rate = float(data.get("month_over_month_rate", _rate_from_index(inflation.month_over_month_index)))
	inflation.year_over_year_index = float(data.get("year_over_year_index", 0.0))
	inflation.year_over_year_rate = float(data.get("year_over_year_rate", _rate_from_index(inflation.year_over_year_index)))
	inflation.source = str(data.get("source", "gus_bdl"))
	inflation.source_variable_id = str(data.get("source_variable_id", ""))
	inflation.last_updated = float(data.get("last_updated", 0.0))

	return inflation


static func _rate_from_index(value: float) -> float:
	if value <= 0.0:
		return 0.0

	return value - 100.0
