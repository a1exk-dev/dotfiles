-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Discord runs natively on Wayland, where its keybind recorder sees no keys.
-- In Discord, turn Ctrl+M into its built-in Toggle Mute (Ctrl+Shift+M); every
-- other window still receives Ctrl+M. Down/up split as in Omarchy's clipboard.lua.
local function send_shortcut_once(mods, key)
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
  end, { timeout = 50, type = "oneshot" })
end

o.bind("CTRL + M", "Discord toggle mute", function()
  local window = hl.get_active_window()
  if window and window.class == "discord" then
    send_shortcut_once("CTRL + SHIFT", "M")
  else
    send_shortcut_once("CTRL", "M")
  end
end)

-- Hotkeys that only one machine's hardware justifies belong to its machine profile.
-- Choose one with: bin/dotfiles --action hypr-profile
require("default.hypr.require_optional").module("hypr.machine.bindings")
