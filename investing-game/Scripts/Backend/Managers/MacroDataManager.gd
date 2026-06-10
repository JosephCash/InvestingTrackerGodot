extends Node

signal inflation_updated(inflation: InflationData)
signal monthly_inflation_updated(inflation: InflationData)
signal macro_fetch_failed(source_id: String, error_message: String)

const INFLATION_CACHE_DURATION_SECONDS: float = 24.0 * 60.0 * 60.0

var cached_inflation: InflationData
var cached_monthly_inflation: InflationData
var gus_inflation_api: GusInflationProvider


func _ready() -> void:
	cached_inflation = SaveManager.load_inflation_cache()
	cached_monthly_inflation = SaveManager.load_monthly_inflation_cache()

	gus_inflation_api = GusInflationProvider.new()
	add_child(gus_inflation_api)
	gus_inflation_api.fetch_successful.connect(_on_inflation_fetched)
	gus_inflation_api.fetch_failed.connect(_on_inflation_fetch_failed)
	gus_inflation_api.monthly_cpi_fetch_successful.connect(_on_monthly_inflation_fetched)
	gus_inflation_api.monthly_cpi_fetch_failed.connect(_on_monthly_inflation_fetch_failed)


func request_latest_poland_inflation() -> void:
	if _check_inflation_cache():
		return

	print("[API] Fetching GUS annual CPI inflation.")
	gus_inflation_api.fetch_latest_annual_cpi()


func request_latest_poland_monthly_inflation() -> void:
	if _check_monthly_inflation_cache():
		return

	print("[API] Fetching GUS monthly CPI inflation.")
	gus_inflation_api.fetch_latest_monthly_cpi()


func _check_inflation_cache() -> bool:
	if cached_inflation == null:
		return false

	var cache_age_seconds: float = Time.get_unix_time_from_system() - cached_inflation.last_updated
	if cache_age_seconds >= INFLATION_CACHE_DURATION_SECONDS:
		return false

	print("[Cache] Fresh inflation data | age=", int(cache_age_seconds), "s")
	inflation_updated.emit(cached_inflation)
	return true


func _check_monthly_inflation_cache() -> bool:
	if cached_monthly_inflation == null:
		return false

	var cache_age_seconds: float = Time.get_unix_time_from_system() - cached_monthly_inflation.last_updated
	if cache_age_seconds >= INFLATION_CACHE_DURATION_SECONDS:
		return false

	print("[Cache] Fresh monthly inflation data | age=", int(cache_age_seconds), "s")
	monthly_inflation_updated.emit(cached_monthly_inflation)
	return true


func _on_inflation_fetched(inflation: InflationData) -> void:
	cached_inflation = inflation
	SaveManager.save_inflation_cache(inflation)
	inflation_updated.emit(inflation)


func _on_monthly_inflation_fetched(inflation: InflationData) -> void:
	cached_monthly_inflation = inflation
	SaveManager.save_monthly_inflation_cache(inflation)
	monthly_inflation_updated.emit(inflation)


func _on_inflation_fetch_failed(error_message: String) -> void:
	print("[API Error] GUS inflation: ", error_message)
	if cached_inflation != null:
		print("[Cache] Using stale inflation data after API error: ", cached_inflation.get_period_label())
		inflation_updated.emit(cached_inflation)

	macro_fetch_failed.emit("gus_inflation", error_message)


func _on_monthly_inflation_fetch_failed(error_message: String) -> void:
	print("[API Error] GUS monthly inflation: ", error_message)
	if cached_monthly_inflation != null:
		print("[Cache] Using stale monthly inflation data after API error: ", cached_monthly_inflation.get_period_label())
		monthly_inflation_updated.emit(cached_monthly_inflation)

	macro_fetch_failed.emit("gus_monthly_inflation", error_message)
