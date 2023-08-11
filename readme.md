an example of narrow region implementation for nvim

## feature/limits
* aimed to selection lines, not range
* no nested nag
* only one nag for one buffer
* hard to properly maintain the original buffer's &modifiable, so let user concern it
* no syntax/filetype nor treesitter/lsp support
* diff+patch

## status
* it just work (tm)

## prerequisites
* linux
* nvim 0.9.*
* haolian9/infra.nvim

## usage
* select text then `:lua require'nag'.vsplit()`

## thanks
* NrrwRgn.vim was my good old friend, and is the one that inspired this plugin.
