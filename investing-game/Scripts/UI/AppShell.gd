extends Control
class_name AppShell

signal screen_requested(screen_id: String)
signal popup_closed()

const SCREEN_DASHBOARD: String = "dashboard"
const SCREEN_PORTFOLIO: String = "portfolio"
const SCREEN_ANALYSIS: String = "analysis"
const SCREEN_SETTINGS: String = "settings"

@onready var _header_title_label: Label = get_node("MainLayout/HeaderBar/HeaderMargin/HeaderRow/HeaderLeft/HeaderTitleLabel")
@onready var _header_context_label: Label = get_node("MainLayout/HeaderBar/HeaderMargin/HeaderRow/HeaderLeft/HeaderContextLabel")
@onready var _header_value_label: Label = get_node("MainLayout/HeaderBar/HeaderMargin/HeaderRow/HeaderRight/HeaderValueLabel")
@onready var _header_result_label: Label = get_node("MainLayout/HeaderBar/HeaderMargin/HeaderRow/HeaderRight/HeaderResultLabel")
@onready var _content_root: Control = get_node("MainLayout/ContentHost/ContentMargin/ContentRoot")
@onready var _popup_overlay: Control = get_node("PopupLayer/PopupOverlay")
@onready var _popup_content: Control = get_node("PopupLayer/PopupOverlay/PopupHost/PopupContent")
@onready var _dashboard_button: Button = get_node("MainLayout/FooterBar/FooterMargin/FooterTabs/DashboardButton")
@onready var _portfolio_button: Button = get_node("MainLayout/FooterBar/FooterMargin/FooterTabs/PortfolioButton")
@onready var _analysis_button: Button = get_node("MainLayout/FooterBar/FooterMargin/FooterTabs/AnalysisButton")
@onready var _settings_button: Button = get_node("MainLayout/FooterBar/FooterMargin/FooterTabs/SettingsButton")

var current_screen_id: String = ""
var selected_portfolio_id: String = ""


func _ready() -> void:
	_connect_navigation()
	_popup_overlay.visible = false
	set_global_header(0.0, SettingsManager.get_base_currency(), 0.0, 0.0)
	show_placeholder_screen(SCREEN_DASHBOARD)


func show_placeholder_screen(screen_id: String) -> void:
	current_screen_id = screen_id
	_set_active_footer(screen_id)
	_clear_content()

	var wrapper: VBoxContainer = VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.alignment = BoxContainer.ALIGNMENT_CENTER
	wrapper.add_theme_constant_override("separation", 10)
	_content_root.add_child(wrapper)

	var title: Label = Label.new()
	title.text = _screen_title(screen_id)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	wrapper.add_child(title)

	var hint: Label = Label.new()
	hint.text = "Tu podepniesz scene ekranu: %s" % screen_id
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 14)
	wrapper.add_child(hint)

	screen_requested.emit(screen_id)


func set_content_screen(screen: Control, screen_id: String = "") -> void:
	if screen == null:
		return

	if not screen_id.is_empty():
		current_screen_id = screen_id
		_set_active_footer(screen_id)

	_clear_content()
	screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_root.add_child(screen)


func set_global_header(total_value: float, currency: String, profit: float, profit_percent: float) -> void:
	selected_portfolio_id = ""
	_header_title_label.text = "Investor Notes"
	_header_context_label.text = "Wszystkie portfele"
	_header_value_label.text = "%s %s" % [_format_amount(total_value), currency]
	_header_result_label.text = "%s %s (%s%%)" % [
		_format_amount(profit),
		currency,
		_format_amount(profit_percent)
	]


func set_portfolio_header(
	portfolio_id: String,
	portfolio_name: String,
	total_value: float,
	currency: String,
	profit: float,
	profit_percent: float
) -> void:
	selected_portfolio_id = portfolio_id
	_header_title_label.text = portfolio_name
	_header_context_label.text = "Wybrany portfel"
	_header_value_label.text = "%s %s" % [_format_amount(total_value), currency]
	_header_result_label.text = "%s %s (%s%%)" % [
		_format_amount(profit),
		currency,
		_format_amount(profit_percent)
	]


func show_popup(content: Control) -> void:
	if content == null:
		return

	_clear_popup()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_popup_content.add_child(content)
	_popup_overlay.visible = true


func close_popup() -> void:
	_popup_overlay.visible = false
	_clear_popup()
	popup_closed.emit()


func _connect_navigation() -> void:
	_dashboard_button.pressed.connect(show_placeholder_screen.bind(SCREEN_DASHBOARD))
	_portfolio_button.pressed.connect(show_placeholder_screen.bind(SCREEN_PORTFOLIO))
	_analysis_button.pressed.connect(show_placeholder_screen.bind(SCREEN_ANALYSIS))
	_settings_button.pressed.connect(show_placeholder_screen.bind(SCREEN_SETTINGS))


func _clear_content() -> void:
	for child in _content_root.get_children():
		child.queue_free()


func _clear_popup() -> void:
	for child in _popup_content.get_children():
		child.queue_free()


func _set_active_footer(screen_id: String) -> void:
	_dashboard_button.button_pressed = screen_id == SCREEN_DASHBOARD
	_portfolio_button.button_pressed = screen_id == SCREEN_PORTFOLIO
	_analysis_button.button_pressed = screen_id == SCREEN_ANALYSIS
	_settings_button.button_pressed = screen_id == SCREEN_SETTINGS


func _screen_title(screen_id: String) -> String:
	match screen_id:
		SCREEN_DASHBOARD:
			return "Dashboard"
		SCREEN_PORTFOLIO:
			return "Portfel"
		SCREEN_ANALYSIS:
			return "Analizy"
		SCREEN_SETTINGS:
			return "Ustawienia"

	return "Ekran"


func _format_amount(value: float) -> String:
	return "%.2f" % value
