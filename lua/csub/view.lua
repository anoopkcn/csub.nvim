local M = {}

-- Cache frequently used API functions
local win_is_valid = vim.api.nvim_win_is_valid
local buf_is_valid = vim.api.nvim_buf_is_valid
local buf_line_count = vim.api.nvim_buf_line_count
local win_get_buf = vim.api.nvim_win_get_buf
local win_call = vim.api.nvim_win_call

local function clamp_line(bufnr, line)
    if not (bufnr and buf_is_valid(bufnr)) then
        return 1
    end
    local count = buf_line_count(bufnr)
    return math.max(1, math.min(line, count))
end

function M.save(winid, bufnr)
    if not (winid and win_is_valid(winid)) then
        return
    end
    if bufnr and not buf_is_valid(bufnr) then
        return
    end
    local view = win_call(winid, function()
        return vim.fn.winsaveview()
    end)
    view.lnum = clamp_line(bufnr or win_get_buf(winid), view.lnum or 1)
    return view
end

function M.restore(winid, bufnr, view, cursor_line)
    if not (winid and view) then
        return
    end
    if bufnr and not buf_is_valid(bufnr) then
        return
    end
    if not win_is_valid(winid) then
        return
    end
    local target_buf = bufnr or win_get_buf(winid)
    local line = cursor_line or view.lnum or 1
    line = clamp_line(target_buf, line)

    -- Shallow copy is sufficient for view tables (all values are primitives)
    local restore = {
        lnum = line,
        col = 0,
        coladd = view.coladd,
        curswant = view.curswant,
        topline = view.topline,
        topfill = view.topfill,
        leftcol = view.leftcol,
        skipcol = view.skipcol,
    }
    win_call(winid, function()
        pcall(vim.fn.winrestview, restore)
    end)
end

return M
