syntax on
set nu
set whichwrap+=<,>,h,l
set tabstop=4
set shiftwidth=4
set expandtab
set autoindent
set cindent
set list lcs=tab:\|\
set cc=80
set cursorline
set background=dark

filetype plugin indent on

call plug#begin('~/.vim/plugged')

Plug 'sheerun/vim-polyglot'
Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'preservim/nerdtree'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'jiangmiao/auto-pairs'
Plug 'tpope/vim-fugitive'
Plug 'morhetz/gruvbox'
Plug 'vim-airline/vim-airline'
Plug 'lukas-reineke/indent-blankline.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim'
Plug 'williamboman/mason.nvim'
Plug 'williamboman/mason-lspconfig.nvim'
Plug 'neovim/nvim-lspconfig'
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
Plug 'stevearc/conform.nvim'
Plug 'romgrk/barbar.nvim'
Plug 'nvim-tree/nvim-web-devicons'
Plug 'petertriho/nvim-scrollbar'

call plug#end()

if filereadable(expand("~/.vim/plugged/gruvbox/colors/gruvbox.vim"))
  colorscheme gruvbox
endif

lua << EOF
require("ibl").setup {
  indent = { char = "│" },
  scope = { enabled = true },
}
EOF

lua << EOF
require("nvim-treesitter.configs").setup {
  ensure_installed = { "python", "cpp", "c", "bash", "json", "lua", "vim" },
  highlight = {
    enable = true,
    additional_vim_regex_highlighting = false,
  },
}
EOF

lua << EOF
require("mason").setup()
require("mason-lspconfig").setup {
  ensure_installed = { "pyright", "clangd" }
}
local lspconfig = require("lspconfig")
lspconfig.pyright.setup({})
lspconfig.clangd.setup({})
EOF

lua << EOF
require("conform").setup({
  format_on_save = {
    timeout_ms = 500,
    lsp_fallback = true,
  },
})
EOF

lua << EOF
vim.g.barbar_auto_setup = false
require("barbar").setup({
  animation = true,
  auto_hide = false,
  tabpages = true,
  clickable = true,
})
EOF

lua << EOF
require("scrollbar").setup()
EOF


let mapleader = " "
nnoremap <C-n> :NERDTreeToggle<CR>
nnoremap <C-f> <cmd>Telescope current_buffer_fuzzy_find<CR>
nnoremap <C-p>f <cmd>Telescope find_files<CR>
noremap <C-l> :BufferNext<CR>
noremap <C-S-l> :BufferPrevious<CR>
noremap <C-z> u
noremap <C-w> :bd<CR>
nnoremap <C-p>g <cmd>Telescope live_grep<CR>
nnoremap <C-p>b <cmd>Telescope buffers<CR>
noremap <C-s> :w<CR>
inoremap <C-s> <Esc>:w<CR>gi
vnoremap <C-s> <Esc>:w<CR>gv
cnoremap <C-s> <C-c>:w<CR>
noremap <C-q> :q<CR>


inoremap <silent><expr> <TAB> pumvisible() ? "\<C-n>" : "\<TAB>"
inoremap <silent><expr> <S-TAB> pumvisible() ? "\<C-p>" : "\<S-TAB>"
