local theme = require("config.theme")

return {
  {
    "neanias/everforest-nvim",
    priority = 1000,
    main = "everforest",
    opts = {
      background = theme.background,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = theme.colorscheme,
    },
  },
}
