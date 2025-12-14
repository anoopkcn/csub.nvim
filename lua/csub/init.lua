local buffer = require("csub.buffer")
local fmt = require("csub.format")
local replace = require("csub.replace")
local view = require("csub.view")
local window = require("csub.window")

-- Cache frequently used API functions
local buf_is_valid = vim.api.nvim_buf_is_valid
local win_is_valid = vim.api.nvim_win_is_valid
local win_get_buf = vim.api.nvim_win_get_buf
local win_get_cursor = vim.api.nvim_win_get_cursor
local get_current_buf = vim.api.nvim_get_current_buf
local get_current_win = vim.api.nvim_get_current_win
local set_current_win = vim.api.nvim_set_current_win
local buf_clear_namespace = vim.api.nvim_buf_clear_namespace
local buf_set_extmark = vim.api.nvim_buf_set_extmark
local create_namespace = vim.api.nvim_create_namespace
local create_autocmd = vim.api.nvim_create_autocmd
local create_augroup = vim.api.nvim_create_augroup
local create_user_command = vim.api.nvim_create_user_command
local set_hl = vim.api.nvim_set_hl

local M = {}

local qf_ns = create_namespace("csub_qf_meta")

local state = {
    bufnr = nil,
    qf_bufnr = nil,
    qf_winid = nil,
    qf_cursor = 1,
    qf_view = nil,
}

local config = {
    handlers = {},
    default_mode = "replace",
}

--- Detect the mode for the current quickfix list based on its title
--- @return string|nil mode The detected mode, or nil if csub should be disabled
local function detect_mode()
    local qf_info = vim.fn.getqflist({ title = 1 })
    local title = qf_info.title or ""

    for _, handler in ipairs(config.handlers) do
        if title:find(handler.match, 1, true) then
            return handler.mode -- can be nil to disable csub
        end
    end

    return config.default_mode
end

local function highlight_qf_buffer()
    local qf_info = vim.fn.getqflist({ qfbufnr = 1, items = 1 })
    local qfbufnr = qf_info.qfbufnr
    if not qfbufnr or qfbufnr == 0 or not buf_is_valid(qfbufnr) then
        return
    end

    local items = qf_info.items or {}
    if #items == 0 then
        return
    end

    buf_clear_namespace(qfbufnr, qf_ns, 0, -1)

    for idx, entry in ipairs(items) do
        local chunks = fmt.format_meta_chunks(entry, { width = fmt.META_WIDTH })
        buf_set_extmark(qfbufnr, qf_ns, idx - 1, 0, {
            virt_text = chunks,
            virt_text_pos = "overlay",
            hl_mode = "combine",
            priority = 100,
            strict = false,
        })
    end
end

local function open_replace_window()
    local current_qflist = vim.fn.getqflist()
    if not current_qflist or #current_qflist == 0 then
        vim.notify("[csub] No quickfix list available.", vim.log.levels.INFO)
        return
    end

    -- Detect mode from quickfix title
    local mode = detect_mode()
    if mode == nil then
        vim.notify("[csub] Csub is disabled for this quickfix list.", vim.log.levels.INFO)
        return
    end

    -- Only use stored window if it's still a valid quickfix window
    local target_win = state.qf_winid
    if not window.is_quickfix_window(target_win) then
        target_win = window.ensure_quickfix_window()
    end
    if not target_win then
        vim.notify("[csub] Unable to open quickfix window.", vim.log.levels.ERROR)
        return
    end

    state.qf_winid = target_win
    state.qf_bufnr = win_get_buf(target_win)
    local qf_view = view.save(target_win, state.qf_bufnr)
    local cursor_line = (qf_view and qf_view.lnum) or win_get_cursor(target_win)[1]
    state.qf_cursor = cursor_line
    state.qf_view = qf_view

    local bufnr = buffer.ensure_buffer(state, target_win, state.qf_bufnr, replace.apply)
    if not bufnr then
        vim.notify("[csub] Unable to prepare csub buffer.", vim.log.levels.ERROR)
        return
    end

    vim.b[bufnr].csub_qf_view = qf_view
    buffer.populate(bufnr, current_qflist, mode)
    window.apply_window_opts(target_win)
    view.restore(target_win, bufnr, qf_view, cursor_line)
end

function M.start()
    local current_buf = get_current_buf()
    if state.bufnr and buf_is_valid(state.bufnr) and current_buf == state.bufnr then
        local current_line = win_get_cursor(0)[1]
        state.qf_cursor = current_line
        local new_view = view.save(get_current_win(), state.bufnr) or state.qf_view or {}
        new_view.lnum = current_line
        state.qf_view = new_view
        vim.b[state.bufnr].csub_qf_view = new_view

        local current_qflist = vim.fn.getqflist()
        if current_qflist and #current_qflist > 0 then
            local mode = vim.b[state.bufnr].csub_mode or config.default_mode
            buffer.populate(state.bufnr, current_qflist, mode)
        end

        local qf_info = vim.fn.getqflist({ qfbufnr = 1 }) or {}
        local qfbuf = (qf_info.qfbufnr and qf_info.qfbufnr ~= 0) and qf_info.qfbufnr or state.qf_bufnr

        if qfbuf and buf_is_valid(qfbuf) then
            window.use_buf(get_current_win(), qfbuf)
            view.restore(get_current_win(), qfbuf, state.qf_view, state.qf_cursor)
        else
            local qfwin = window.ensure_quickfix_window()
            if qfwin and win_is_valid(qfwin) then
                set_current_win(qfwin)
                view.restore(qfwin, win_get_buf(qfwin), state.qf_view, state.qf_cursor)
            end
        end

        -- Keep state.bufnr so we can reuse the buffer next time
        return
    end

    open_replace_window()
end

function M.quickfix_text(info)
    return fmt.quickfix_text(info)
end

function M.setup(opts)
    opts = opts or {}

    if opts.separator ~= nil then
        fmt.separator = opts.separator
    end

    if opts.handlers ~= nil then
        config.handlers = opts.handlers
    end

    if opts.default_mode ~= nil then
        config.default_mode = opts.default_mode
    end

    vim.o.quickfixtextfunc = "v:lua.require'csub'.quickfix_text"

    -- default=true only sets the highlight if it doesn't already exist
    set_hl(0, "CsubSeparator", { link = "Comment", default = true })
    set_hl(0, "CsubMetaFileName", { link = "Comment", default = true })
    set_hl(0, "CsubMetaNumber", { link = "Number", default = true })

    -- Create autocommand group for organized cleanup
    local augroup = create_augroup("csub", { clear = true })

    -- Set nowrap for quickfix and csub windows
    create_autocmd("FileType", {
        group = augroup,
        pattern = { "qf", "csub" },
        callback = function()
            vim.wo.wrap = false
        end,
    })

    -- Apply extmark highlights to quickfix buffer
    create_autocmd("QuickFixCmdPost", {
        group = augroup,
        pattern = "*",
        callback = function()
            vim.schedule(highlight_qf_buffer)
        end,
    })

    -- Reapply highlights when quickfix window is opened
    create_autocmd("BufWinEnter", {
        group = augroup,
        callback = function(args)
            if vim.bo[args.buf].buftype == "quickfix" then
                vim.schedule(highlight_qf_buffer)
            end
        end,
    })

    create_user_command("Csub", function()
        M.start()
    end, { nargs = 0 })
end

return M
