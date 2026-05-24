local list = require("csub.list")

local M = {}

-- Cache frequently used API functions
local win_is_valid = vim.api.nvim_win_is_valid
local buf_is_valid = vim.api.nvim_buf_is_valid
local win_get_buf = vim.api.nvim_win_get_buf
local win_set_buf = vim.api.nvim_win_set_buf
local set_current_win = vim.api.nvim_set_current_win
local get_current_win = vim.api.nvim_get_current_win
local list_wins = vim.api.nvim_list_wins
local set_option_value = vim.api.nvim_set_option_value

function M.apply_window_opts(winid)
    if winid and win_is_valid(winid) then
        set_option_value("wrap", false, { scope = "local", win = winid })
    end
end

function M.is_quickfix_window(winid)
    if not (winid and win_is_valid(winid)) then
        return false
    end
    local buf = win_get_buf(winid)
    return vim.bo[buf].buftype == "quickfix"
end

function M.find_quickfix_window()
    for _, win in ipairs(list_wins()) do
        if M.is_quickfix_window(win) and not list.is_loclist_window(win) then
            return win
        end
    end
end

function M.find_loclist_window(owner_winid)
    if not owner_winid or not win_is_valid(owner_winid) then return nil end
    for _, win in ipairs(list_wins()) do
        if list.is_loclist_window(win) then
            local fi = vim.fn.getloclist(win, { filewinid = 0 })
            if fi and fi.filewinid == owner_winid then
                return win
            end
        end
    end
end

function M.ensure_quickfix_window()
    local winid = M.find_quickfix_window()
    if winid then
        return winid
    end
    pcall(vim.cmd.copen)
    return M.find_quickfix_window()
end

function M.ensure_list_window(target)
    if target.kind == "loclist" then
        local win = M.find_loclist_window(target.winid)
        if win then return win end
        if target.winid and win_is_valid(target.winid) then
            local prev = get_current_win()
            local ok = pcall(set_current_win, target.winid)
            if ok then
                pcall(vim.cmd.lopen)
                if win_is_valid(prev) then
                    pcall(set_current_win, prev)
                end
            end
            return M.find_loclist_window(target.winid)
        end
        return nil
    end
    return M.ensure_quickfix_window()
end

function M.find_window_with_buf(bufnr)
    if not (bufnr and buf_is_valid(bufnr)) then
        return
    end
    for _, win in ipairs(list_wins()) do
        if win_is_valid(win) and win_get_buf(win) == bufnr then
            return win
        end
    end
end

function M.use_buf(winid, bufnr)
    if not (winid and bufnr) then
        return
    end
    if not (win_is_valid(winid) and buf_is_valid(bufnr)) then
        return
    end
    if win_get_buf(winid) ~= bufnr then
        pcall(win_set_buf, winid, bufnr)
    end
    pcall(set_current_win, winid)
end

return M
