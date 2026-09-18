-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all
--
-- Displays belong to the selected machine profile. Choose one with:
--   bin/dotfiles --action hypr-profile
--
-- Omarchy's defaults below apply until a profile is selected, so applying this
-- package on its own changes no display behavior.

local machine = "hypr.machine.monitors"

if package.searchpath(machine, package.path) then
  require(machine)
else
  hl.env("GDK_SCALE", "2")
  hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
end
