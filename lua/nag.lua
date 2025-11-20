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

local buflines = require("infra.buflines")
local bufopen = require("infra.bufopen")
local ctx = require("infra.ctx")
local Ephemeral = require("infra.Ephemeral")
local jelly = require("infra.jellyfish")("nag")
local mi = require("infra.mi")
local ni = require("infra.ni")
local strlib = require("infra.strlib")
local sync = require("infra.sync_primitives")
local vsel = require("infra.vsel")

local function make_nag_name(bufname, start, stop) return string.format("nag://%s@%s~%s", vim.fn.fnamemodify(bufname, ":t"), start, stop) end

local function is_nag_buf(bufname) return strlib.startswith(bufname, "nag://") end

---start: lnum, 0-based, inclusive
---stop: lnum, 0-based, exclusive
---@param host nag.Host
---@param nag_bufnr integer
local function diffpatch(host, nag_bufnr)
  local hunks
  do
    local a = buflines.joined(host.bufnr, host.start, host.stop)
    local b = buflines.joined(nag_bufnr)
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
      lines = buflines.lines(nag_bufnr, start, start + count_b)
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
      buflines.replaces(host.bufnr, start, stop, lines)
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
  local bufnr = ni.win_get_buf(winid)
  local bufname = ni.buf_get_name(bufnr)
  if is_nag_buf(bufname) then return jelly.warn("no nag-on-nag") end

  local range = vsel.range(bufnr, true)
  if range == nil then return jelly.warn("no selection") end

  return {
    winid = winid,
    bufnr = bufnr,
    name = bufname,
    start = range.start_line,
    stop = range.stop_line,
  }
end

---@param host_winid? integer @nil = current
---@param open_mode? infra.bufopen.Mode @nil='right'
return function(host_winid, open_mode)
  host_winid = mi.resolve_winid_param(host_winid)
  open_mode = open_mode or "right"

  local host = Host(host_winid)
  if host == nil then return end

  local mux = sync.BufMutex(host.bufnr, "nag")
  if not mux:acquire_nowait() then return jelly.warn("nagging in buf#%d already", host.bufnr) end

  local nag_bufnr
  do
    local function namefn() return make_nag_name(host.name, host.start, host.stop) end
    local lines = buflines.lines(host.bufnr, host.start, host.stop)
    nag_bufnr = Ephemeral({ modifiable = true, namefn = namefn, undolevels = vim.go.undolevels }, lines)

    local tick0 = ni.buf_get_changedtick(nag_bufnr)

    ni.create_autocmd("bufwipeout", {
      buffer = nag_bufnr,
      once = true,
      callback = function()
        mux:release()
        if not ni.buf_is_valid(host.bufnr) then return jelly.warn("original buf#%d was gone", host.bufnr) end
        --determining &modified base on changedtick is not accurate, yet it's still good enough.
        if ni.buf_get_changedtick(nag_bufnr) == tick0 then return jelly.debug("nag buf has not been modified") end
        ctx.undoblock(host.bufnr, function() diffpatch(host, nag_bufnr) end)
      end,
    })
  end

  do
    bufopen(open_mode, nag_bufnr)
    local nag_winid = ni.get_current_win()
    assert(nag_winid ~= host.winid)
    assert(ni.win_get_buf(nag_winid) == nag_bufnr)
  end
end
