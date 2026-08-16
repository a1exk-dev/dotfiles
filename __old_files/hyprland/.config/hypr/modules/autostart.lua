-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
-- Or execute your favorite apps at launch like this:
--
hl.on("hyprland.start", function()
	hl.exec_cmd("waybar")
	hl.exec_cmd("hyprpaper -c ~/.config/hypr/hyprpaper.conf")
	hl.exec_cmd("~/.config/hypr/scripts/edp-refresh-rate.sh")
	hl.exec_cmd("pgrep -x ollama >/dev/null || env OLLAMA_IGPU_ENABLE=1 ollama serve")
end)
