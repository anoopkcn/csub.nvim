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

return M
