-- Lazy-require submodules so they only load on the first :Csub.
local function lazy_require(name)
    local m
    return setmetatable({}, {
        __index = function(_, k)
            m = m or require(name)
            return m[k]
        end,
    })
end

local buffer = lazy_require("csub.buffer")
local list = lazy_require("csub.list")
local replace = lazy_require("csub.replace")
local view = lazy_require("csub.view")
local window = lazy_require("csub.window")

-- Cache frequently used API functions
local buf_is_valid = vim.api.nvim_buf_is_valid
local win_is_valid = vim.api.nvim_win_is_valid
local win_get_buf = vim.api.nvim_win_get_buf
local win_get_cursor = vim.api.nvim_win_get_cursor
local get_current_buf = vim.api.nvim_get_current_buf
local get_current_win = vim.api.nvim_get_current_win
local set_current_win = vim.api.nvim_set_current_win

local M = {}

local state = {
    bufnr = nil,
    source_bufnr = nil,
    source_winid = nil,
    cursor_line = 1,
    saved_view = nil,
    target = { kind = "qf", winid = nil },
}

local config = {
    handlers = {},
    default_mode = "replace",
    syntax_highlight = true,
}

--- Detect mode based on the list's title.
--- @param target table { kind, winid }
--- @return string|nil mode The detected mode, or nil if csub should be disabled
local function detect_mode(target)
    local info = list.get(target, { title = 1 })
    local title = (info and info.title) or ""

    for _, handler in ipairs(config.handlers) do
        if title:find(handler.match, 1, true) then
            return handler.mode -- can be nil to disable csub
        end
    end

    return config.default_mode
end

local function open_replace_window(invoking_winid, scope)
    local target = list.classify(invoking_winid)

    -- A visual range only makes sense over a list buffer.
    if scope and not window.is_quickfix_window(invoking_winid) then
        vim.notify(
            "[csub] :Csub with a range must be invoked from a quickfix or loclist window.",
            vim.log.levels.WARN
        )
        return
    end

    local current_items = list.get(target, { items = 1 }).items or {}
    if #current_items == 0 then
        local label = target.kind == "loclist" and "location list" or "quickfix list"
        vim.notify(("[csub] No %s available."):format(label), vim.log.levels.INFO)
        return
    end

    if scope then
        scope.first = math.max(1, math.min(scope.first, #current_items))
        scope.last = math.max(scope.first, math.min(scope.last, #current_items))
    end

    local mode = detect_mode(target)
    if mode == nil then
        local label = target.kind == "loclist" and "location list" or "quickfix list"
        vim.notify(("[csub] Csub is disabled for this %s."):format(label), vim.log.levels.INFO)
        return
    end

    -- Pick the list window to host the csub buffer.
    local target_win = state.source_winid
    if not (target_win and win_is_valid(target_win)
            and window.is_quickfix_window(target_win)
            and list.classify(target_win).kind == target.kind
            and (target.kind ~= "loclist" or list.classify(target_win).winid == target.winid)) then
        target_win = window.ensure_list_window(target)
    end
    if not target_win then
        vim.notify("[csub] Unable to open list window.", vim.log.levels.ERROR)
        return
    end

    state.target = target
    state.source_winid = target_win
    state.source_bufnr = win_get_buf(target_win)
    local saved_view = view.save(target_win, state.source_bufnr)
    local cursor_line = (saved_view and saved_view.lnum) or win_get_cursor(target_win)[1]
    local list_id = list.current_id(target)
    state.cursor_line = cursor_line
    state.saved_view = saved_view

    local signature = list.signature(target, list_id, scope)
    if state.bufnr
        and buf_is_valid(state.bufnr)
        and vim.b[state.bufnr].csub_dirty
        and vim.b[state.bufnr].csub_list_signature
        and vim.b[state.bufnr].csub_list_signature ~= signature then
        vim.notify(
            "[csub] Existing csub buffer has unsaved changes for another list.",
            vim.log.levels.WARN
        )
        return
    end

    local bufnr = buffer.ensure_buffer(state, target_win, state.source_bufnr, replace.apply)
    if not bufnr then
        vim.notify("[csub] Unable to prepare csub buffer.", vim.log.levels.ERROR)
        return
    end

    vim.b[bufnr].csub_saved_view = saved_view

    if vim.b[bufnr].csub_dirty and vim.b[bufnr].csub_list_signature == signature then
        vim.b[bufnr].csub_mode = mode
    else
        buffer.populate(bufnr, current_items, mode, {
            list_id = list_id,
            target = target,
            signature = signature,
            scope = scope,
            syntax_highlight = config.syntax_highlight,
        })
    end

    window.apply_window_opts(target_win)
    view.restore(target_win, bufnr, saved_view, cursor_line)
end

function M.start(opts)
    opts = opts or {}
    local scope = nil
    if opts.range and opts.range > 0 and opts.line1 and opts.line2 then
        scope = { first = opts.line1, last = opts.line2 }
    end

    local current_buf = get_current_buf()
    if state.bufnr and buf_is_valid(state.bufnr) and current_buf == state.bufnr then
        -- We are in the csub buffer; toggle back to the list window.
        local current_line = win_get_cursor(0)[1]
        state.cursor_line = current_line
        local new_view = view.save(get_current_win(), state.bufnr) or state.saved_view or {}
        new_view.lnum = current_line
        state.saved_view = new_view
        vim.b[state.bufnr].csub_saved_view = new_view

        local target = state.target or { kind = "qf", winid = nil }
        local info = list.get(target, { qfbufnr = 1 }) or {}
        local listbuf = (info.qfbufnr and info.qfbufnr ~= 0) and info.qfbufnr or state.source_bufnr

        if listbuf and buf_is_valid(listbuf) then
            window.use_buf(get_current_win(), listbuf)
            view.restore(get_current_win(), listbuf, state.saved_view, state.cursor_line)
        else
            local listwin = window.ensure_list_window(target)
            if listwin and win_is_valid(listwin) then
                set_current_win(listwin)
                view.restore(listwin, win_get_buf(listwin), state.saved_view, state.cursor_line)
            end
        end

        return
    end

    open_replace_window(get_current_win(), scope)
end

-- Optional: override defaults. The plugin works without calling this; the
-- :Csub command, the FileType autocommand, and the highlight groups are
-- registered automatically by plugin/csub.lua at startup.
function M.setup(opts)
    opts = opts or {}

    if opts.handlers ~= nil then
        config.handlers = opts.handlers
    end

    if opts.default_mode ~= nil then
        config.default_mode = opts.default_mode
    end

    if opts.syntax_highlight ~= nil then
        config.syntax_highlight = opts.syntax_highlight
    end
end

return M
