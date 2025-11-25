local M = {}

function M.apply_window_opts(winid)
    if winid and vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_set_option_value("wrap", false, { scope = "local", win = winid })
    end
end

function M.close_list_windows()
    for _, win in ipairs(vim.fn.getwininfo()) do
        if win.quickfix == 1 then
            pcall(vim.api.nvim_win_close, win.winid, false)
        end
    end
end

function M.find_quickfix_window()
    for _, win in ipairs(vim.fn.getwininfo()) do
        if win.quickfix == 1 then
            return win.winid
        end
    end
end

function M.ensure_quickfix_window()
    local winid = M.find_quickfix_window()
    if winid and vim.api.nvim_win_is_valid(winid) then
        return winid
    end

    pcall(vim.cmd, "copen")
    winid = M.find_quickfix_window()
    if winid and vim.api.nvim_win_is_valid(winid) then
        return winid
    end
end

function M.find_window_with_buf(bufnr)
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
        return
    end
    local wins = vim.fn.win_findbuf(bufnr)
    if wins and wins[1] and vim.api.nvim_win_is_valid(wins[1]) then
        return wins[1]
    end
end

function M.close_if_buf(winid, bufnr)
    if not (winid and bufnr) then
        return
    end
    if not vim.api.nvim_win_is_valid(winid) then
        return
    end
    local current = vim.api.nvim_win_get_buf(winid)
    if current == bufnr then
        pcall(vim.api.nvim_win_close, winid, true)
    end
end

function M.use_buf(winid, bufnr)
    if not (winid and bufnr) then
        return
    end
    if not (vim.api.nvim_win_is_valid(winid) and vim.api.nvim_buf_is_valid(bufnr)) then
        return
    end
    if vim.api.nvim_win_get_buf(winid) ~= bufnr then
        pcall(vim.api.nvim_win_set_buf, winid, bufnr)
    end
    pcall(vim.api.nvim_set_current_win, winid)
end

return M
