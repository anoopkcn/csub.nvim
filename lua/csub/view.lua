local M = {}

local function clamp_line(bufnr, line)
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
        return 1
    end
    local count = vim.api.nvim_buf_line_count(bufnr)
    return math.max(1, math.min(line, count))
end

function M.save(winid, bufnr)
    if not (winid and vim.api.nvim_win_is_valid(winid)) then
        return
    end
    if bufnr and not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    local view = vim.api.nvim_win_call(winid, function()
        return vim.fn.winsaveview()
    end)
    view.lnum = clamp_line(bufnr or vim.api.nvim_win_get_buf(winid), view.lnum or 1)
    return view
end

function M.restore(winid, bufnr, view, cursor_line)
    if not (winid and view) then
        return
    end
    if bufnr and not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    if not vim.api.nvim_win_is_valid(winid) then
        return
    end
    local target_buf = bufnr or vim.api.nvim_win_get_buf(winid)
    local line = cursor_line or view.lnum or 1
    line = clamp_line(target_buf, line)

    local restore = vim.deepcopy(view)
    restore.lnum = line
    restore.col = 0
    vim.api.nvim_win_call(winid, function()
        pcall(vim.fn.winrestview, restore)
    end)
end

return M
