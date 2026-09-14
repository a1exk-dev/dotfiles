-- US stays first so Omarchy bindings continue to resolve Latin keysyms.
-- Left Alt + Right Alt switches layouts, as in Omarchy's input.lua template.
hl.config({
  input = {
    kb_layout = "us,ru",
    kb_variant = ",",
    kb_options = "compose:caps,shift:both_capslock_cancel,grp:alts_toggle",
  },
})

-- App-specific touchpad scroll speeds.
-- o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })
-- o.window("com.mitchellh.ghostty", { scroll_touchpad = 0.2 })

-- Enable touchpad gestures for changing workspaces.
-- hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
