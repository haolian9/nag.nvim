an example of narrow region implementation for nvim

## feature/limits
* aimed to selection lines, not range
* no nested nag
* only one nag for one buffer
* hard to properly maintain the original buffer's &modifiable, so let user concern it
* no syntax/filetype nor treesitter/lsp support
* diff+patch

## status
* just work

## prerequisites
* linux
* nvim 0.11.*
* haolian9/infra.nvim

## usage
* select text then `:lua require'nag'()` or `nag(nil, open_mode: 'tab'|'right'|'left'|'above'|'below')`
* an example for adding a usercmd, requiring haolian9/cmds.nvim
```
do --:Nag
  local function action(args) require("nag")(0, args.open) end
  local comp = cmds.ArgComp.constant({ "tab", "left", "right", "above", "below" })

  local spell = cmds.Spell("Nag", action)
  spell:enable("range")
  spell:add_arg("open", "string", false, "tab", comp)
  cmds.cast(spell)
end
```

## thanks
* NrrwRgn.vim, my good old friend, the one inspired this plugin.
