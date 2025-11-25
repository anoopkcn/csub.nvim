local buffer = require("csub.buffer")
local fmt = require("csub.format")
local replace = require("csub.replace")
local window = require("csub.window")

local M = {}

local state = {
    bufnr = nil,
    qf_bufnr = nil,
    qf_winid = nil,
    qf_cursor = 1,
    qf_view = nil,
}

local function set_cursor_safe(winid, bufnr, line)
    if not (winid and bufnr and line) then
        return
    end
    if not (vim.api.nvim_win_is_valid(winid) and vim.api.nvim_buf_is_valid(bufnr)) then
        return
    end
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local l = math.max(1, math.min(line, line_count))
    pcall(vim.api.nvim_win_set_cursor, winid, { l, 0 })
end

local function open_replace_window()
    local current_qflist = vim.fn.getqflist()
    if not current_qflist or vim.tbl_isempty(current_qflist) then
        vim.notify("[csub] No quickfix list available.", vim.log.levels.INFO)
        return
    end

    local target_win = state.qf_winid
    if not (target_win and vim.api.nvim_win_is_valid(target_win)) then
        target_win = window.ensure_quickfix_window()
    end
    if not target_win then
        vim.notify("[csub] Unable to open quickfix window.", vim.log.levels.ERROR)
        return
    end

    state.qf_winid = target_win
    state.qf_bufnr = vim.api.nvim_win_get_buf(target_win)
    local view = vim.fn.winsaveview()
    local cursor_line = view.lnum or vim.api.nvim_win_get_cursor(target_win)[1]
    state.qf_cursor = cursor_line
    state.qf_view = view

    local bufnr = buffer.ensure_buffer(state, target_win, state.qf_bufnr, replace.apply)
    if not bufnr then
        vim.notify("[csub] Unable to prepare csub buffer.", vim.log.levels.ERROR)
        return
    end

    vim.b[bufnr].csub_qf_view = view

    buffer.populate(bufnr, current_qflist)
    window.apply_window_opts(target_win)
    set_cursor_safe(target_win, bufnr, cursor_line)
    if view then
        local restore = vim.deepcopy(view)
        restore.lnum = cursor_line
        pcall(vim.fn.winrestview, restore)
    end
end

function M.start()
    local current_buf = vim.api.nvim_get_current_buf()
    if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) and current_buf == state.bufnr then
        local current_qflist = vim.fn.getqflist()
        if current_qflist and not vim.tbl_isempty(current_qflist) then
            buffer.populate(state.bufnr, current_qflist)
        end

        local qf_info = vim.fn.getqflist({ qfbufnr = 0 }) or {}
        local qfbuf = (qf_info.qfbufnr and qf_info.qfbufnr ~= 0) and qf_info.qfbufnr or state.qf_bufnr

        if qfbuf and vim.api.nvim_buf_is_valid(qfbuf) then
            window.use_buf(vim.api.nvim_get_current_win(), qfbuf)
            set_cursor_safe(vim.api.nvim_get_current_win(), qfbuf, state.qf_cursor)
            if state.qf_view then
                local restore = vim.deepcopy(state.qf_view)
                restore.lnum = state.qf_cursor
                pcall(vim.fn.winrestview, restore)
            end
        else
            local qfwin = window.ensure_quickfix_window()
            if qfwin and vim.api.nvim_win_is_valid(qfwin) then
                vim.api.nvim_set_current_win(qfwin)
                set_cursor_safe(qfwin, vim.api.nvim_win_get_buf(qfwin), state.qf_cursor)
                if state.qf_view then
                    local restore = vim.deepcopy(state.qf_view)
                    restore.lnum = state.qf_cursor
                    pcall(vim.fn.winrestview, restore)
                end
            end
        end

        state.bufnr = nil
        return
    end

    open_replace_window()
end

function M.quickfix_text(info)
    return fmt.quickfix_text(info)
end

function M.setup()
    vim.o.quickfixtextfunc = "v:lua.require'csub'.quickfix_text"

    if vim.fn.hlexists("CsubSeparator") == 0 then
        pcall(vim.api.nvim_set_hl, 0, "CsubSeparator", { link = "Comment" })
    end
    if vim.fn.hlexists("CsubMetaFileName") == 0 then
        pcall(vim.api.nvim_set_hl, 0, "CsubMetaFileName", { link = "Comment" })
    end
    if vim.fn.hlexists("CsubMetaNumber") == 0 then
        pcall(vim.api.nvim_set_hl, 0, "CsubMetaNumber", { link = "Number" })
    end

    vim.api.nvim_create_user_command("Csub", function()
        M.start()
    end, { nargs = 0 })
end

return M
