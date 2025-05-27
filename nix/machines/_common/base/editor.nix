{ config, pkgs, pkgs-unstable, ... }:

let

in
{

  environment.systemPackages = with pkgs; [
    # editor specific configuration
    # git is needed for gitsigns-nvim
    # ripgrep and fd are needed for telescope-nvim
    ripgrep
    git
    fd
    haskell-language-server
    # ghc, stack and cabal are required to run the language server
    stack
    ghc
    cabal-install
    manix
    nil
  ];

  environment.variables = {
    EDITOR="nvim";
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    configure = {
      packages.myVimPackage = with pkgs.vimPlugins; {
        start = [
          (nvim-treesitter.withAllGrammars)
          bufferline-nvim
          cmp-nvim-lsp
          cmp-path
          csv-vim
          gitsigns-nvim
          indent-blankline-nvim
          nerdtree
          nvim-cmp
          nvim-lspconfig
          nvim-web-devicons
          tagbar
          telescope-manix
          telescope-nvim
          vim-commentary
          vim-dirdiff
          vim-endwise
          vim-nix
          vim-oscyank
          vim-tmux-navigator
        ];
      };
      customRC = ''
        set background=light
        set cursorline " underline the line that the cursor is currently on
        set paste
        set number
        "set numberwidth=3

        " better searching
        set hlsearch " highlight search terms
        highlight! link DiffText MatchParen " Better diff highlighting
        set ignorecase " search without case sensitivity

        " indentation: use spaces instead of tabs
        set expandtab
        set tabstop=4
        set shiftwidth=4
        set softtabstop=4

        " set 2 space tabs when appropriate
        autocmd FileType vim,*.nix,nix,go,r,R,yml,yaml,json,markdown,ruby,javascript,Rakefile setlocal shiftwidth=2 tabstop=2 softtabstop=2 showtabline=2

        " set 4 space tabs when appropriate
        "autocmd FileType python,*.py.tpl setlocal tabstop=4 expandtab shiftwidth=4 softtabstop=4 showtabline=4

        autocmd BufWritePre * :%s/\s\+$//e " Remove end of line whitespace on save

        set colorcolumn=80 " visual indicator appears at this column
        set textwidth=80 " controls line wrapping

        let mapleader=" "

        " insert date
        nnoremap <leader>d :put =strftime('%Y-%m-%d')

        " insert datetime
        nnoremap <leader>D :put =strftime('%Y-%m-%d:%H:%M:%S')

        " Go to tab by number
        noremap <leader>1 1gt
        noremap <leader>2 2gt
        noremap <leader>3 3gt
        noremap <leader>4 4gt
        noremap <leader>5 5gt
        noremap <leader>6 6gt

        " navigation with control keys
        nnoremap <C-J> <C-W><C-J>
        nnoremap <C-K> <C-W><C-K>
        nnoremap <C-L> <C-W><C-L>
        nnoremap <C-H> <C-W><C-H>

        nmap <F8> :TagbarToggle<CR>

        " Configure Telescope
        " Find files using Telescope command-line sugar.
        nnoremap <leader>ff <cmd>Telescope find_files<cr>
        nnoremap <leader>fg <cmd>Telescope live_grep<cr>
        nnoremap <leader>fb <cmd>Telescope buffers<cr>
        nnoremap <leader>fh <cmd>Telescope help_tags<cr>

        vmap <C-c> y:OSCYankVisual<cr>

        nnoremap <silent><A-h> :BufferLineCyclePrev<CR>
        nnoremap <silent><A-l> :BufferLineCycleNext<CR>
        nnoremap <silent><A-c> :bdelete!<CR>

        set completeopt=menuone,noselect
        set mouse-=a
        set tw=80
        set wrap linebreak
        set number
        set signcolumn=yes:2
        set foldexpr=nvim_treesitter#foldexpr()

        augroup markdown_settings
          autocmd!
          autocmd FileType markdown setlocal formatlistpat=^\\s*\\d\\+\\.\\s\\+\\\|^\\s*[-*+]\\s\\+
          autocmd FileType markdown setlocal formatoptions+=n
          autocmd FileType markdown setlocal autoindent
        augroup END

        lua << EOF
        vim.g.mapleader = ' '

        -- shift + tab to remove one level of indentation
        -- Insert mode
        vim.keymap.set('i', '<S-Tab>', '<C-d>')
        -- Normal mode
        vim.keymap.set('n', '<S-Tab>', '<<')
        -- Visual mode
        vim.keymap.set('v', '<S-Tab>', '<gv')

        -- Telescope configuration
        local actions = require('telescope.actions')
        require('gitsigns').setup()
        require('telescope').setup {
          defaults = {
            file_ignore_patterns = { "node_modules", ".git" },
            mappings = {
              i = {
                ["<A-j>"] = actions.move_selection_next,
                ["<A-k>"] = actions.move_selection_previous
              }
            }
          }
        }

        -- Telescope keymaps
        local telescope_builtin = require('telescope.builtin')
        vim.keymap.set('n', '<leader>ff', telescope_builtin.find_files, {})
        vim.keymap.set('n', '<leader>fg', telescope_builtin.live_grep, {})
        vim.keymap.set('n', '<leader>fb', telescope_builtin.buffers, {})


        require'nvim-treesitter.configs'.setup {
          indent = {
            enable = true
          }
        }
        require('bufferline').setup {
          options = {
            show_close_icon = false,
            show_buffer_close_icons = false
          }
        }
        require("ibl").setup {}

        vim.cmd[[
          match ExtraWhitespace /\s\+$/
          highlight ExtraWhitespace ctermbg=red guibg=red
        ]]

        vim.opt.list = false

        -- LSP + nvim-cmp setup
        local lspc = require('lspconfig')
        lspc.hls.setup {}
        local cmp = require("cmp")
        cmp.setup {
          sources = {
            { name = "nvim_lsp" },
            { name = "path" },
          },
          formatting = {
            format = function(entry, vim_item)
              vim_item.menu = ({
                nvim_lsp = "[LSP]",
                path = "[Path]",
              })[entry.source.name]
              return vim_item
            end
          },
          mapping = {
            ['<Tab>'] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
            ['<S-Tab>'] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
            ['<C-b>'] = cmp.mapping.scroll_docs(-4),
            ['<C-f>'] = cmp.mapping.scroll_docs(4),
            ['<C-Space>'] = cmp.mapping.complete(),
            ['<C-e>'] = cmp.mapping.close(),
            ['<CR>'] = cmp.mapping.confirm({
              behavior = cmp.ConfirmBehavior.Replace,
              select = true,
            })
          },
        }

        local servers = { 'nil_ls' }
        for _, lsp in ipairs(servers) do
          require('lspconfig')[lsp].setup {
            capabilities = require('cmp_nvim_lsp').default_capabilities(vim.lsp.protocol.make_client_capabilities()),
            on_attach = on_attach,
          }
        end
        EOF
      '';
    };
  };
}
