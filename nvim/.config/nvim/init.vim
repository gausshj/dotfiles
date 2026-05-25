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

let s:plug_path = stdpath('data') . '/site/autoload/plug.vim'
if filereadable(s:plug_path)
  call plug#begin('~/.vim/plugged')

  Plug 'sheerun/vim-polyglot'
  Plug 'preservim/nerdtree'
  Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
  Plug 'junegunn/fzf.vim'
  Plug 'jiangmiao/auto-pairs'
  Plug 'tpope/vim-fugitive'
  Plug 'morhetz/gruvbox'
  Plug 'vim-airline/vim-airline'
  Plug 'lukas-reineke/indent-blankline.nvim'
  Plug 'nvim-lua/plenary.nvim'
  Plug 'nvim-telescope/telescope.nvim', { 'tag': '0.1.8' }
  Plug 'williamboman/mason.nvim'
  Plug 'williamboman/mason-lspconfig.nvim'
  Plug 'neovim/nvim-lspconfig', { 'tag': 'v1.8.0' }
  Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
  Plug 'romgrk/barbar.nvim'
  Plug 'nvim-tree/nvim-web-devicons'
  Plug 'petertriho/nvim-scrollbar'

  call plug#end()
else
  echohl WarningMsg
  echom 'vim-plug is not installed. Run ~/.dotfiles/bootstrap.sh or install plug.vim, then run :PlugInstall.'
  echohl None
endif

if filereadable(expand("~/.vim/plugged/gruvbox/colors/gruvbox.vim"))
  colorscheme gruvbox
endif

lua << EOF
local ok, ibl = pcall(require, "ibl")
if ok then
ibl.setup {
  indent = { char = "│" },
  scope = { enabled = true },
}
end
EOF

lua << EOF
local ok, treesitter = pcall(require, "nvim-treesitter.configs")
if ok then
treesitter.setup {
  ensure_installed = { "python", "cpp", "c", "bash", "json", "lua", "vim" },
  highlight = {
    enable = true,
    additional_vim_regex_highlighting = false,
  },
}
end
EOF

lua << EOF
local ok_mason, mason = pcall(require, "mason")
local ok_mason_lsp, mason_lspconfig = pcall(require, "mason-lspconfig")
local ok_lsp, lspconfig = pcall(require, "lspconfig")
if ok_mason then
mason.setup()
end
if ok_mason_lsp then
mason_lspconfig.setup({})
end
if ok_lsp then
if vim.fn.executable("pyright-langserver") == 1 then
lspconfig.pyright.setup({})
end
if vim.fn.executable("clangd") == 1 then
lspconfig.clangd.setup({})
end
end
EOF

lua << EOF
vim.g.barbar_auto_setup = false
local ok, barbar = pcall(require, "barbar")
if ok then
barbar.setup({
  animation = true,
  auto_hide = false,
  tabpages = true,
  clickable = true,
})
end
EOF

lua << EOF
local ok, scrollbar = pcall(require, "scrollbar")
if ok then
scrollbar.setup()
end
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
