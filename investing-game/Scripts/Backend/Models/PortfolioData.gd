extends Resource
class_name PortfolioData

const SCHEMA_VERSION := 2

const TYPE_REGULAR := "regular"
const TYPE_IKE := "ike"
const TYPE_IKZE := "ikze"

@export var id: String = ""
@export var name: String = "Main Portfolio"
@export var portfolio_type: String = TYPE_REGULAR
@export var icon_name: String = "briefcase"
@export var base_currency: String = "PLN"
@export var deposits: Array[PortfolioDepositData] = []
@export var value_snapshots: Array[PortfolioSnapshotData] = []


func add_deposit(date: String, amount: float, currency: String = "", note: String = "") -> Error:
	var clean_currency := MoneyData.normalize_currency(currency)
	if clean_currency.is_empty():
		clean_currency = base_currency

	var deposit := PortfolioDepositData.create(date, amount, clean_currency, note)
	var errors := deposit.validate()
	if not errors.is_empty():
		return ERR_INVALID_PARAMETER

	deposits.append(deposit)
	return OK


func add_value_snapshot(date: String, total_value: float, currency: String = "", note: String = "") -> Error:
	var clean_currency := MoneyData.normalize_currency(currency)
	if clean_currency.is_empty():
		clean_currency = base_currency

	var snapshot := PortfolioSnapshotData.create(date, total_value, clean_currency, note)
	var errors := snapshot.validate()
	if not errors.is_empty():
		return ERR_INVALID_PARAMETER

	value_snapshots.append(snapshot)
	return OK


func get_latest_value_snapshot() -> Dictionary:
	if value_snapshots.is_empty():
		return {}

	return value_snapshots[value_snapshots.size() - 1].to_dict()


func get_total_deposits() -> Dictionary:
	var totals: Dictionary = {}

	for deposit in deposits:
		if deposit == null or deposit.money == null:
			continue

		var currency := MoneyData.normalize_currency(deposit.money.currency)
		totals[currency] = float(totals.get(currency, 0.0)) + deposit.money.amount

	return totals


func update_metadata(new_name: String, new_portfolio_type: String, new_icon_name: String, new_base_currency: String) -> Error:
	var clean_name := new_name.strip_edges()
	var clean_type := _normalize_portfolio_type(new_portfolio_type)
	var clean_currency := MoneyData.normalize_currency(new_base_currency)

	if clean_name.is_empty() or clean_currency.is_empty() or not _is_supported_portfolio_type(clean_type):
		return ERR_INVALID_PARAMETER

	name = clean_name
	portfolio_type = clean_type
	icon_name = new_icon_name.strip_edges()
	base_currency = clean_currency
	return OK


func update_deposit(deposit_id: String, date: String, amount: float, currency: String, note: String = "") -> Error:
	var deposit := get_deposit(deposit_id)
	if deposit == null:
		return ERR_DOES_NOT_EXIST

	var updated_deposit := PortfolioDepositData.create(date, amount, currency, note)
	updated_deposit.id = deposit.id

	var errors := updated_deposit.validate()
	if not errors.is_empty():
		return ERR_INVALID_PARAMETER

	deposit.date = updated_deposit.date
	deposit.money = updated_deposit.money
	deposit.note = updated_deposit.note
	return OK


func delete_deposit(deposit_id: String) -> Error:
	for index in range(deposits.size()):
		var deposit := deposits[index]
		if deposit != null and deposit.id == deposit_id:
			deposits.remove_at(index)
			return OK

	return ERR_DOES_NOT_EXIST


func get_deposit(deposit_id: String) -> PortfolioDepositData:
	for deposit in deposits:
		if deposit != null and deposit.id == deposit_id:
			return deposit

	return null


func update_value_snapshot(snapshot_id: String, date: String, total_value: float, currency: String, note: String = "") -> Error:
	var snapshot := get_value_snapshot(snapshot_id)
	if snapshot == null:
		return ERR_DOES_NOT_EXIST

	var updated_snapshot := PortfolioSnapshotData.create(date, total_value, currency, note)
	updated_snapshot.id = snapshot.id

	var errors := updated_snapshot.validate()
	if not errors.is_empty():
		return ERR_INVALID_PARAMETER

	snapshot.date = updated_snapshot.date
	snapshot.total_value = updated_snapshot.total_value
	snapshot.note = updated_snapshot.note
	return OK


func delete_value_snapshot(snapshot_id: String) -> Error:
	for index in range(value_snapshots.size()):
		var snapshot := value_snapshots[index]
		if snapshot != null and snapshot.id == snapshot_id:
			value_snapshots.remove_at(index)
			return OK

	return ERR_DOES_NOT_EXIST


func get_value_snapshot(snapshot_id: String) -> PortfolioSnapshotData:
	for snapshot in value_snapshots:
		if snapshot != null and snapshot.id == snapshot_id:
			return snapshot

	return null


func validate() -> PackedStringArray:
	var errors := PackedStringArray()

	if id.strip_edges().is_empty():
		errors.append("Portfolio id is empty.")

	if name.strip_edges().is_empty():
		errors.append("Portfolio name is empty.")

	if not _is_supported_portfolio_type(portfolio_type):
		errors.append("Unsupported portfolio type: %s." % portfolio_type)

	if MoneyData.normalize_currency(base_currency).is_empty():
		errors.append("Base currency is empty.")

	for deposit in deposits:
		if deposit == null:
			errors.append("Deposit is null.")
		else:
			errors.append_array(deposit.validate())

	for snapshot in value_snapshots:
		if snapshot == null:
			errors.append("Value snapshot is null.")
		else:
			errors.append_array(snapshot.validate())

	return errors


func to_dict() -> Dictionary:
	var deposit_dicts: Array[Dictionary] = []
	for deposit in deposits:
		if deposit != null:
			deposit_dicts.append(deposit.to_dict())

	var snapshot_dicts: Array[Dictionary] = []
	for snapshot in value_snapshots:
		if snapshot != null:
			snapshot_dicts.append(snapshot.to_dict())

	return {
		"schema_version": SCHEMA_VERSION,
		"id": id.strip_edges(),
		"name": name.strip_edges(),
		"portfolio_type": _normalize_portfolio_type(portfolio_type),
		"icon_name": icon_name.strip_edges(),
		"base_currency": MoneyData.normalize_currency(base_currency),
		"deposits": deposit_dicts,
		"value_snapshots": snapshot_dicts
	}


static func from_dict(data: Dictionary) -> PortfolioData:
	var portfolio := PortfolioData.new()

	portfolio.id = str(data.get("id", "")).strip_edges()
	portfolio.name = str(data.get("name", "Main Portfolio")).strip_edges()
	portfolio.portfolio_type = PortfolioData._normalize_portfolio_type(str(data.get("portfolio_type", TYPE_REGULAR)))
	portfolio.icon_name = str(data.get("icon_name", "briefcase")).strip_edges()
	portfolio.base_currency = MoneyData.normalize_currency(str(data.get("base_currency", "PLN")))
	portfolio.deposits = PortfolioData._copy_deposit_array(data.get("deposits", []))
	portfolio.value_snapshots = PortfolioData._copy_snapshot_array(data.get("value_snapshots", []))

	return portfolio


static func _copy_deposit_array(value: Variant) -> Array[PortfolioDepositData]:
	var result: Array[PortfolioDepositData] = []

	if value is Array:
		for item in value:
			if item is PortfolioDepositData:
				result.append(item)
			elif item is Dictionary:
				result.append(PortfolioDepositData.from_dict(item))

	return result


static func _copy_snapshot_array(value: Variant) -> Array[PortfolioSnapshotData]:
	var result: Array[PortfolioSnapshotData] = []

	if value is Array:
		for item in value:
			if item is PortfolioSnapshotData:
				result.append(item)
			elif item is Dictionary:
				result.append(PortfolioSnapshotData.from_dict(item))

	return result


static func _normalize_portfolio_type(value: String) -> String:
	return value.strip_edges().to_lower()


static func _is_supported_portfolio_type(value: String) -> bool:
	return _normalize_portfolio_type(value) in [
		TYPE_REGULAR,
		TYPE_IKE,
		TYPE_IKZE
	]
