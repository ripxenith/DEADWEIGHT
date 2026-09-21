# ============================================================
# GAME BUTTONS
# ============================================================

func _on_host_game_pressed() -> void:
	print_debug("Host Game pressed.")

	if not SteamManager.is_ready():
		print_debug("Steam is not ready. Cannot create lobby.")
		return

	print_debug("Creating Steam lobby...")

	SteamManager.create_lobby()


func _on_join_game_pressed() -> void:
	print_debug("Join Game is handled through Steam invites.")


func _on_invite_button_pressed() -> void:
	print_debug("Invite button pressed.")

	if not SteamManager.is_ready():
		print_debug("Steam is not ready.")
		return

	if SteamManager.lobby_id <= 0:
		print_debug("No Steam lobby exists yet.")
		return

	# Opens Steam's overlay to invite friends to the lobby.
	Steam.activateGameOverlayInviteDialog(
		SteamManager.lobby_id
	)


func _on_quit_pressed() -> void:
	print_debug("Quit pressed.")
	get_tree().quit()
