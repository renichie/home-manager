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
      -- better_performance caches after/syntax in the plugin dir, falling back
      -- to stdpath("config"). In the agent sandbox both are read-only binds,
      -- which makes the colorscheme abort with E739, so only enable it when
      -- the config dir is writable.
      vim.g.gruvbox_material_better_performance =
        vim.fn.filewritable(vim.fn.stdpath("config")) == 2 and 1 or 0

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
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      local treesitter = require("nvim-treesitter")
      local parsers = { "c", "lua", "vim", "vimdoc", "python", "javascript", "html", "typescript", "rust", "kotlin", "java", "markdown", "markdown_inline" }
      treesitter.setup({})

      local function enable_treesitter(bufnr)
        local language = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
        if not language or not vim.list_contains(treesitter.get_installed("parsers"), language) then
          return
        end
        vim.treesitter.start(bufnr, language)
        if vim.treesitter.query.get(language, "indents") then
          vim.bo[bufnr].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("TreesitterFeatures", { clear = true }),
        callback = function(event)
          enable_treesitter(event.buf)
        end,
      })
      -- Install missing parsers without blocking startup; attach already opened buffers afterwards.
      treesitter.install(parsers):await(vim.schedule_wrap(function(err)
        if err then
          vim.notify(tostring(err), vim.log.levels.ERROR)
          return
        end
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(bufnr) then
            enable_treesitter(bufnr)
          end
        end
      end))
    end,
  },
  {
    "allaman/emoji.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim"
    },
    opts = {},
    config = function(_, opts)
      require("emoji").setup(opts)
      local emoji_picker = require("telescope").load_extension("emoji")
      vim.keymap.set("n", "<leader>se", emoji_picker.emoji, { desc = "Search emoji" })
    end,
  },
  {
    "MeanderingProgrammer/render-markdown.nvim",
    lazy = false,  -- load at startup, not only when the toggle key is pressed
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
      enabled = true,
      render = { diff = true },  -- also render Markdown in Diffview windows
      debounce = 0,  -- do not drop render events while Diffview creates and displays its buffers
    },
    keys = {
      { "<leader>mr", "<cmd>RenderMarkdown toggle<cr>", desc = "Toggle Markdown rendering" },
    },
  },
  {
    "sindrets/diffview.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles", "DiffviewFocusFiles", "DiffviewRefresh" },
    opts = {
      use_icons = false,
      hooks = {
        diff_buf_win_enter = function(bufnr, winid)
          if vim.bo[bufnr].filetype == "markdown" then
            vim.wo[winid].foldenable = false
            local markdown = require("render-markdown")
            -- Revision buffers inherit the current rendering toggle, including off.
            markdown.set(markdown.get())
          end
        end,
      },
    },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Open Git diff" },
      { "<leader>gq", "<cmd>DiffviewClose<cr>", desc = "Close Git diff" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "Current file history" },
    },
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
