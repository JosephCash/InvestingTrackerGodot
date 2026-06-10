extends Node
class_name GusInflationProvider

signal fetch_successful(inflation: InflationData)
signal fetch_failed(error_message: String)
signal monthly_cpi_fetch_successful(inflation: InflationData)
signal monthly_cpi_fetch_failed(error_message: String)

const ANNUAL_CPI_VARIABLE_ID := "217230"
const ANNUAL_CPI_URL_TEMPLATE := "https://bdl.stat.gov.pl/api/v1/data/by-variable/%s?unit-level=0&lang=pl"
const MONTHLY_CPI_VARIABLE_ID := "305"
const MONTHLY_CPI_SECTION_ID := "736"
const MONTHLY_CPI_URL_TEMPLATE := "https://api-dbw.stat.gov.pl/api/variable/variable-data-section?id-zmienna=%s&id-przekroj=%s&id-rok=%d&id-okres=%d&ile-na-stronie=5000&numer-strony=0&lang=pl"

const DBW_PERIOD_JANUARY_ID := 247
const DBW_PRESENTATION_PREVIOUS_PERIOD_ID := 2
const DBW_PRESENTATION_SAME_PERIOD_LAST_YEAR_ID := 5
const DBW_POLAND_POSITION_ID := 33617
const DBW_CONSUMER_GOODS_OVERALL_POSITION_ID := 6656078
const DBW_HOUSEHOLDS_OVERALL_POSITION_ID := 6902025
const MONTHLY_CPI_LOOKBACK_MONTHS := 24
const MONTHLY_CPI_RETRY_DELAY_SECONDS := 0.4

var _monthly_cpi_candidates: Array[Dictionary] = []
var _monthly_cpi_request_active := false


func fetch_latest_annual_cpi() -> void:
	var http_request := HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed.bind(http_request))

	var headers := PackedStringArray([
		"User-Agent: Mozilla/5.0",
		"Accept: application/vnd.api+json, application/json"
	])

	var error := http_request.request(ANNUAL_CPI_URL_TEMPLATE % ANNUAL_CPI_VARIABLE_ID, headers)
	if error != OK:
		fetch_failed.emit("GUS BDL request initialization failed: %s" % error_string(error))
		http_request.queue_free()


func fetch_latest_monthly_cpi() -> void:
	if _monthly_cpi_request_active:
		return

	_monthly_cpi_request_active = true
	_monthly_cpi_candidates = _build_monthly_cpi_candidates()
	_request_next_monthly_cpi_candidate()


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http_request: HTTPRequest
) -> void:
	http_request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		fetch_failed.emit("GUS BDL network error. Result: %s" % result)
		return

	if response_code == 429:
		fetch_failed.emit("GUS BDL rate limit exceeded.")
		return

	if response_code != 200:
		fetch_failed.emit("GUS BDL HTTP error: %s" % response_code)
		return

	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		fetch_failed.emit("GUS BDL JSON parse error.")
		return

	var inflation := _parse_latest_inflation(json.data)
	if inflation == null:
		fetch_failed.emit("GUS BDL response does not contain valid annual CPI data.")
		return

	fetch_successful.emit(inflation)


func _request_next_monthly_cpi_candidate() -> void:
	if _monthly_cpi_candidates.is_empty():
		_fail_monthly_cpi("GUS DBW response does not contain monthly CPI data in the last %s months." % MONTHLY_CPI_LOOKBACK_MONTHS)
		return

	var candidate_variant = _monthly_cpi_candidates.pop_front()
	if not (candidate_variant is Dictionary):
		_schedule_next_monthly_cpi_candidate()
		return

	var candidate = candidate_variant
	var year := int(candidate["year"])
	var month := int(candidate["month"])
	var period_id := int(candidate["period_id"])

	var http_request := HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_monthly_cpi_request_completed.bind(http_request, year, month, period_id))

	var headers := PackedStringArray([
		"User-Agent: Mozilla/5.0",
		"Accept: application/json"
	])

	var url := MONTHLY_CPI_URL_TEMPLATE % [MONTHLY_CPI_VARIABLE_ID, MONTHLY_CPI_SECTION_ID, year, period_id]
	var error := http_request.request(url, headers)
	if error != OK:
		http_request.queue_free()
		_fail_monthly_cpi("GUS DBW request initialization failed: %s" % error_string(error))


func _on_monthly_cpi_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http_request: HTTPRequest,
	year: int,
	month: int,
	_period_id: int
) -> void:
	http_request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		_fail_monthly_cpi("GUS DBW network error. Result: %s" % result)
		return

	if response_code == 404:
		_schedule_next_monthly_cpi_candidate()
		return

	if response_code == 429:
		_fail_monthly_cpi("GUS DBW rate limit exceeded.")
		return

	if response_code != 200:
		_fail_monthly_cpi("GUS DBW HTTP error: %s" % response_code)
		return

	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		_fail_monthly_cpi("GUS DBW JSON parse error.")
		return

	var inflation := _parse_monthly_cpi(json.data, year, month, _period_id)
	if inflation == null:
		_schedule_next_monthly_cpi_candidate()
		return

	_monthly_cpi_request_active = false
	monthly_cpi_fetch_successful.emit(inflation)


func _parse_latest_inflation(data: Variant) -> InflationData:
	if not (data is Dictionary):
		return null

	var unit_data_list = data.get("data", data.get("value", []))
	if not (unit_data_list is Array) or unit_data_list.is_empty():
		return null

	var poland_data := _find_unit_with_values(unit_data_list)
	if poland_data.is_empty():
		return null

	var values := _extract_values_array(poland_data)
	if values.is_empty():
		return null

	var latest_year: int = -1
	var latest_index_value: float = -1.0

	for item in values:
		if not (item is Dictionary) or not item.has("year") or not item.has("val"):
			continue

		var item_year := int(item["year"])
		if item_year > latest_year:
			latest_year = item_year
			latest_index_value = float(item["val"])

	if latest_year <= 0 or latest_index_value <= 0.0:
		return null

	var inflation := InflationData.new()
	inflation.id = "poland_cpi_annual"
	inflation.name = "Poland CPI annual"
	inflation.country_code = "PL"
	inflation.period = "annual"
	inflation.year = latest_year
	inflation.index_value = latest_index_value
	inflation.inflation_rate = latest_index_value - 100.0
	inflation.source = "gus_bdl"
	inflation.source_variable_id = ANNUAL_CPI_VARIABLE_ID
	inflation.last_updated = Time.get_unix_time_from_system()

	return inflation


func _schedule_next_monthly_cpi_candidate() -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = MONTHLY_CPI_RETRY_DELAY_SECONDS
	add_child(timer)
	timer.timeout.connect(_on_monthly_cpi_retry_timer_timeout.bind(timer))
	timer.start()


func _on_monthly_cpi_retry_timer_timeout(timer: Timer) -> void:
	timer.queue_free()
	_request_next_monthly_cpi_candidate()


func _fail_monthly_cpi(error_message: String) -> void:
	_monthly_cpi_request_active = false
	monthly_cpi_fetch_failed.emit(error_message)


func _parse_monthly_cpi(data: Variant, year: int, month: int, _period_id: int) -> InflationData:
	if not (data is Dictionary):
		return null

	var rows = data.get("data", [])
	if not (rows is Array) or rows.is_empty():
		return null

	var month_over_month_index := -1.0
	var year_over_year_index := -1.0

	for item in rows:
		if not (item is Dictionary):
			continue

		if not _is_overall_monthly_cpi_row(item):
			continue

		var presentation_id := int(item.get("id-sposob-prezentacji-miara", -1))
		var value := float(item.get("wartosc", -1.0))
		if value <= 0.0:
			continue

		if presentation_id == DBW_PRESENTATION_PREVIOUS_PERIOD_ID:
			month_over_month_index = value
		elif presentation_id == DBW_PRESENTATION_SAME_PERIOD_LAST_YEAR_ID:
			year_over_year_index = value

	if month_over_month_index <= 0.0 and year_over_year_index <= 0.0:
		return null

	var primary_index := year_over_year_index
	if primary_index <= 0.0:
		primary_index = month_over_month_index

	var inflation := InflationData.new()
	inflation.id = "poland_cpi_monthly_%04d_%02d" % [year, month]
	inflation.name = "Poland CPI monthly"
	inflation.country_code = "PL"
	inflation.period = InflationData.PERIOD_MONTHLY
	inflation.year = year
	inflation.month = month
	inflation.index_value = primary_index
	inflation.inflation_rate = primary_index - 100.0
	inflation.month_over_month_index = month_over_month_index
	inflation.month_over_month_rate = _rate_from_index(month_over_month_index)
	inflation.year_over_year_index = year_over_year_index
	inflation.year_over_year_rate = _rate_from_index(year_over_year_index)
	inflation.source = "gus_dbw"
	inflation.source_variable_id = MONTHLY_CPI_VARIABLE_ID
	inflation.last_updated = Time.get_unix_time_from_system()

	if not inflation.validate().is_empty():
		return null

	return inflation


func _is_overall_monthly_cpi_row(item: Dictionary) -> bool:
	return (
		int(item.get("id-pozycja-1", -1)) == DBW_POLAND_POSITION_ID
		and int(item.get("id-pozycja-2", -1)) == DBW_CONSUMER_GOODS_OVERALL_POSITION_ID
		and int(item.get("id-pozycja-3", -1)) == DBW_HOUSEHOLDS_OVERALL_POSITION_ID
	)


func _build_monthly_cpi_candidates() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var date_parts := Time.get_datetime_dict_from_system()
	var year := int(date_parts["year"])
	var month := int(date_parts["month"]) - 1

	if month < 1:
		month = 12
		year -= 1

	for _index in range(MONTHLY_CPI_LOOKBACK_MONTHS):
		candidates.append({
			"year": year,
			"month": month,
			"period_id": _month_to_dbw_period_id(month)
		})

		month -= 1
		if month < 1:
			month = 12
			year -= 1

	return candidates


func _month_to_dbw_period_id(month: int) -> int:
	return DBW_PERIOD_JANUARY_ID + month - 1


func _rate_from_index(value: float) -> float:
	if value <= 0.0:
		return 0.0

	return value - 100.0


func _find_unit_with_values(unit_data_list: Array) -> Dictionary:
	for item in unit_data_list:
		if not (item is Dictionary):
			continue

		var values := _extract_values_array(item)
		if not values.is_empty():
			return item

	return {}


func _extract_values_array(unit_data: Dictionary) -> Array:
	if unit_data.has("attributes") and unit_data["attributes"] is Dictionary:
		var attributes: Dictionary = unit_data["attributes"]
		var attribute_values = attributes.get("values", [])
		if attribute_values is Array:
			return attribute_values

	var direct_values = unit_data.get("values", [])
	if direct_values is Array:
		return direct_values

	return []
