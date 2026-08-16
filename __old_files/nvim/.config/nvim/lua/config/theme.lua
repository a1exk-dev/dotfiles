local config_home = vim.env.XDG_CONFIG_HOME
if not config_home or config_home == "" then
  config_home = vim.env.HOME .. "/.config"
end

return dofile(config_home .. "/dotfiles-theme/current/.config/nvim/theme.lua")
