extends RefCounted
class_name UserFlowBackendTest

const PORTFOLIO_ID := "user_flow_demo"
const PORTFOLIO_NAME := "User Flow Demo"
const LEGACY_DEV_PORTFOLIO_ID := "dev_real_api_flow"

const FIRST_DEPOSIT_AMOUNT: float = 10000.0
const SECOND_DEPOSIT_AMOUNT: float = 2500.0
const FIRST_SNAPSHOT_AMOUNT: float = 10100.0
const LATEST_SNAPSHOT_AMOUNT: float = 13750.0


func run_user_actions() -> OperationResult:
	var cleanup_service: PortfolioService = PortfolioService.new()
	cleanup_service.delete_portfolio(PORTFOLIO_ID)
	cleanup_service.delete_portfolio(LEGACY_DEV_PORTFOLIO_ID)

	PortfolioDataManager.begin_batch_operations()

	var create_result: OperationResult = PortfolioDataManager.create_portfolio(
		PORTFOLIO_ID,
		PORTFOLIO_NAME,
		PortfolioData.TYPE_IKE,
		"PLN",
		"chart"
	)
	if not create_result.is_ok():
		return _batch_step_fail("create_portfolio", create_result)

	var first_deposit_result: OperationResult = PortfolioDataManager.add_deposit(
		PORTFOLIO_ID,
		"2025-12-01",
		FIRST_DEPOSIT_AMOUNT,
		"PLN",
		"User flow deposit 1"
	)
	if not first_deposit_result.is_ok():
		return _batch_step_fail("add_first_deposit", first_deposit_result)

	var second_deposit_result: OperationResult = PortfolioDataManager.add_deposit(
		PORTFOLIO_ID,
		"2025-12-15",
		SECOND_DEPOSIT_AMOUNT,
		"PLN",
		"User flow deposit 2"
	)
	if not second_deposit_result.is_ok():
		return _batch_step_fail("add_second_deposit", second_deposit_result)

	var first_snapshot_result: OperationResult = PortfolioDataManager.add_value_snapshot(
		PORTFOLIO_ID,
		"2025-12-10",
		FIRST_SNAPSHOT_AMOUNT,
		"PLN",
		"User flow snapshot 1"
	)
	if not first_snapshot_result.is_ok():
		return _batch_step_fail("add_first_snapshot", first_snapshot_result)

	var second_snapshot_result: OperationResult = PortfolioDataManager.add_value_snapshot(
		PORTFOLIO_ID,
		"2025-12-31",
		LATEST_SNAPSHOT_AMOUNT,
		"PLN",
		"User flow snapshot 2"
	)
	if not second_snapshot_result.is_ok():
		return _batch_step_fail("add_second_snapshot", second_snapshot_result)

	PortfolioDataManager.end_batch_operations(false)
	return _verify_saved_portfolio()


func calculate_statistics(monthly_inflation: InflationData) -> OperationResult:
	if monthly_inflation == null:
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Monthly inflation is required for user flow statistics.")

	var monthly_series: Array[InflationData] = []
	monthly_series.append(monthly_inflation)
	return PortfolioDataManager.build_statistics(PORTFOLIO_ID, monthly_series)


func _verify_saved_portfolio() -> OperationResult:
	var load_result: OperationResult = PortfolioDataManager.load_all_portfolios()
	if not load_result.is_ok():
		return _step_fail("load_all_portfolios", load_result)

	var portfolios_raw: Variant = load_result.data
	if not (portfolios_raw is Array):
		return OperationResult.fail(ERR_INVALID_DATA, "load_all_portfolios returned invalid data.")

	var portfolios: Array = []
	portfolios.assign(portfolios_raw)

	for item in portfolios:
		if not (item is PortfolioData):
			continue

		var portfolio: PortfolioData = item as PortfolioData
		if portfolio == null or portfolio.id != PORTFOLIO_ID:
			continue

		var latest_snapshot: Dictionary = portfolio.get_latest_value_snapshot()
		if latest_snapshot.is_empty():
			return OperationResult.fail(ERR_INVALID_DATA, "Saved user flow portfolio has no latest snapshot.")

		return OperationResult.ok({
			"portfolio_id": portfolio.id,
			"name": portfolio.name,
			"portfolio_type": portfolio.portfolio_type,
			"base_currency": portfolio.base_currency,
			"deposits": portfolio.deposits.size(),
			"snapshots": portfolio.value_snapshots.size(),
			"latest_snapshot_value": float(latest_snapshot.get("total_value", 0.0)),
			"latest_snapshot_currency": str(latest_snapshot.get("currency", ""))
		}, "User flow portfolio saved and loaded.")

	return OperationResult.fail(ERR_DOES_NOT_EXIST, "Saved user flow portfolio was not found after reload.")


func _step_fail(step: String, result: OperationResult) -> OperationResult:
	if result == null:
		return OperationResult.fail(FAILED, "%s failed: null result." % step)

	return OperationResult.fail(
		result.error_code,
		"%s failed: %s" % [step, result.message],
		result.data
	)


func _batch_step_fail(step: String, result: OperationResult) -> OperationResult:
	PortfolioDataManager.end_batch_operations(false)
	return _step_fail(step, result)
