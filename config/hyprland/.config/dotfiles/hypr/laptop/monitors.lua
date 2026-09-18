-- Laptop displays.
--
-- This profile still carries Omarchy's defaults: the built-in panel is configured from
-- its preferred mode and Hyprland derives the scale from its DPI. Replace the call
-- below once the laptop's output name and modes are known; list them on that machine
-- with `hyprctl monitors all`.
--
-- GDK_SCALE is read when Hyprland starts, so changing it needs a new session rather
-- than a reload.

hl.env("GDK_SCALE", "2")
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
