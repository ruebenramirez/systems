{
  description = "Neovim configuration for note-taking";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        mkNeovim = { notesDir ? "$HOME/Sync/notes" }: pkgs.neovim.override {
          viAlias = true;
          configure = {
            customRC = ''
              vmap <C-c> y:OSCYankVisual<cr>
              autocmd BufWritePre * :%s/\s\+$//e " Remove end of line whitespace on save
              lua << EOF
              -- Basic setup
              vim.opt.number = true
              vim.opt.expandtab = true
              vim.opt.tabstop = 2
              vim.opt.shiftwidth = 2
              vim.opt.conceallevel = 2
              vim.opt.mouse = 'a'
              vim.g.mapleader = ' '
              vim.opt.clipboard = 'unnamedplus'
              vim.opt.completeopt = 'menu,menuone,noselect'

              -- Configure nvim-cmp for completion
              local cmp = require('cmp')
              cmp.setup({
                mapping = cmp.mapping.preset.insert({
                  ['<C-Space>'] = cmp.mapping.complete(),
                  ['<C-e>'] = cmp.mapping.abort(),
                  ['<CR>'] = cmp.mapping.confirm({ select = true }),
                  ['<Tab>'] = cmp.mapping.select_next_item(),
                  ['<S-Tab>'] = cmp.mapping.select_prev_item(),
                }),
                sources = cmp.config.sources({
                  { name = 'buffer' },
                  { name = 'path' },
                })
              })

              -- Telescope setup
              local telescope = require('telescope')
              telescope.setup({
                defaults = {
                  file_ignore_patterns = { "node_modules", ".git" }
                }
              })

              -- Telescope keymaps
              local telescope_builtin = require('telescope.builtin')
              vim.keymap.set('n', '<leader>ff', telescope_builtin.find_files, {})
              vim.keymap.set('n', '<leader>fg', telescope_builtin.live_grep, {})
              vim.keymap.set('n', '<leader>fb', telescope_builtin.buffers, {})

              -- Obsidian setup
              require('obsidian').setup({
                dir = "${notesDir}",
                completion = {
                  nvim_cmp = true,
                  min_chars = 2,
                },
                daily_notes = {
                  date_format = "%Y-%m-%d"
                },
                templates = {
                  subdir = "Templates",
                  date_format = "%Y-%m-%d",
                  time_format = "%H:%M",
                },
                note_frontmatter_func = function(note)
                  local out = {
                    id = note.id,
                    date = os.date("%Y-%m-%d"),
                  }
                  if note.title ~= nil then
                    out.title = note.title
                  end
                  return out
                end,
                -- Optional, customize how note IDs are generated given an optional title.
                ---@param title string|?
                ---@return string
                note_id_func = function(title)
                  -- Create note IDs in a Zettelkasten format with a timestamp and a suffix.
                  -- In this case a note with the title 'My new note' will be given an ID that looks
                  -- like '1657296016-my-new-note', and therefore the file name '1657296016-my-new-note.md'
                  local suffix = ""
                  if title ~= nil then
                    -- If title is given, transform it into valid file name.
                    suffix = title:gsub(" ", "-"):gsub("[^A-Za-z0-9-]", ""):lower()
                  else
                    -- If title is nil, just add 4 random uppercase letters to the suffix.
                    for _ = 1, 4 do
                      suffix = suffix .. string.char(math.random(65, 90))
                    end
                  end
                  return tostring(os.time()) .. "-" .. suffix
                end,
              })


              -- Obsidian keymaps
              vim.keymap.set('n', '<leader>on', ':ObsidianNew<CR>', { noremap = true, silent = true })
              vim.keymap.set('n', '<leader>of', ':ObsidianFollowLink<CR>', { noremap = true, silent = true })
              vim.keymap.set('n', '<leader>ob', ':ObsidianBacklinks<CR>', { noremap = true, silent = true })
              vim.keymap.set('n', '<leader>ot', ':ObsidianToday<CR>', { noremap = true, silent = true })
              vim.keymap.set('n', '<leader>oy', ':ObsidianYesterday<CR>', { noremap = true, silent = true })
              vim.keymap.set('n', '<leader>os', ':ObsidianSearch<CR>', { noremap = true, silent = true })

              -- TreeSitter setup with parser_install_dir explicitly set to nil
              -- to use the pre-compiled parsers
              require('nvim-treesitter.configs').setup({
                parser_install_dir = nil,
                highlight = {
                  enable = true,
                },
              })

              -- Set up markdown concealing
              vim.opt.conceallevel = 2
              vim.g.markdown_recommended_style = 0

              -- Set filetype for .md files
              vim.api.nvim_create_autocmd({"BufEnter", "BufWinEnter"}, {
                pattern = {"*.md"},
                command = "set filetype=markdown"
              })
              EOF
            '';

            packages.myVimPackage = with pkgs.vimPlugins; {
              start = [
                # Essential plugins
                vim-tmux-navigator
                plenary-nvim
                telescope-nvim
                vim-oscyank

                # Pre-compiled treesitter with parsers
                (nvim-treesitter.withPlugins (plugins: with plugins; [
                  lua
                  vim
                  markdown
                  markdown_inline
                ]))

                # Completion
                nvim-cmp
                cmp-buffer
                cmp-path

                # Obsidian integration
                obsidian-nvim

                # Theme
                tokyonight-nvim
              ];
            };
          };
        };

        defaultNeovim = mkNeovim {};
      in
      {
        packages.default = defaultNeovim;
        lib.mkNeovim = mkNeovim;

        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            defaultNeovim
            ripgrep  # For telescope live grep
            fd       # Better file finding
          ];
        };
      }
    );
}
