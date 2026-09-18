-- PC displays: one Gigabyte MO27Q2 QD-OLED on DP-1.
--
-- The mode is pinned rather than left to "preferred" because this monitor's EDID
-- advertises 2560x1440@59.95 as its preferred timing and keeps the 240 Hz mode in a
-- DisplayID extension block. "preferred" therefore selects 60 Hz on a 240 Hz panel.
--
-- GDK_SCALE is read when Hyprland starts, so changing it needs a new session rather
-- than a reload.

hl.env("GDK_SCALE", "1")
hl.monitor({ output = "DP-1", mode = "2560x1440@240", position = "0x0", scale = 1.25 })
