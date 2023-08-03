-- nag -> NArrow reGion
--
-- inspirated by NrrwRgn.vim
--
-- features/limits
-- * aimed to selection lines, not range
-- * no nested nag
-- * only one nag for one buffer
-- * hard to properly maintain the original buffer's &modifiable, so let user concern it
-- * no syntax/filetype nor treesitter/lsp support at now
--

local M = {}

local api = vim.api

local bufrename = require("infra.bufrename")
local ctx = require("infra.ctx")
local ex = require("infra.ex")
local jelly = require("infra.jellyfish")("nag")
local prefer = require("infra.prefer")
local strlib = require("infra.strlib")
local sync = require("infra.sync_primitives")
local vsel = require("infra.vsel")

local launch
do
  local function make_nag_name(bufname, start, stop) return string.format("nag://%s@%s~%s", vim.fn.fnamemodify(bufname, ":t"), start, stop) end

  local function is_valid_nag_buf(bufname) return strlib.startswith(bufname, "nag://") end

  function launch(src_win_id, src_bufnr, edit_cmd)
    assert(src_win_id and src_bufnr and edit_cmd)

    local origin_state, selines
    do
      local bufname = api.nvim_buf_get_name(src_bufnr)
      if is_valid_nag_buf(bufname) then return jelly.warn("nag on nag") end

      local range = vsel.range(src_bufnr)
      if range == nil then return jelly.warn("no selection") end

      origin_state = {
        winid = src_win_id,
        bufnr = src_bufnr,
        name = bufname,
        start_line = range.start_line,
        stop_line = range.stop_line,
      }

      selines = vsel.multiline_text(origin_state.bufnr)
      if selines == nil then return end
    end

    local nag_bufnr
    do -- setup nag buf
      nag_bufnr = api.nvim_create_buf(false, true)

      local bo = prefer.buf(nag_bufnr)
      bo.buftype = "nofile"
      bo.bufhidden = "wipe"

      local mux = sync.create_buf_mutex(origin_state.bufnr, "nag")
      if not mux:acquire() then return jelly.warn("nag is running already") end
      local tick0 = api.nvim_buf_get_changedtick(nag_bufnr)

      api.nvim_create_autocmd("bufwipeout", {
        buffer = nag_bufnr,
        once = true,
        callback = function()
          mux:release()
          if not api.nvim_buf_is_valid(origin_state.bufnr) then return jelly.warn("original buf#%d was gone", origin_state.bufnr) end
          --determining &modified base on changedtick is not accurate, yet it's still good enough.
          if api.nvim_buf_get_changedtick(nag_bufnr) == tick0 then return jelly.debug("nag buf has not been modified") end
          local ok, err = xpcall(function()
            local lines = api.nvim_buf_get_lines(nag_bufnr, 0, -1, true)
            api.nvim_buf_set_lines(origin_state.bufnr, origin_state.start_line, origin_state.stop_line, false, lines)
          end, debug.traceback)
          if not ok then jelly.error(err) end
        end,
      })

      ctx.no_undo(bo, function() api.nvim_buf_set_lines(nag_bufnr, 0, #selines, false, selines) end)
    end

    local nag_bufname
    do
      nag_bufname = make_nag_name(origin_state.name, origin_state.start_line, origin_state.stop_line)
      bufrename(nag_bufnr, nag_bufname)
    end

    do -- setup nag window
      ex(edit_cmd, nag_bufname)
      local nag_winid = api.nvim_get_current_win()
      assert(nag_winid ~= origin_state.winid)
      api.nvim_win_set_buf(nag_winid, nag_bufnr)
    end
  end
end

do
  local function launcher(edit_cmd)
    return function()
      local winid = api.nvim_get_current_win()
      local bufnr = api.nvim_win_get_buf(winid)
      launch(winid, bufnr, edit_cmd)
    end
  end

  M.tab = launcher("tabe")
  M.split = launcher("split")
  M.vsplit = launcher("vsplit")
end

return M
