{ config, pkgs, pkgs-unstable, ... }:

{
  environment.systemPackages = with pkgs; [
    # Core development tools
    git
    # Search and navigation tools - required for telescope-nvim
    ripgrep      # for live_grep and grep_string
    fd           # faster find alternative for find_files
    # Language servers
    nil          # Nix language server
    nodejs       # required for some language servers and firenvim
    manix        # Nix documentation tool
  ];

  environment.variables = {
    EDITOR = "nvim";
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    configure = {
      packages.myVimPackage = with pkgs.vimPlugins; {
        start = [
          # Core plugins
          (nvim-treesitter.withAllGrammars)
          nvim-lspconfig
          nvim-web-devicons

          # Completion framework
          nvim-cmp
          cmp-nvim-lsp
          cmp-path
          cmp-buffer  # Added for buffer completions

          # Navigation and search
          telescope-nvim
          telescope-manix

          # Git integration
          gitsigns-nvim

          # File management and editing
          vim-commentary
          vim-tmux-navigator
          vim-oscyank

          # Additional utilities
          tagbar
          vim-dirdiff
          vim-endwise
          vim-nix

          # Theme
          tokyonight-nvim
        ];
      };
      customRC = ''
        " ========================================
        " BASIC VIM SETTINGS
        " ========================================
        set background=light
        set number
        set cursorline
        set signcolumn=yes       " Always show sign column to avoid layout shift
        set clipboard=unnamedplus " Use system clipboard
        set splitbelow          " Split windows below current
        set splitright          " Split windows to the right
        set updatetime=250      " Faster updates for better UX
        set timeoutlen=300      " Faster which-key
        set undofile            " Persistent undo

        " Search configuration
        set hlsearch
        set incsearch            " Incremental search
        set ignorecase
        set smartcase           " Case-sensitive when uppercase letters present

        " Indentation settings
        set expandtab
        set tabstop=4
        set shiftwidth=4
        set softtabstop=4
        set autoindent
        set smartindent

        " Visual improvements
        set colorcolumn=80
        set textwidth=80
        set scrolloff=8         " Keep 8 lines above/below cursor
        set sidescrolloff=8     " Keep 8 columns left/right of cursor

        " Disable folding
        set nofoldenable        " Disable folding completely

        " Language-specific settings
        autocmd FileType vim,go,r,R,yml,yaml,json,markdown,ruby,javascript,Rakefile
          \ setlocal shiftwidth=2 tabstop=2 softtabstop=2
        autocmd FileType python
          \ setlocal shiftwidth=4 tabstop=4 softtabstop=4
        autocmd FileType *.nix,nix
          \ setlocal shiftwidth=2 tabstop=2 softtabstop=2 textwidth=0 formatoptions-=t formatoptions-=c

        " Clean up whitespace on save
        autocmd BufWritePre * :%s/\s\+$//e

        " Leader key
        let mapleader=" "

        " ========================================
        " KEY MAPPINGS
        " ========================================
        " Date insertion
        nnoremap <leader>d :put =strftime('%Y-%m-%d')<CR>
        nnoremap <leader>D :put =strftime('%Y-%m-%d:%H:%M:%S')<CR>

        " Tab navigation
        noremap <leader>1 1gt
        noremap <leader>2 2gt
        noremap <leader>3 3gt
        noremap <leader>4 4gt
        noremap <leader>5 5gt
        noremap <leader>6 6gt

        " Window navigation
        nnoremap <C-J> <C-W><C-J>
        nnoremap <C-K> <C-W><C-K>
        nnoremap <C-L> <C-W><C-L>
        nnoremap <C-H> <C-W><C-H>

        " Tagbar toggle
        nmap <F8> :TagbarToggle<CR>

        " Telescope mappings
        nnoremap <leader>ff <cmd>Telescope find_files<CR>
        nnoremap <leader>fg <cmd>Telescope live_grep<CR>
        nnoremap <leader>fb <cmd>Telescope buffers<CR>
        nnoremap <leader>fh <cmd>Telescope help_tags<CR>
        nnoremap <leader>fr <cmd>Telescope oldfiles<CR>
        nnoremap <leader>fc <cmd>Telescope grep_string<CR>

        " Better indentation handling
        vnoremap < <gv
        vnoremap > >gv

        " OSC Yank for copy to system clipboard over SSH
        vmap <C-c> y:OSCYankVisual<CR>

        " Clear search highlighting
        nnoremap <Esc> :nohlsearch<CR>

        " ========================================
        " LUA CONFIGURATION
        " ========================================
        lua << EOF
        -- Set leader key early
        vim.g.mapleader = ' '
        vim.g.maplocalleader = ' '

        -- Modern completion options
        vim.opt.completeopt = {'menu', 'menuone', 'noselect', 'noinsert'}

        -- Better shift-tab behavior for insert mode
        vim.keymap.set('i', '<S-Tab>', '<C-d>')
        vim.keymap.set('n', '<S-Tab>', '<<')
        vim.keymap.set('v', '<S-Tab>', '<gv')

        -- Highlight trailing whitespace
        vim.cmd([[
          match ExtraWhitespace /\s\+$/
          highlight ExtraWhitespace ctermbg=red guibg=red
        ]])



        -- ========================================
        -- indentation correction
        --    disable C preprocessor directive handling
        -- ========================================
        vim.opt.autoindent = true
        vim.opt.smartindent = false
        vim.opt.cindent = false
        vim.opt.indentexpr = ""


        -- ========================================
        -- TREESITTER CONFIGURATION
        -- ========================================
        require('nvim-treesitter.configs').setup {
          highlight = {
            enable = true,
            additional_vim_regex_highlighting = false,
          },
          indent = {
            enable = true
          },
          -- Incremental selection
          incremental_selection = {
            enable = true,
            keymaps = {
              init_selection = "gnn",
              node_incremental = "grn",
              scope_incremental = "grc",
              node_decremental = "grm",
            },
          },
        }

        -- ========================================
        -- TELESCOPE CONFIGURATION
        -- ========================================
        local telescope = require('telescope')
        local actions = require('telescope.actions')

        telescope.setup {
          defaults = {
            prompt_prefix = "🔍 ",
            selection_caret = "❯ ",
            file_ignore_patterns = {
              "node_modules",
              ".git/",
              "*.pyc",
              "__pycache__/",
              ".cache/"
            },
            layout_config = {
              horizontal = {
                preview_width = 0.6,
              },
              vertical = {
                mirror = false,
              },
            },
            sorting_strategy = "ascending",
            layout_strategy = "horizontal",
            mappings = {
              i = {
                ["<A-j>"] = actions.move_selection_next,
                ["<A-k>"] = actions.move_selection_previous,
                ["<A-q>"] = actions.send_to_qflist + actions.open_qflist,
                ["<A-x>"] = actions.select_horizontal,
                ["<A-v>"] = actions.select_vertical,
                ["<A-t>"] = actions.select_tab,
                ["<A-u>"] = actions.preview_scrolling_up,
                ["<A-d>"] = actions.preview_scrolling_down,
              },
              n = {
                ["<A-j>"] = actions.move_selection_next,
                ["<A-k>"] = actions.move_selection_previous,
                ["<A-q>"] = actions.send_to_qflist + actions.open_qflist,
                ["<A-x>"] = actions.select_horizontal,
                ["<A-v>"] = actions.select_vertical,
                ["<A-t>"] = actions.select_tab,
              },
            },
          },
          pickers = {
            find_files = {
              hidden = true,
              find_command = { "rg", "--files", "--hidden", "--glob", "!**/.git/*" },
            },
            live_grep = {
              additional_args = function()
                return {"--hidden"}
              end
            },
            buffers = {
              previewer = false,
              layout_config = { width = 80 },
            },
          },
        }

        -- Load telescope extensions
        telescope.load_extension('manix')

        -- ========================================
        -- GITSIGNS CONFIGURATION
        -- ========================================
        require('gitsigns').setup {
          signs = {
            add          = { text = '+' },
            change       = { text = '~' },
            delete       = { text = '_' },
            topdelete    = { text = '‾' },
            changedelete = { text = '~' },
          },
          current_line_blame = true,
          current_line_blame_opts = {
            virt_text = true,
            virt_text_pos = 'eol',
            delay = 300,
          },
        }

        -- ========================================
        -- LSP CONFIGURATION
        -- ========================================
        local lspconfig = require('lspconfig')

        -- Enhanced capabilities with nvim-cmp
        local capabilities = require('cmp_nvim_lsp').default_capabilities()
        capabilities.textDocument.completion.completionItem.snippetSupport = true

        -- Global diagnostic configuration
        vim.diagnostic.config({
          virtual_text = {
            prefix = '●',
            source = "if_many",
          },
          signs = true,
          underline = true,
          update_in_insert = false,
          severity_sort = true,
          float = {
            focusable = false,
            style = "minimal",
            border = "rounded",
            source = "always",
            header = "",
            prefix = "",
          },
        })

        -- LSP keymaps (applied when LSP attaches)
        local on_attach = function(client, bufnr)
          local opts = { noremap = true, silent = true, buffer = bufnr }

          vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, opts)
          vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
          vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
          vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
          -- vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, opts)
          vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
          vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, opts)
          vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
          vim.keymap.set('n', '<leader>f', function()
            vim.lsp.buf.format { async = true }
          end, opts)
        end

        -- Setup Nix language server
        lspconfig.nil_ls.setup {
          capabilities = capabilities,
          on_attach = on_attach,
          settings = {
            ['nil'] = {
              formatting = {
                command = { "nixfmt" },
              },
            },
          },
        }

        -- ========================================
        -- NVIM-CMP CONFIGURATION
        -- ========================================
        local cmp = require('cmp')

        cmp.setup {
          snippet = {
            expand = function(args)
              -- Using Neovim's native snippet support (0.10+)
              vim.snippet.expand(args.body)
            end,
          },
          sources = cmp.config.sources({
            { name = 'nvim_lsp', priority = 1000 },
            { name = 'path', priority = 750 },
          }, {
            { name = 'buffer', priority = 500, keyword_length = 3 },
          }),
          formatting = {
            fields = { 'kind', 'abbr', 'menu' },
            format = function(entry, vim_item)
              local kind_icons = {
                Text = "",
                Method = "󰆧",
                Function = "󰊕",
                Constructor = "",
                Field = "󰇽",
                Variable = "󰂡",
                Class = "󰠱",
                Interface = "",
                Module = "",
                Property = "󰜢",
                Unit = "",
                Value = "󰎠",
                Enum = "",
                Keyword = "󰌋",
                Snippet = "",
                Color = "󰏘",
                File = "󰈙",
                Reference = "",
                Folder = "󰉋",
                EnumMember = "",
                Constant = "󰏿",
                Struct = "",
                Event = "",
                Operator = "󰆕",
                TypeParameter = "󰅲",
              }

              vim_item.kind = string.format('%s %s', kind_icons[vim_item.kind], vim_item.kind)
              vim_item.menu = ({
                nvim_lsp = "[LSP]",
                path = "[Path]",
                buffer = "[Buffer]",
              })[entry.source.name]

              return vim_item
            end
          },
          window = {
            completion = cmp.config.window.bordered(),
            documentation = cmp.config.window.bordered(),
          },
          mapping = cmp.mapping.preset.insert({
            -- Navigation
            ['<C-k>'] = cmp.mapping.select_prev_item(),
            ['<C-j>'] = cmp.mapping.select_next_item(),
            ['<C-b>'] = cmp.mapping.scroll_docs(-4),
            ['<C-f>'] = cmp.mapping.scroll_docs(4),

            -- Completion control
            ['<C-Space>'] = cmp.mapping.complete(),
            ['<C-e>'] = cmp.mapping.abort(),

            -- Confirm selection
            ['<CR>'] = cmp.mapping.confirm({
              behavior = cmp.ConfirmBehavior.Replace,
              select = false
            }),

            -- Tab/Shift-Tab for navigation
            ['<Tab>'] = cmp.mapping(function(fallback)
              if cmp.visible() then
                cmp.select_next_item()
              else
                fallback()
              end
            end, { 'i', 's' }),

            ['<S-Tab>'] = cmp.mapping(function(fallback)
              if cmp.visible() then
                cmp.select_prev_item()
              else
                fallback()
              end
            end, { 'i', 's' }),
          }),
          experimental = {
            ghost_text = {
              hl_group = "CmpGhostText",
            },
          },
        }

        -- Command-line completion
        cmp.setup.cmdline({ '/', '?' }, {
          mapping = cmp.mapping.preset.cmdline(),
          sources = {
            { name = 'buffer' }
          }
        })

        cmp.setup.cmdline(':', {
          mapping = cmp.mapping.preset.cmdline(),
          sources = cmp.config.sources({
            { name = 'path' }
          }, {
            { name = 'cmdline' }
          })
        })

        -- ========================================
        -- AUTOCOMMANDS
        -- ========================================

        -- Highlight on yank
        vim.api.nvim_create_autocmd('TextYankPost', {
          callback = function()
            vim.highlight.on_yank()
          end,
        })

        -- Auto-format on save for Nix files
        vim.api.nvim_create_autocmd('BufWritePre', {
          pattern = '*.nix',
          callback = function()
            vim.lsp.buf.format({ async = false })
          end,
        })

        -- Close some filetypes with <q>
        vim.api.nvim_create_autocmd('FileType', {
          pattern = {
            'qf',
            'help',
            'man',
            'notify',
            'lspinfo',
            'spectre_panel',
            'startuptime',
            'tsplayground',
            'PlenaryTestPopup',
          },
          callback = function(event)
            vim.bo[event.buf].buflisted = false
            vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = event.buf, silent = true })
          end,
        })

        EOF
      '';
    };
  };
}
