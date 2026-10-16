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
    branch = "master",   -- pin to the classic API; `main` is a rewrite without nvim-treesitter.configs
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = { "c", "lua", "vim", "vimdoc", "python", "javascript", "html", "typescript", "rust", "kotlin", "java", "markdown", "markdown_inline" },  -- add languages you need
        sync_install = false,
        highlight = { enable = true, additional_vim_regex_highlighting = false },
        indent    = { enable = true },
      })
      if vim.fn.has("nvim-0.12") == 1 then
        -- The classic plugin uses all=false, removed in 0.12: captures are now node lists.
        require("nvim-treesitter.query_predicates")
        vim.treesitter.query.add_directive("set-lang-from-info-string!", function(match, _, bufnr, pred, metadata)
          local nodes = match[pred[2]]
          local node = nodes and nodes[1]
          if not node then
            return
          end
          local language = vim.treesitter.get_node_text(node, bufnr):lower()
          local aliases = { ex = "elixir", pl = "perl", sh = "bash", uxn = "uxntal", ts = "typescript" }
          metadata["injection.language"] = vim.filetype.match({ filename = "a." .. language })
            or aliases[language] or language
        end, { force = true })
      end
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
            -- Diffview fills revision buffers asynchronously; render after entering the window.
            vim.defer_fn(function()
              if not vim.api.nvim_buf_is_valid(bufnr)
                or not vim.api.nvim_win_is_valid(winid)
                or vim.api.nvim_win_get_buf(winid) ~= bufnr then
                return
              end
              local markdown = require("render-markdown")
              -- New revision buffers should inherit the current toggle state, including off.
              markdown.set(markdown.get())
            end, 150)
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
