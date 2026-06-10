extends RefCounted
class_name PortfolioRepository

const PORTFOLIOS_DIR_PATH := "user://portfolios"
const FILE_EXTENSION := ".json"
const TEMP_EXTENSION := ".tmp"
const BACKUP_EXTENSION := ".bak"


func save_portfolio(portfolio: PortfolioData) -> OperationResult:
	if portfolio == null:
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Cannot save null portfolio.")

	var validation_errors := portfolio.validate()
	if not validation_errors.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "Portfolio is invalid: %s" % str(validation_errors))

	var directory_error := _ensure_portfolios_directory()
	if directory_error != OK:
		return OperationResult.fail(directory_error, "Cannot create portfolios directory: %s" % error_string(directory_error))

	var file_path := _portfolio_file_path(portfolio.id)
	var temp_path := file_path + TEMP_EXTENSION
	var backup_path := file_path + BACKUP_EXTENSION

	var serialized := JSON.stringify(portfolio.to_dict())
	var write_error := _write_text_file(temp_path, serialized)
	if write_error != OK:
		return OperationResult.fail(write_error, "Cannot write temporary portfolio file: %s" % error_string(write_error))

	if FileAccess.file_exists(file_path):
		if FileAccess.file_exists(backup_path):
			var old_backup_remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
			if old_backup_remove_error != OK:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
				return OperationResult.fail(old_backup_remove_error, "Cannot remove old portfolio backup: %s" % error_string(old_backup_remove_error))

		var backup_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(file_path), ProjectSettings.globalize_path(backup_path))
		if backup_error != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
			return OperationResult.fail(backup_error, "Cannot backup existing portfolio file: %s" % error_string(backup_error))

		var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
		if remove_error != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
			return OperationResult.fail(remove_error, "Cannot replace existing portfolio file: %s" % error_string(remove_error))

	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(file_path))
	if rename_error != OK:
		if FileAccess.file_exists(backup_path) and not FileAccess.file_exists(file_path):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(file_path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return OperationResult.fail(rename_error, "Cannot finalize portfolio file: %s" % error_string(rename_error))

	return OperationResult.ok(portfolio, "Portfolio saved.")


func load_portfolio(portfolio_id: String) -> OperationResult:
	var file_path := _portfolio_file_path(portfolio_id)
	if not FileAccess.file_exists(file_path):
		return OperationResult.fail(ERR_FILE_NOT_FOUND, "Portfolio file does not exist: %s" % portfolio_id)

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		var open_error := FileAccess.get_open_error()
		return OperationResult.fail(open_error, "Cannot open portfolio file: %s" % error_string(open_error))

	var parsed_data = JSON.parse_string(file.get_as_text())
	if not (parsed_data is Dictionary):
		var quarantine_result := _quarantine_corrupted_file(file_path)
		return OperationResult.fail(ERR_PARSE_ERROR, "Portfolio JSON is invalid. %s" % quarantine_result.message)

	var portfolio := PortfolioData.from_dict(parsed_data)
	var validation_errors := portfolio.validate()
	if not validation_errors.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "Loaded portfolio is invalid: %s" % str(validation_errors))

	return OperationResult.ok(portfolio, "Portfolio loaded.")


func load_all_portfolios() -> OperationResult:
	var portfolios: Array[PortfolioData] = []

	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(PORTFOLIOS_DIR_PATH)):
		return OperationResult.ok(portfolios, "No portfolios directory.")

	var dir := DirAccess.open(PORTFOLIOS_DIR_PATH)
	if dir == null:
		var open_error := DirAccess.get_open_error()
		return OperationResult.fail(open_error, "Cannot open portfolios directory: %s" % error_string(open_error))

	for file_name_value in dir.get_files():
		var file_name := str(file_name_value)
		if not file_name.ends_with(FILE_EXTENSION):
			continue
		if file_name.ends_with(TEMP_EXTENSION) or file_name.ends_with(BACKUP_EXTENSION):
			continue

		var portfolio_id := file_name.substr(0, file_name.length() - FILE_EXTENSION.length())
		var load_result := load_portfolio(portfolio_id)
		if load_result == null:
			push_error("[PortfolioRepository] Cannot load portfolio %s: repository returned null result." % portfolio_id)
			continue

		if load_result.is_ok() and load_result.data is PortfolioData:
			portfolios.append(load_result.data)
		else:
			push_error("[PortfolioRepository] Cannot load portfolio %s: %s" % [portfolio_id, load_result.message])

	return OperationResult.ok(portfolios, "Portfolios loaded.")


func delete_portfolio(portfolio_id: String) -> OperationResult:
	var file_path := _portfolio_file_path(portfolio_id)
	if not FileAccess.file_exists(file_path):
		return OperationResult.fail(ERR_FILE_NOT_FOUND, "Portfolio file does not exist: %s" % portfolio_id)

	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	if remove_error != OK:
		return OperationResult.fail(remove_error, "Cannot delete portfolio file: %s" % error_string(remove_error))

	return OperationResult.ok(null, "Portfolio deleted.")


func _ensure_portfolios_directory() -> Error:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PORTFOLIOS_DIR_PATH))


func _write_text_file(file_path: String, text: String) -> Error:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_string(text)
	return OK


func _quarantine_corrupted_file(file_path: String) -> OperationResult:
	var quarantine_path := "%s.corrupt.%d" % [
		file_path,
		int(Time.get_unix_time_from_system())
	]

	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(file_path), ProjectSettings.globalize_path(quarantine_path))
	if rename_error != OK:
		return OperationResult.fail(rename_error, "Could not quarantine corrupted file: %s" % error_string(rename_error))

	return OperationResult.ok(null, "Corrupted file moved to: %s" % quarantine_path)


func _portfolio_file_path(portfolio_id: String) -> String:
	return "%s/%s%s" % [PORTFOLIOS_DIR_PATH, _safe_file_id(portfolio_id), FILE_EXTENSION]


func _safe_file_id(value: String) -> String:
	var safe_id := value.strip_edges().to_lower()
	safe_id = safe_id.replace(" ", "_")
	safe_id = safe_id.replace("/", "_")
	safe_id = safe_id.replace("\\", "_")
	safe_id = safe_id.replace(":", "_")

	if safe_id.is_empty():
		return "main"

	return safe_id
