lua << EOF
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({

  -- Gruvbox Material theme
  {
    "sainnhe/gruvbox-material",
    config = function()
      -- Theme options (see plugin README for more)
      vim.o.background = "dark"                 -- or "light"
      vim.g.gruvbox_material_background = "medium"  -- "hard", "medium", "soft"
      vim.g.gruvbox_material_enable_italic = 1
      vim.g.gruvbox_material_better_performance = 1

      vim.cmd("colorscheme gruvbox-material")
    end,
  },

  -- vim-polyglot (syntax & filetype support for many languages)
  {
    "sheerun/vim-polyglot",
    lazy = false,   -- load immediately (optional — can omit)
  },

  -- nvim-treesitter (better syntax highlighting / parsing)
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = { "c", "lua", "vim", "vimdoc", "python", "javascript", "html", "typescript", "rust", "kotlin", "java" },  -- add languages you need
        sync_install = false,
        highlight = { enable = true, additional_vim_regex_highlighting = false },
        indent    = { enable = true },
      })
    end,
  },
  {
    "allaman/emoji.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim"
    },
    config = function()
      -- basic setup, no extras
      require("emoji").setup({})
    end,
  },
})

EOF


set noswapfile
set number
set mouse=a
syntax on
set clipboard=unnamedplus
set tabstop=4
set ai "setzt autoindent
set si "setzt smart indent

nnoremap j h
nnoremap k j
nnoremap l k
nnoremap ö l
nnoremap ; l

vnoremap j h
vnoremap k j
vnoremap l k
vnoremap ö l
vnoremap ; l
