extends RefCounted
class_name DateUtils


static func parse_iso_date(date_value: String) -> OperationResult:
	var clean_date: String = date_value.strip_edges()
	var parts: PackedStringArray = clean_date.split("-")
	if parts.size() != 3:
		return OperationResult.fail(ERR_INVALID_DATA, "Date must use YYYY-MM-DD format: %s" % date_value)

	var year: int = int(parts[0])
	var month: int = int(parts[1])
	var day: int = int(parts[2])

	if not is_valid_date_parts(year, month, day):
		return OperationResult.fail(ERR_INVALID_DATA, "Date is invalid: %s" % date_value)

	return OperationResult.ok({
		"year": year,
		"month": month,
		"day": day
	})


static func is_valid_iso_date(date_value: String) -> bool:
	return parse_iso_date(date_value).is_ok()


static func date_to_day_number(date_value: String) -> OperationResult:
	var parse_result: OperationResult = parse_iso_date(date_value)
	if not parse_result.is_ok():
		return parse_result

	var date_data_raw: Variant = parse_result.data
	if not (date_data_raw is Dictionary):
		return OperationResult.fail(ERR_INVALID_DATA, "Parsed date has invalid format.")

	var date_data: Dictionary = _copy_dictionary(date_data_raw)
	var year: int = int(date_data.get("year", 0))
	var month: int = int(date_data.get("month", 0))
	var day: int = int(date_data.get("day", 0))

	var adjusted_year: int = year
	var adjusted_month: int = month
	if adjusted_month <= 2:
		adjusted_year -= 1
		adjusted_month += 12

	var era_days: int = (
		365 * adjusted_year
		+ int(floor(float(adjusted_year) / 4.0))
		- int(floor(float(adjusted_year) / 100.0))
		+ int(floor(float(adjusted_year) / 400.0))
		+ int(floor(float(153 * (adjusted_month - 3) + 2) / 5.0))
		+ day
		- 1
	)

	return OperationResult.ok(era_days)


static func compare_iso_dates(left_date: String, right_date: String) -> OperationResult:
	var left_result: OperationResult = date_to_day_number(left_date)
	if not left_result.is_ok():
		return left_result

	var right_result: OperationResult = date_to_day_number(right_date)
	if not right_result.is_ok():
		return right_result

	var left_day: int = int(left_result.data)
	var right_day: int = int(right_result.data)
	var compare_result: int = 0

	if left_day < right_day:
		compare_result = -1
	elif left_day > right_day:
		compare_result = 1

	return OperationResult.ok(compare_result)


static func elapsed_years(start_date: String, end_date: String) -> OperationResult:
	var start_result: OperationResult = date_to_day_number(start_date)
	if not start_result.is_ok():
		return start_result

	var end_result: OperationResult = date_to_day_number(end_date)
	if not end_result.is_ok():
		return end_result

	var start_day: int = int(start_result.data)
	var end_day: int = int(end_result.data)
	if end_day < start_day:
		return OperationResult.fail(ERR_INVALID_DATA, "End date cannot be earlier than start date.")

	return OperationResult.ok(float(end_day - start_day) / 365.0)


static func inclusive_months_between(start_date: String, end_date: String) -> OperationResult:
	var compare_result: OperationResult = compare_iso_dates(start_date, end_date)
	if not compare_result.is_ok():
		return compare_result

	if int(compare_result.data) > 0:
		return OperationResult.fail(ERR_INVALID_DATA, "End date cannot be earlier than start date.")

	var start_key_result: OperationResult = period_key_from_date(start_date)
	if not start_key_result.is_ok():
		return start_key_result

	var end_key_result: OperationResult = period_key_from_date(end_date)
	if not end_key_result.is_ok():
		return end_key_result

	var months: int = int(end_key_result.data) - int(start_key_result.data) + 1
	if months < 1:
		months = 1

	return OperationResult.ok(months)


static func period_key_from_date(date_value: String) -> OperationResult:
	var parse_result: OperationResult = parse_iso_date(date_value)
	if not parse_result.is_ok():
		return parse_result

	var date_data_raw: Variant = parse_result.data
	if not (date_data_raw is Dictionary):
		return OperationResult.fail(ERR_INVALID_DATA, "Parsed date has invalid format.")

	var date_data: Dictionary = _copy_dictionary(date_data_raw)
	return OperationResult.ok(period_key(int(date_data.get("year", 0)), int(date_data.get("month", 0))))


static func period_key(year: int, month: int) -> int:
	return year * 12 + month


static func period_label_from_key(value: int) -> String:
	var year: int = int(floor(float(value - 1) / 12.0))
	var month: int = value - year * 12
	return "%04d-%02d" % [year, month]


static func is_valid_date_parts(year: int, month: int, day: int) -> bool:
	if year < 1900 or month < 1 or month > 12 or day < 1:
		return false

	return day <= days_in_month(year, month)


static func days_in_month(year: int, month: int) -> int:
	match month:
		1, 3, 5, 7, 8, 10, 12:
			return 31
		4, 6, 9, 11:
			return 30
		2:
			if is_leap_year(year):
				return 29
			return 28

	return 0


static func is_leap_year(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


static func _copy_dictionary(value: Variant) -> Dictionary:
	var result: Dictionary = {}

	if value is Dictionary:
		for key in value:
			result[key] = value[key]

	return result
