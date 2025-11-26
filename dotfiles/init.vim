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
