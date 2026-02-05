extends Control

# Login Screen
# Handles login, registration, and guest play options
# Local authentication

signal login_successful()
signal registration_successful()

enum LoginState { IDLE, LOGGING_IN, REGISTERING, ERROR }

var current_state: LoginState = LoginState.IDLE

@onready var login_panel: PanelContainer = $CenterContainer/LoginPanel
@onready var vbox: VBoxContainer = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer
@onready var email_input: LineEdit = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer/EmailContainer/EmailInput
@onready var username_input: LineEdit = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer/UsernameContainer/UsernameInput
@onready var username_container: HBoxContainer = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer/UsernameContainer
@onready var password_input: LineEdit = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer/PasswordContainer/PasswordInput
@onready var confirm_password_input: LineEdit = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer/ConfirmPasswordContainer/ConfirmPasswordInput
@onready var confirm_password_container: HBoxContainer = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer/ConfirmPasswordContainer
@onready var verification_input: LineEdit = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer/VerificationContainer/VerificationInput
@onready var verification_container: HBoxContainer = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer/VerificationContainer
@onready var verify_button: Button = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer/VerifyButton
@onready var login_button: Button = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer/ButtonsContainer/LoginButton
@onready var register_button: Button = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer/ButtonsContainer/RegisterButton
@onready var guest_button: Button = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer/GuestButton
@onready var toggle_mode_button: Button = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer/ToggleModeButton
@onready var status_label: Label = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer/StatusLabel
@onready var title_label: Label = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer/TitleLabel
@onready var remember_me_check: CheckBox = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer/RememberMeContainer/RememberMeCheck

const SAVED_LOGIN_PATH = "user://saved_login.dat"
var is_register_mode: bool = false
var is_verification_mode: bool = false

func _ready() -> void:
	# Connect button signals
	login_button.pressed.connect(_on_login_pressed)
	register_button.pressed.connect(_on_register_pressed)
	guest_button.pressed.connect(_on_guest_pressed)
	toggle_mode_button.pressed.connect(_toggle_mode)
	verify_button.pressed.connect(_on_verify_pressed)
	
	# Set up password fields
	password_input.secret = true
	confirm_password_input.secret = true
	
	# Enter key submits
	email_input.text_submitted.connect(func(_t): _focus_next(password_input))
	username_input.text_submitted.connect(func(_t): _focus_next(password_input))
	password_input.text_submitted.connect(func(_t): _on_submit())
	confirm_password_input.text_submitted.connect(func(_t): _on_submit())
	verification_input.text_submitted.connect(func(_t): _on_verify_pressed())
	
	# Start in login mode
	_set_login_mode()
	
	# Check if already logged in
	_check_existing_session()

func _check_existing_session() -> void:
	# First hide the panel and show loading
	login_panel.visible = false
	_show_status("Checking session...", Color.YELLOW)
	
	# Wait a frame for autoloads to initialize
	await get_tree().process_frame
	
	if has_node("/root/PlayerData"):
		var player_data = get_node("/root/PlayerData")
		if not player_data.is_guest and not player_data.user_id.is_empty():
			# Already logged in, go to dashboard
			_show_status("Welcome back, " + player_data.username + "!", Color.GREEN)
			await get_tree().create_timer(0.8).timeout
			_go_to_dashboard()
			return
	
	# Check for saved login credentials
	var saved_login = _load_saved_login()
	if saved_login != null:
		_show_status("Auto-logging in...", Color.YELLOW)
		await get_tree().process_frame
		_auto_login(saved_login.email, saved_login.password)
		return
	
	# No saved session, show login panel
	login_panel.visible = true
	_clear_status()
	email_input.grab_focus()

func _set_login_mode() -> void:
	is_register_mode = false
	is_verification_mode = false
	title_label.text = "LOGIN"
	username_container.visible = false
	confirm_password_container.visible = false
	verification_container.visible = false
	verify_button.visible = false
	login_button.visible = true
	register_button.visible = false
	guest_button.visible = true
	toggle_mode_button.visible = true
	toggle_mode_button.text = "Need an account? Register"
	_clear_status()

func _set_register_mode() -> void:
	is_register_mode = true
	is_verification_mode = false
	title_label.text = "REGISTER"
	username_container.visible = true
	confirm_password_container.visible = true
	verification_container.visible = false
	verify_button.visible = false
	login_button.visible = false
	register_button.visible = true
	guest_button.visible = true
	toggle_mode_button.visible = true
	toggle_mode_button.text = "Already have an account? Login"
	_clear_status()

func _set_verification_mode(email: String) -> void:
	is_register_mode = false
	is_verification_mode = true
	title_label.text = "VERIFY EMAIL"
	username_container.visible = false
	confirm_password_container.visible = false
	verification_container.visible = true
	verify_button.visible = true
	login_button.visible = false
	register_button.visible = false
	guest_button.visible = false
	toggle_mode_button.visible = true
	toggle_mode_button.text = "Back to Login"
	verification_input.text = ""
	verification_input.grab_focus()
	_show_status("Verification code sent to:\n" + email, Color.YELLOW)

func _toggle_mode() -> void:
	if is_verification_mode:
		_set_login_mode()
	elif is_register_mode:
		_set_login_mode()
	else:
		_set_register_mode()

func _focus_next(next_field: LineEdit) -> void:
	next_field.grab_focus()

func _on_submit() -> void:
	if is_register_mode:
		_on_register_pressed()
	else:
		_on_login_pressed()

func _on_login_pressed() -> void:
	var email = email_input.text.strip_edges()
	var password = password_input.text
	
	if email.is_empty():
		_show_status("Please enter your email", Color.RED)
		return
	
	if password.is_empty():
		_show_status("Please enter a password", Color.RED)
		return
	
	current_state = LoginState.LOGGING_IN
	_show_status("Logging in...", Color.YELLOW)
	_set_buttons_enabled(false)
	
	# Use AccountManager for login
	if has_node("/root/AccountManager"):
		var account_mgr = get_node("/root/AccountManager")
		account_mgr.login_success.connect(_on_login_success, CONNECT_ONE_SHOT)
		account_mgr.login_failed.connect(_on_login_error, CONNECT_ONE_SHOT)
		account_mgr.login(email, password)
	else:
		# Fallback to direct login
		await get_tree().create_timer(0.5).timeout
		_on_login_success(email)

func _on_register_pressed() -> void:
	var email = email_input.text.strip_edges()
	var username = username_input.text.strip_edges()
	var password = password_input.text
	var confirm_password = confirm_password_input.text
	
	if email.is_empty():
		_show_status("Please enter your email", Color.RED)
		return
	
	if not "@" in email or not "." in email:
		_show_status("Please enter a valid email", Color.RED)
		return
	
	if username.is_empty():
		_show_status("Please enter a username", Color.RED)
		return
	
	if username.length() < 3:
		_show_status("Username must be at least 3 characters", Color.RED)
		return
	
	if password.is_empty():
		_show_status("Please enter a password", Color.RED)
		return
	
	if password.length() < 3:
		_show_status("Password must be at least 3 characters", Color.RED)
		return
	
	if password != confirm_password:
		_show_status("Passwords do not match", Color.RED)
		return
	
	current_state = LoginState.REGISTERING
	_show_status("Creating account...", Color.YELLOW)
	_set_buttons_enabled(false)
	
	# Use AccountManager for registration (pass email as third param)
	if has_node("/root/AccountManager"):
		var account_mgr = get_node("/root/AccountManager")
		account_mgr.registration_success.connect(_on_register_success, CONNECT_ONE_SHOT)
		account_mgr.registration_failed.connect(_on_login_error, CONNECT_ONE_SHOT)
		account_mgr.verification_required.connect(_on_verification_required, CONNECT_ONE_SHOT)
		account_mgr.register(username, password, email)
	else:
		# Fallback to direct registration
		await get_tree().create_timer(0.5).timeout
		_on_register_success(username)

func _on_verify_pressed() -> void:
	var code = verification_input.text.strip_edges()
	
	if code.is_empty():
		_show_status("Please enter the verification code", Color.RED)
		return
	
	_show_status("Verifying...", Color.YELLOW)
	_set_buttons_enabled(false)
	
	if has_node("/root/AccountManager"):
		var account_mgr = get_node("/root/AccountManager")
		account_mgr.verification_success.connect(_on_verification_success, CONNECT_ONE_SHOT)
		account_mgr.verification_failed.connect(_on_verification_error, CONNECT_ONE_SHOT)
		account_mgr.verify_email(code)
	else:
		_show_status("AccountManager not available", Color.RED)
		_set_buttons_enabled(true)

func _on_verification_required(email: String) -> void:
	current_state = LoginState.IDLE
	_set_buttons_enabled(true)
	_set_verification_mode(email)

func _on_verification_success(username: String) -> void:
	current_state = LoginState.IDLE
	_set_buttons_enabled(true)
	_show_status("Email verified! Welcome, " + username + "!", Color.GREEN)
	await get_tree().create_timer(0.8).timeout
	_go_to_dashboard()

func _on_verification_error(error_message: String) -> void:
	current_state = LoginState.IDLE
	_show_status(error_message, Color.RED)
	_set_buttons_enabled(true)

func _on_guest_pressed() -> void:
	_show_status("Playing as guest...", Color.YELLOW)
	_set_buttons_enabled(false)
	
	await get_tree().create_timer(0.3).timeout
	
	# Use AccountManager for guest play
	if has_node("/root/AccountManager"):
		var account_mgr = get_node("/root/AccountManager")
		account_mgr.play_as_guest()
	else:
		# Fallback
		if has_node("/root/PlayerData"):
			var player_data = get_node("/root/PlayerData")
			player_data.is_guest = true
			player_data.username = "Guest"
			player_data.save_data()
	
	_go_to_dashboard()

func _on_login_success(username: String) -> void:
	current_state = LoginState.IDLE
	_set_buttons_enabled(true)
	
	# Save login if remember me is checked
	if remember_me_check and remember_me_check.button_pressed:
		_save_login(email_input.text.strip_edges(), password_input.text)
	
	_show_status("Login successful!", Color.GREEN)
	login_successful.emit()
	
	await get_tree().create_timer(0.5).timeout
	_go_to_dashboard()

func _on_register_success(username: String) -> void:
	current_state = LoginState.IDLE
	_set_buttons_enabled(true)
	
	_show_status("Account created!", Color.GREEN)
	registration_successful.emit()
	
	await get_tree().create_timer(0.5).timeout
	_go_to_dashboard()

func _on_login_error(error_message: String) -> void:
	current_state = LoginState.ERROR
	_show_status(error_message, Color.RED)
	_set_buttons_enabled(true)

func _show_status(message: String, color: Color) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", color)
	status_label.visible = true

func _clear_status() -> void:
	status_label.text = ""
	status_label.visible = false

func _set_buttons_enabled(enabled: bool) -> void:
	login_button.disabled = not enabled
	register_button.disabled = not enabled
	guest_button.disabled = not enabled
	toggle_mode_button.disabled = not enabled

func _go_to_dashboard() -> void:
	if has_node("/root/SceneTransition"):
		SceneTransition.change_scene("res://scenes/dashboard/dashboard.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/dashboard/dashboard.tscn")

func _save_login(email: String, password: String) -> void:
	var file = FileAccess.open(SAVED_LOGIN_PATH, FileAccess.WRITE)
	if file:
		var data = {
			"email": email,
			"password": password
		}
		file.store_string(JSON.stringify(data))
		file.close()

func _load_saved_login() -> Variant:
	if not FileAccess.file_exists(SAVED_LOGIN_PATH):
		return null
	var file = FileAccess.open(SAVED_LOGIN_PATH, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		file.close()
		var json = JSON.new()
		if json.parse(content) == OK:
			return json.data
	return null

func _clear_saved_login() -> void:
	if FileAccess.file_exists(SAVED_LOGIN_PATH):
		DirAccess.remove_absolute(SAVED_LOGIN_PATH)

func _auto_login(email: String, password: String) -> void:
	current_state = LoginState.LOGGING_IN
	_set_buttons_enabled(false)
	
	if has_node("/root/AccountManager"):
		var account_mgr = get_node("/root/AccountManager")
		account_mgr.login_success.connect(_on_auto_login_success, CONNECT_ONE_SHOT)
		account_mgr.login_failed.connect(_on_auto_login_failed, CONNECT_ONE_SHOT)
		account_mgr.login(email, password)
	else:
		await get_tree().create_timer(0.5).timeout
		_on_auto_login_success(email)

func _on_auto_login_success(username: String) -> void:
	current_state = LoginState.IDLE
	_show_status("Welcome back, " + username + "!", Color.GREEN)
	login_successful.emit()
	await get_tree().create_timer(0.5).timeout
	_go_to_dashboard()

func _on_auto_login_failed(error_message: String) -> void:
	# Clear saved login since it failed
	_clear_saved_login()
	current_state = LoginState.IDLE
	login_panel.visible = true
	_show_status("Saved login expired. Please login again.", Color.YELLOW)
	_set_buttons_enabled(true)
	email_input.grab_focus()
