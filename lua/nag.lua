-- nag -> NArrow reGion
--
-- inspirated by NrrwRgn.vim
--
-- features/limits
-- * aimed to selection lines, not range
-- * no nested nag
-- * only one nag for one buffer
-- * hard to properly maintain the original buffer's &modifiable, so let user concern it
-- * no syntax/filetype nor treesitter/lsp support
-- * diff+patch
--

local M = {}

local api = vim.api

local bufrename = require("infra.bufrename")
local ctx = require("infra.ctx")
local Ephemeral = require("infra.Ephemeral")
local ex = require("infra.ex")
local jelly = require("infra.jellyfish")("nag")
local strlib = require("infra.strlib")
local sync = require("infra.sync_primitives")
local vsel = require("infra.vsel")

local launch
do
  local function make_nag_name(bufname, start, stop) return string.format("nag://%s@%s~%s", vim.fn.fnamemodify(bufname, ":t"), start, stop) end

  local function is_nag_buf(bufname) return strlib.startswith(bufname, "nag://") end

  ---@param bufnr integer
  ---@param start integer
  ---@param stop integer
  ---@return string
  local function join_lines(bufnr, start, stop)
    local lines = api.nvim_buf_get_lines(bufnr, start, stop, false)
    table.insert(lines, "\n")
    return table.concat(lines, "\n")
  end

  ---start: lnum, 0-based, inclusive
  ---stop: lnum, 0-based, exclusive
  ---@param host nag.Host
  ---@param nag_bufnr integer
  local function diffpatch(host, nag_bufnr)
    local hunks
    do
      local a = join_lines(host.bufnr, host.start, host.stop)
      local b = join_lines(nag_bufnr, 0, -1)
      hunks = vim.diff(a, b, { result_type = "indices" })
      if #hunks == 0 then return jelly.debug("no changes") end
    end
    local offset = host.start
    for i = #hunks, 1, -1 do
      local start_a, count_a, start_b, count_b = unpack(hunks[i])

      local lines
      if count_b == 0 then
        lines = {}
      else
        local start = start_b - 1
        lines = api.nvim_buf_get_lines(nag_bufnr, start, start + count_b, false)
      end

      do
        local start, stop
        if count_a == 0 then -- append
          start = start_a - 1 + offset + 1
          stop = start
        elseif count_b == 0 then -- delete
          start = start_a - 1 + offset
          stop = start + count_a
        else
          start = start_a - 1 + offset
          stop = start + count_a
        end
        api.nvim_buf_set_lines(host.bufnr, start, stop, false, lines)
      end
    end
  end

  ---@class nag.Host
  ---@field winid integer
  ---@field bufnr integer
  ---@field name string
  ---@field start integer
  ---@field stop integer

  ---@return nag.Host?
  local function Host(winid)
    local bufnr = api.nvim_win_get_buf(winid)
    local bufname = api.nvim_buf_get_name(bufnr)
    if is_nag_buf(bufname) then return jelly.warn("nag on nag") end

    local range = vsel.range(bufnr)
    if range == nil then return jelly.warn("no selection") end

    return {
      winid = winid,
      bufnr = bufnr,
      name = bufname,
      start = range.start_line,
      stop = range.stop_line,
    }
  end

  ---@param host_winid integer
  ---@param edit_cmd string @sp,vs,tabe ..., but no modifiers
  function launch(host_winid, edit_cmd)
    assert(host_winid and edit_cmd)

    local host = Host(host_winid)
    if host == nil then return end

    local mux = sync.create_buf_mutex(host.bufnr, "nag")
    if not mux:acquire() then return jelly.warn("nag is running already") end

    local nag_bufnr
    do
      nag_bufnr = Ephemeral({ modifiable = true }, api.nvim_buf_get_lines(host.bufnr, host.start, host.stop, false))
      local tick0 = api.nvim_buf_get_changedtick(nag_bufnr)

      api.nvim_create_autocmd("bufwipeout", {
        buffer = nag_bufnr,
        once = true,
        callback = function()
          mux:release()
          if not api.nvim_buf_is_valid(host.bufnr) then return jelly.warn("original buf#%d was gone", host.bufnr) end
          --determining &modified base on changedtick is not accurate, yet it's still good enough.
          if api.nvim_buf_get_changedtick(nag_bufnr) == tick0 then return jelly.debug("nag buf has not been modified") end
          ctx.undoblock(host.bufnr, function() diffpatch(host, nag_bufnr) end)
        end,
      })
    end

    local nag_name
    do
      nag_name = make_nag_name(host.name, host.start, host.stop)
      bufrename(nag_bufnr, nag_name)
    end

    do
      ex(edit_cmd, nag_name)
      local nag_winid = api.nvim_get_current_win()
      assert(nag_winid ~= host.winid)
      assert(api.nvim_win_get_buf(nag_winid) == nag_bufnr)
    end
  end
end

do
  local function launcher(edit_cmd)
    return function() launch(api.nvim_get_current_win(), edit_cmd) end
  end

  M.tab = launcher("tabe")
  M.split = launcher("split")
  M.vsplit = launcher("vsplit")
end

return M
