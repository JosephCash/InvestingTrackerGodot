extends RefCounted
class_name BondValuationService


func estimate_value(
	bond: BondLotData,
	valuation_date: String,
	latest_monthly_inflation: InflationData = null
) -> OperationResult:
	if bond == null:
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Cannot value null bond lot.")

	var validation_errors := bond.validate()
	if not validation_errors.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "Bond lot is invalid: %s" % str(validation_errors))

	var date_result := _elapsed_years(bond.purchase_date, valuation_date)
	if not date_result.is_ok():
		return date_result

	var elapsed_years: float = float(date_result.data)
	var rate_result := _resolve_annual_rate(bond, elapsed_years, latest_monthly_inflation)
	if not rate_result.is_ok():
		return rate_result

	var rate_data_raw: Variant = rate_result.data
	if not (rate_data_raw is Dictionary):
		return OperationResult.fail(ERR_INVALID_DATA, "Bond rate result has invalid format.")

	var rate_data: Dictionary = _copy_dictionary(rate_data_raw)
	var annual_rate: float = float(rate_data.get("annual_rate", 0.0))
	var principal: float = bond.get_principal()
	var gross_value: float = principal * pow(1.0 + annual_rate / 100.0, elapsed_years)
	var gross_interest: float = gross_value - principal
	if gross_interest < 0.0:
		gross_interest = 0.0

	var tax: float = gross_interest * bond.tax_rate / 100.0
	var net_value: float = gross_value - tax

	return OperationResult.ok({
		"bond_id": bond.id,
		"code": bond.code,
		"interest_type": bond.interest_type,
		"valuation_date": valuation_date.strip_edges(),
		"currency": MoneyData.normalize_currency(bond.currency),
		"quantity": bond.quantity,
		"principal": principal,
		"purchase_cost": bond.get_purchase_cost(),
		"elapsed_years": elapsed_years,
		"annual_rate_used": annual_rate,
		"gross_value": gross_value,
		"gross_interest": gross_interest,
		"tax": tax,
		"net_value": net_value,
		"rate_source": rate_data.get("rate_source", ""),
		"warnings": rate_data.get("warnings", PackedStringArray())
	}, "Bond valuation estimated.")


func _resolve_annual_rate(
	bond: BondLotData,
	elapsed_years: float,
	latest_monthly_inflation: InflationData
) -> OperationResult:
	var warnings := PackedStringArray()
	var normalized_type := bond.interest_type.strip_edges().to_lower()

	if normalized_type == BondLotData.TYPE_FIXED_RATE:
		return OperationResult.ok({
			"annual_rate": bond.fixed_annual_rate,
			"rate_source": "fixed_rate",
			"warnings": warnings
		})

	if normalized_type == BondLotData.TYPE_INFLATION_INDEXED:
		if elapsed_years <= 1.0:
			return OperationResult.ok({
				"annual_rate": bond.first_year_rate,
				"rate_source": "first_year_rate",
				"warnings": warnings
			})

		if latest_monthly_inflation == null:
			return OperationResult.fail(ERR_INVALID_DATA, "Inflation-indexed bond valuation requires monthly CPI data.")

		if latest_monthly_inflation.period.strip_edges().to_lower() != InflationData.PERIOD_MONTHLY:
			return OperationResult.fail(ERR_INVALID_DATA, "Inflation data is not monthly.")

		if latest_monthly_inflation.year_over_year_index <= 0.0:
			return OperationResult.fail(ERR_INVALID_DATA, "Monthly CPI does not contain year-over-year index.")

		warnings.append("Estimated with the latest available CPI period. Exact bond valuation will need issue-specific coupon periods.")
		return OperationResult.ok({
			"annual_rate": latest_monthly_inflation.year_over_year_rate + bond.inflation_margin,
			"rate_source": "gus_dbw:%s+margin" % latest_monthly_inflation.get_period_label(),
			"warnings": warnings
		})

	return OperationResult.fail(ERR_INVALID_DATA, "Unsupported bond interest type: %s" % bond.interest_type)


func _copy_dictionary(value: Variant) -> Dictionary:
	var result: Dictionary = {}

	if value is Dictionary:
		for key in value:
			result[key] = value[key]

	return result


func _elapsed_years(start_date: String, end_date: String) -> OperationResult:
	var start_day_result := _date_to_day_number(start_date)
	if not start_day_result.is_ok():
		return start_day_result

	var end_day_result := _date_to_day_number(end_date)
	if not end_day_result.is_ok():
		return end_day_result

	var start_day: int = int(start_day_result.data)
	var end_day: int = int(end_day_result.data)
	if end_day < start_day:
		return OperationResult.fail(ERR_INVALID_DATA, "Valuation date cannot be earlier than purchase date.")

	return OperationResult.ok(float(end_day - start_day) / 365.0)


func _date_to_day_number(date_value: String) -> OperationResult:
	var parts := date_value.strip_edges().split("-")
	if parts.size() != 3:
		return OperationResult.fail(ERR_INVALID_DATA, "Date must use YYYY-MM-DD format: %s" % date_value)

	var year := int(parts[0])
	var month := int(parts[1])
	var day := int(parts[2])

	if not _is_valid_date_parts(year, month, day):
		return OperationResult.fail(ERR_INVALID_DATA, "Date is invalid: %s" % date_value)

	var adjusted_year := year
	var adjusted_month := month
	if adjusted_month <= 2:
		adjusted_year -= 1
		adjusted_month += 12

	var era_days := (
		365 * adjusted_year
		+ int(floor(float(adjusted_year) / 4.0))
		- int(floor(float(adjusted_year) / 100.0))
		+ int(floor(float(adjusted_year) / 400.0))
		+ int(floor(float(153 * (adjusted_month - 3) + 2) / 5.0))
		+ day
		- 1
	)

	return OperationResult.ok(era_days)


func _is_valid_date_parts(year: int, month: int, day: int) -> bool:
	if year < 1900 or month < 1 or month > 12 or day < 1:
		return false

	return day <= _days_in_month(year, month)


func _days_in_month(year: int, month: int) -> int:
	match month:
		1, 3, 5, 7, 8, 10, 12:
			return 31
		4, 6, 9, 11:
			return 30
		2:
			if _is_leap_year(year):
				return 29
			return 28

	return 0


func _is_leap_year(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
