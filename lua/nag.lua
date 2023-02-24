-- nag -> NArrow reGion
--
-- inspirated by NrrwRgn.vim
--
-- features/limits
-- * aimed to selection lines, not range
-- * keep indents as is
-- * no nag on nag
-- * only one nag for one buffer
-- * is hard to properly maintain original buffer's &modifiable, so let user concern it
-- * no syntax/filetype, treesitter/lsp support at now
--

local M = {}

local api = vim.api

local vsel = require("infra.vsel")
local sync = require("infra.sync_primitives")
local jelly = require("infra.jellyfish")("nag")
local bufrename = require("infra.bufrename")
local ex = require("infra.ex")

local function make_nag_name(bufname, start, stop)
  return string.format("nag://%s@%s-%s", vim.fn.fnamemodify(bufname, ":t"), start, stop)
end

local function is_valid_nag_buf(bufname)
  return vim.startswith(bufname, "nag://")
end

local function setup(src_win_id, src_bufnr, open_win_cmd)
  assert(src_win_id and src_bufnr and open_win_cmd)

  local origin_state
  local selines
  do
    local bufname = api.nvim_buf_get_name(src_bufnr)
    if is_valid_nag_buf(bufname) then
      jelly.warn("nag on nag")
      return
    end

    local start_row, _, stop_row, _ = vsel.range(src_bufnr)
    origin_state = {
      win_id = src_win_id,
      bufnr = src_bufnr,
      name = bufname,
      start_row = start_row,
      stop_row = stop_row,
    }

    selines = vsel.multiline_text(origin_state.bufnr)
    if selines == nil then return end
  end

  local mux = sync.create_buf_mutex("nag")
  if not mux:acquire() then
    jelly.warn("nag is running already")
    return
  end

  local nag_bufnr
  local nag_bufname
  -- setup nag buf
  do
    nag_bufnr = api.nvim_create_buf(false, true)
    nag_bufname = make_nag_name(origin_state.name, origin_state.start_row, origin_state.stop_row)
    do
      bufrename(nag_bufnr, nag_bufname)
      api.nvim_buf_set_lines(nag_bufnr, 0, #selines, false, selines)
      local bo = vim.bo[nag_bufnr]
      bo.buftype = "acwrite"
      bo.modified = false
      bo.bufhidden = "wipe"
    end

    -- NB: with buftype=acwrite, bufhidden=wipe
    -- * :w             -> event:bufwritecmd            sync
    -- * :q+&unmodified -> event:bufwritecmd            sync
    -- * :q+&modified   -> event:none                   error
    -- * :q!            -> event:none                   discard
    -- * :x             -> event:bufwritecmd&bufwipeout sync
    local ran = false
    api.nvim_create_autocmd({ "BufWriteCmd", "BufWipeout" }, {
      buffer = nag_bufnr,
      callback = function()
        if ran then return end
        ran = true
        mux:release()
        if not api.nvim_buf_is_valid(origin_state.bufnr) then return end
        if not vim.bo[nag_bufnr].modified then return end
        local ok, err = xpcall(function()
          local lines = api.nvim_buf_get_lines(nag_bufnr, 0, -1, true)
          api.nvim_buf_set_lines(origin_state.bufnr, origin_state.start_row - 1, origin_state.stop_row, false, lines)
          vim.bo[nag_bufnr].modified = false
        end, debug.traceback)
        if not ok then jelly.error(err) end
      end,
    })
  end

  -- setup nag window
  do
    ex(open_win_cmd, nag_bufname)
    local nag_winid = api.nvim_get_current_win()
    assert(nag_winid ~= origin_state.win_id)
    api.nvim_win_set_buf(nag_winid, nag_bufnr)
  end
end

M.tab = function()
  local src_win_id = api.nvim_get_current_win()
  local src_bufnr = api.nvim_get_current_buf()

  setup(src_win_id, src_bufnr, "tabe")
end

M.vsplit = function()
  local src_win_id = api.nvim_get_current_win()
  local src_bufnr = api.nvim_get_current_buf()

  setup(src_win_id, src_bufnr, "vsplit")
end

M.split = function()
  local src_win_id = api.nvim_get_current_win()
  local src_bufnr = api.nvim_get_current_buf()

  setup(src_win_id, src_bufnr, "split")
end

return M
