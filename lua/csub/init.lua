local buffer = require("csub.buffer")
local fmt = require("csub.format")
local replace = require("csub.replace")
local view = require("csub.view")
local window = require("csub.window")

local M = {}

local qf_ns = vim.api.nvim_create_namespace("csub_qf_meta")

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
    local qf_info = vim.fn.getqflist({ title = 0 })
    local title = qf_info.title or ""

    for _, handler in ipairs(config.handlers) do
        if title:find(handler.match, 1, true) then
            return handler.mode -- can be nil to disable csub
        end
    end

    return config.default_mode
end

local function highlight_qf_buffer()
    local qf_info = vim.fn.getqflist({ qfbufnr = 0, items = 1 })
    local qfbufnr = qf_info.qfbufnr
    if not qfbufnr or qfbufnr == 0 or not vim.api.nvim_buf_is_valid(qfbufnr) then
        return
    end

    local items = qf_info.items or {}
    if #items == 0 then
        return
    end

    vim.api.nvim_buf_clear_namespace(qfbufnr, qf_ns, 0, -1)

    for idx, entry in ipairs(items) do
        local chunks = fmt.format_meta_chunks(entry, { width = fmt.META_WIDTH })
        vim.api.nvim_buf_set_extmark(qfbufnr, qf_ns, idx - 1, 0, {
            virt_text = chunks,
            virt_text_pos = "overlay",
            hl_mode = "combine",
            priority = 100,
        })
    end
end

local function open_replace_window()
    local current_qflist = vim.fn.getqflist()
    if not current_qflist or vim.tbl_isempty(current_qflist) then
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
    state.qf_bufnr = vim.api.nvim_win_get_buf(target_win)
    local qf_view = view.save(target_win, state.qf_bufnr)
    local cursor_line = (qf_view and qf_view.lnum) or vim.api.nvim_win_get_cursor(target_win)[1]
    state.qf_cursor = cursor_line
    state.qf_view = qf_view

    local bufnr = buffer.ensure_buffer(state, target_win, state.qf_bufnr, replace.apply)
    if not bufnr then
        vim.notify("[csub] Unable to prepare csub buffer.", vim.log.levels.ERROR)
        return
    end

    vim.b[bufnr].csub_qf_view = qf_view
    vim.b[bufnr].csub_mode = mode

    buffer.populate(bufnr, current_qflist, mode)
    window.apply_window_opts(target_win)
    view.restore(target_win, bufnr, qf_view, cursor_line)
end

function M.start()
    local current_buf = vim.api.nvim_get_current_buf()
    if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) and current_buf == state.bufnr then
        local current_line = vim.api.nvim_win_get_cursor(0)[1]
        state.qf_cursor = current_line
        local new_view = view.save(vim.api.nvim_get_current_win(), state.bufnr) or state.qf_view or {}
        new_view.lnum = current_line
        state.qf_view = new_view
        vim.b[state.bufnr].csub_qf_view = new_view

        local current_qflist = vim.fn.getqflist()
        if current_qflist and not vim.tbl_isempty(current_qflist) then
            local mode = vim.b[state.bufnr].csub_mode or config.default_mode
            buffer.populate(state.bufnr, current_qflist, mode)
        end

        local qf_info = vim.fn.getqflist({ qfbufnr = 0 }) or {}
        local qfbuf = (qf_info.qfbufnr and qf_info.qfbufnr ~= 0) and qf_info.qfbufnr or state.qf_bufnr

        if qfbuf and vim.api.nvim_buf_is_valid(qfbuf) then
            window.use_buf(vim.api.nvim_get_current_win(), qfbuf)
            view.restore(vim.api.nvim_get_current_win(), qfbuf, state.qf_view, state.qf_cursor)
        else
            local qfwin = window.ensure_quickfix_window()
            if qfwin and vim.api.nvim_win_is_valid(qfwin) then
                vim.api.nvim_set_current_win(qfwin)
                view.restore(qfwin, vim.api.nvim_win_get_buf(qfwin), state.qf_view, state.qf_cursor)
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
    vim.api.nvim_set_hl(0, "CsubSeparator", { link = "Comment", default = true })
    vim.api.nvim_set_hl(0, "CsubMetaFileName", { link = "Comment", default = true })
    vim.api.nvim_set_hl(0, "CsubMetaNumber", { link = "Number", default = true })

    -- Set nowrap for quickfix and csub windows
    vim.api.nvim_create_autocmd("FileType", {
        pattern = { "qf", "csub" },
        callback = function()
            vim.wo.wrap = false
        end,
    })

    -- Apply extmark highlights to quickfix buffer
    vim.api.nvim_create_autocmd("QuickFixCmdPost", {
        pattern = "*",
        callback = function()
            vim.schedule(highlight_qf_buffer)
        end,
    })

    -- Reapply highlights when quickfix window is opened
    vim.api.nvim_create_autocmd("BufWinEnter", {
        callback = function(args)
            if vim.bo[args.buf].buftype == "quickfix" then
                vim.schedule(highlight_qf_buffer)
            end
        end,
    })

    vim.api.nvim_create_user_command("Csub", function()
        M.start()
    end, { nargs = 0 })
end

return M
