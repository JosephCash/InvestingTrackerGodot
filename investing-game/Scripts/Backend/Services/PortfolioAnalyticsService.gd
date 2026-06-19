extends RefCounted
class_name PortfolioAnalyticsService


func calculate_portfolio_statistics(
	portfolio: PortfolioData,
	monthly_inflation: Array[InflationData] = []
) -> OperationResult:
	if portfolio == null:
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Cannot calculate statistics for null portfolio.")

	var validation_errors: PackedStringArray = portfolio.validate()
	if not validation_errors.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "Portfolio is invalid: %s" % str(validation_errors))

	var date_validation_result: OperationResult = _validate_portfolio_dates(portfolio)
	if not date_validation_result.is_ok():
		return date_validation_result

	var target_currency: String = MoneyData.normalize_currency(portfolio.base_currency)
	if target_currency.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "Portfolio base currency is empty.")

	var snapshots: Array[PortfolioSnapshotData] = _copy_snapshot_array(portfolio.value_snapshots)
	if snapshots.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "Portfolio statistics require at least one value snapshot.")

	_sort_snapshots_by_date_ascending(snapshots)
	var latest_snapshot: PortfolioSnapshotData = snapshots[snapshots.size() - 1]
	if latest_snapshot.total_value == null:
		return OperationResult.fail(ERR_INVALID_DATA, "Latest value snapshot has no value.")

	var valuation_date: String = latest_snapshot.date.strip_edges()
	var valuation_currency: String = MoneyData.normalize_currency(latest_snapshot.total_value.currency)
	if valuation_currency != target_currency:
		return OperationResult.fail(
			ERR_INVALID_DATA,
			"Portfolio analytics currently require snapshots in base currency %s, got %s." % [
				target_currency,
				valuation_currency
			]
		)

	var currency_result: OperationResult = _validate_single_currency(portfolio, target_currency)
	if not currency_result.is_ok():
		return currency_result

	var deposits: Array[PortfolioDepositData] = _copy_deposit_array(portfolio.deposits)
	_sort_deposits_by_date_ascending(deposits)

	var first_activity_result: OperationResult = _first_activity_date(deposits, snapshots)
	if not first_activity_result.is_ok():
		return first_activity_result

	var first_activity_date: String = str(first_activity_result.data)
	var months_result: OperationResult = DateUtils.inclusive_months_between(first_activity_date, valuation_date)
	if not months_result.is_ok():
		return months_result

	var investing_months: int = int(months_result.data)
	var deposited: float = _sum_deposits_until(deposits, target_currency, valuation_date)
	var current_value: float = latest_snapshot.total_value.amount
	var nominal_profit: float = current_value - deposited
	var profit_percent: float = 0.0
	if deposited > 0.0:
		profit_percent = nominal_profit / deposited * 100.0

	var average_monthly_deposit: float = 0.0
	if investing_months > 0:
		average_monthly_deposit = deposited / float(investing_months)

	var first_deposit_date: String = _first_deposit_date(deposits, target_currency, valuation_date)
	var cagr: Dictionary = _calculate_simple_cagr(deposited, current_value, first_deposit_date, valuation_date)
	var real_result: Dictionary = _calculate_real_result(
		deposits,
		monthly_inflation,
		target_currency,
		valuation_date,
		current_value,
		deposited
	)
	var capital_history: Dictionary = _build_capital_history(deposits, snapshots, target_currency, valuation_date)

	return OperationResult.ok({
		"portfolio_id": portfolio.id,
		"name": portfolio.name,
		"portfolio_type": portfolio.portfolio_type,
		"currency": target_currency,
		"first_activity_date": first_activity_date,
		"valuation_date": valuation_date,
		"investing_months": investing_months,
		"total_deposited": deposited,
		"current_value": current_value,
		"nominal_profit": nominal_profit,
		"profit_percent": profit_percent,
		"average_monthly_deposit": average_monthly_deposit,
		"cagr": cagr,
		"real_result": real_result,
		"chart_series": {
			"capital_history": capital_history
		}
	}, "Portfolio statistics calculated.")


func _validate_portfolio_dates(portfolio: PortfolioData) -> OperationResult:
	for deposit in portfolio.deposits:
		if deposit == null:
			return OperationResult.fail(ERR_INVALID_DATA, "Deposit is null.")
		if not DateUtils.is_valid_iso_date(deposit.date):
			return OperationResult.fail(ERR_INVALID_DATA, "Deposit date must use YYYY-MM-DD: %s" % deposit.date)

	for snapshot in portfolio.value_snapshots:
		if snapshot == null:
			return OperationResult.fail(ERR_INVALID_DATA, "Value snapshot is null.")
		if not DateUtils.is_valid_iso_date(snapshot.date):
			return OperationResult.fail(ERR_INVALID_DATA, "Snapshot date must use YYYY-MM-DD: %s" % snapshot.date)

	return OperationResult.ok()


func _validate_single_currency(portfolio: PortfolioData, target_currency: String) -> OperationResult:
	for deposit in portfolio.deposits:
		if deposit == null or deposit.money == null:
			continue

		var deposit_currency: String = MoneyData.normalize_currency(deposit.money.currency)
		if deposit_currency != target_currency:
			return OperationResult.fail(
				ERR_INVALID_DATA,
				"Portfolio analytics currently require one currency. Deposit %s is %s, expected %s." % [
					deposit.id,
					deposit_currency,
					target_currency
				]
			)

	for snapshot in portfolio.value_snapshots:
		if snapshot == null or snapshot.total_value == null:
			continue

		var snapshot_currency: String = MoneyData.normalize_currency(snapshot.total_value.currency)
		if snapshot_currency != target_currency:
			return OperationResult.fail(
				ERR_INVALID_DATA,
				"Portfolio analytics currently require one currency. Snapshot %s is %s, expected %s." % [
					snapshot.id,
					snapshot_currency,
					target_currency
				]
			)

	return OperationResult.ok()


func _first_activity_date(
	deposits: Array[PortfolioDepositData],
	snapshots: Array[PortfolioSnapshotData]
) -> OperationResult:
	var first_date: String = ""

	if not deposits.is_empty():
		first_date = deposits[0].date.strip_edges()

	if not snapshots.is_empty():
		var snapshot_date: String = snapshots[0].date.strip_edges()
		if first_date.is_empty():
			first_date = snapshot_date
		else:
			var compare_result: OperationResult = DateUtils.compare_iso_dates(snapshot_date, first_date)
			if not compare_result.is_ok():
				return compare_result
			if int(compare_result.data) < 0:
				first_date = snapshot_date

	if first_date.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "Portfolio has no dated activity.")

	return OperationResult.ok(first_date)


func _first_deposit_date(
	deposits: Array[PortfolioDepositData],
	target_currency: String,
	valuation_date: String
) -> String:
	for deposit in deposits:
		if deposit == null or deposit.money == null:
			continue

		if MoneyData.normalize_currency(deposit.money.currency) != target_currency:
			continue

		if _is_on_or_before(deposit.date, valuation_date):
			return deposit.date.strip_edges()

	return ""


func _sum_deposits_until(
	deposits: Array[PortfolioDepositData],
	target_currency: String,
	valuation_date: String
) -> float:
	var total: float = 0.0

	for deposit in deposits:
		if deposit == null or deposit.money == null:
			continue

		if MoneyData.normalize_currency(deposit.money.currency) != target_currency:
			continue

		if not _is_on_or_before(deposit.date, valuation_date):
			continue

		total += deposit.money.amount

	return total


func _calculate_simple_cagr(
	deposited: float,
	current_value: float,
	first_deposit_date: String,
	valuation_date: String
) -> Dictionary:
	if first_deposit_date.strip_edges().is_empty():
		return {
			"available": false,
			"reason": "No deposit before valuation date."
		}

	if deposited <= 0.0 or current_value <= 0.0:
		return {
			"available": false,
			"reason": "CAGR requires positive deposited capital and current value."
		}

	var elapsed_result: OperationResult = DateUtils.elapsed_years(first_deposit_date, valuation_date)
	if not elapsed_result.is_ok():
		return {
			"available": false,
			"reason": elapsed_result.message
		}

	var elapsed_years: float = float(elapsed_result.data)
	if elapsed_years <= 0.0:
		return {
			"available": false,
			"reason": "CAGR period is too short."
		}

	var ratio: float = current_value / deposited
	var cagr_rate: float = (float(pow(ratio, 1.0 / elapsed_years)) - 1.0) * 100.0

	return {
		"available": true,
		"method": "simple_total_deposits",
		"elapsed_years": elapsed_years,
		"rate": cagr_rate,
		"warning": "This is a simple annualized return from total deposits, not XIRR/time-weighted return."
	}


func _calculate_real_result(
	deposits: Array[PortfolioDepositData],
	monthly_inflation: Array[InflationData],
	target_currency: String,
	valuation_date: String,
	current_value: float,
	deposited: float
) -> Dictionary:
	if monthly_inflation.is_empty():
		return {
			"available": false,
			"reason": "No monthly inflation series supplied."
		}

	var map_result: OperationResult = _build_monthly_inflation_map(monthly_inflation)
	if not map_result.is_ok():
		return {
			"available": false,
			"reason": map_result.message
		}

	var map_data_raw: Variant = map_result.data
	if not (map_data_raw is Dictionary):
		return {
			"available": false,
			"reason": "Monthly inflation map has invalid format."
		}

	var map_data: Dictionary = _copy_dictionary(map_data_raw)
	var period_map_raw: Variant = map_data.get("period_map", {})
	if not (period_map_raw is Dictionary):
		return {
			"available": false,
			"reason": "Monthly inflation period map has invalid format."
		}

	var period_map: Dictionary = _copy_dictionary(period_map_raw)
	var max_period_key: int = int(map_data.get("max_key", 0))
	var valuation_key_result: OperationResult = DateUtils.period_key_from_date(valuation_date)
	if not valuation_key_result.is_ok():
		return {
			"available": false,
			"reason": valuation_key_result.message
		}

	var valuation_key: int = int(valuation_key_result.data)
	var inflation_end_key: int = valuation_key
	var warnings := PackedStringArray()
	if max_period_key < inflation_end_key:
		inflation_end_key = max_period_key
		warnings.append("Inflation data ends before valuation date; real result uses the latest available CPI period.")

	if inflation_end_key <= 0:
		return {
			"available": false,
			"reason": "Monthly inflation series has no valid periods."
		}

	var adjusted_deposited: float = 0.0
	var first_used_key: int = 0

	for deposit in deposits:
		if deposit == null or deposit.money == null:
			continue

		if MoneyData.normalize_currency(deposit.money.currency) != target_currency:
			continue

		if not _is_on_or_before(deposit.date, valuation_date):
			continue

		var deposit_key_result: OperationResult = DateUtils.period_key_from_date(deposit.date)
		if not deposit_key_result.is_ok():
			return {
				"available": false,
				"reason": deposit_key_result.message
			}

		var deposit_key: int = int(deposit_key_result.data)
		if first_used_key == 0 or deposit_key < first_used_key:
			first_used_key = deposit_key

		if deposit_key > inflation_end_key:
			adjusted_deposited += deposit.money.amount
			continue

		var factor_result: OperationResult = _inflation_factor_for_range(period_map, deposit_key, inflation_end_key)
		if not factor_result.is_ok():
			return {
				"available": false,
				"reason": factor_result.message
			}

		var factor: float = float(factor_result.data)
		adjusted_deposited += deposit.money.amount * factor

	if first_used_key == 0:
		return {
			"available": false,
			"reason": "No deposits before valuation date."
		}

	var real_profit: float = current_value - adjusted_deposited
	var cash_opportunity_cost: float = adjusted_deposited - deposited

	return {
		"available": true,
		"method": "monthly_cpi_bucket_adjustment",
		"start_period": DateUtils.period_label_from_key(first_used_key),
		"end_period": DateUtils.period_label_from_key(inflation_end_key),
		"inflation_adjusted_deposited": adjusted_deposited,
		"real_profit": real_profit,
		"cash_opportunity_cost": cash_opportunity_cost,
		"warnings": warnings
	}


func _build_capital_history(
	deposits: Array[PortfolioDepositData],
	snapshots: Array[PortfolioSnapshotData],
	target_currency: String,
	valuation_date: String
) -> Dictionary:
	var deposit_points: Array[Dictionary] = []
	var snapshot_points: Array[Dictionary] = []
	var cumulative_deposits: float = 0.0
	var last_deposit_date: String = ""

	for deposit in deposits:
		if deposit == null or deposit.money == null:
			continue

		if MoneyData.normalize_currency(deposit.money.currency) != target_currency:
			continue

		if not _is_on_or_before(deposit.date, valuation_date):
			continue

		var deposit_date: String = deposit.date.strip_edges()
		cumulative_deposits += deposit.money.amount

		if deposit_date == last_deposit_date and not deposit_points.is_empty():
			var last_deposit_index: int = deposit_points.size() - 1
			deposit_points[last_deposit_index]["value"] = cumulative_deposits
		else:
			deposit_points.append({
				"date": deposit_date,
				"value": cumulative_deposits,
				"currency": target_currency
			})
			last_deposit_date = deposit_date

	var last_snapshot_date: String = ""
	for snapshot in snapshots:
		if snapshot == null or snapshot.total_value == null:
			continue

		if MoneyData.normalize_currency(snapshot.total_value.currency) != target_currency:
			continue

		if not _is_on_or_before(snapshot.date, valuation_date):
			continue

		var snapshot_date: String = snapshot.date.strip_edges()
		if snapshot_date == last_snapshot_date and not snapshot_points.is_empty():
			var last_snapshot_index: int = snapshot_points.size() - 1
			snapshot_points[last_snapshot_index]["value"] = snapshot.total_value.amount
		else:
			snapshot_points.append({
				"date": snapshot_date,
				"value": snapshot.total_value.amount,
				"currency": target_currency
			})
			last_snapshot_date = snapshot_date

	return {
		"deposits": deposit_points,
		"portfolio_value": snapshot_points
	}


func _build_monthly_inflation_map(monthly_inflation: Array[InflationData]) -> OperationResult:
	var period_map: Dictionary = {}
	var min_key: int = 0
	var max_key: int = 0

	for inflation in monthly_inflation:
		if inflation == null:
			return OperationResult.fail(ERR_INVALID_DATA, "Monthly inflation series contains null entry.")

		if inflation.period.strip_edges().to_lower() != InflationData.PERIOD_MONTHLY:
			return OperationResult.fail(ERR_INVALID_DATA, "Inflation entry is not monthly: %s" % inflation.id)

		if inflation.month_over_month_index <= 0.0:
			return OperationResult.fail(ERR_INVALID_DATA, "Monthly CPI index is invalid for: %s" % inflation.get_period_label())

		if not DateUtils.is_valid_date_parts(inflation.year, inflation.month, 1):
			return OperationResult.fail(ERR_INVALID_DATA, "Monthly CPI period is invalid: %s" % inflation.get_period_label())

		var key: int = DateUtils.period_key(inflation.year, inflation.month)
		if period_map.has(key):
			return OperationResult.fail(ERR_INVALID_DATA, "Monthly CPI series contains duplicate period: %s" % inflation.get_period_label())

		period_map[key] = inflation
		if min_key == 0 or key < min_key:
			min_key = key
		if max_key == 0 or key > max_key:
			max_key = key

	return OperationResult.ok({
		"period_map": period_map,
		"min_key": min_key,
		"max_key": max_key
	})


func _inflation_factor_for_range(period_map: Dictionary, start_key: int, end_key: int) -> OperationResult:
	if end_key < start_key:
		return OperationResult.ok(1.0)

	var factor: float = 1.0
	for key in range(start_key, end_key + 1):
		if not period_map.has(key):
			return OperationResult.fail(
				ERR_INVALID_DATA,
				"Monthly CPI series does not cover %s." % DateUtils.period_label_from_key(key)
			)

		var inflation: InflationData = period_map[key] as InflationData
		if inflation == null:
			return OperationResult.fail(ERR_INVALID_DATA, "Monthly CPI map contains invalid entry.")

		factor *= inflation.month_over_month_index / 100.0

	return OperationResult.ok(factor)


func _copy_deposit_array(source: Array[PortfolioDepositData]) -> Array[PortfolioDepositData]:
	var result: Array[PortfolioDepositData] = []
	for deposit in source:
		if deposit != null:
			result.append(deposit)

	return result


func _copy_snapshot_array(source: Array[PortfolioSnapshotData]) -> Array[PortfolioSnapshotData]:
	var result: Array[PortfolioSnapshotData] = []
	for snapshot in source:
		if snapshot != null:
			result.append(snapshot)

	return result


func _sort_deposits_by_date_ascending(items: Array[PortfolioDepositData]) -> void:
	for index in range(items.size()):
		var min_index: int = index

		for compare_index in range(index + 1, items.size()):
			if _date_key(items[compare_index].date) < _date_key(items[min_index].date):
				min_index = compare_index

		if min_index != index:
			var current: PortfolioDepositData = items[index]
			items[index] = items[min_index]
			items[min_index] = current


func _sort_snapshots_by_date_ascending(items: Array[PortfolioSnapshotData]) -> void:
	for index in range(items.size()):
		var min_index: int = index

		for compare_index in range(index + 1, items.size()):
			if _date_key(items[compare_index].date) < _date_key(items[min_index].date):
				min_index = compare_index

		if min_index != index:
			var current: PortfolioSnapshotData = items[index]
			items[index] = items[min_index]
			items[min_index] = current


func _date_key(date_value: String) -> int:
	var result: OperationResult = DateUtils.date_to_day_number(date_value)
	if not result.is_ok():
		return 0

	return int(result.data)


func _is_on_or_before(date_value: String, limit_date: String) -> bool:
	var compare_result: OperationResult = DateUtils.compare_iso_dates(date_value, limit_date)
	if not compare_result.is_ok():
		return false

	return int(compare_result.data) <= 0


func _copy_dictionary(value: Variant) -> Dictionary:
	var result: Dictionary = {}

	if value is Dictionary:
		for key in value:
			result[key] = value[key]

	return result
