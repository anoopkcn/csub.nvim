local buffer = require("csub.buffer")
local list = require("csub.list")
local utils = require("csub.utils")
local view = require("csub.view")
local window = require("csub.window")

-- Cache frequently used API functions
local buf_is_valid = vim.api.nvim_buf_is_valid
local buf_is_loaded = vim.api.nvim_buf_is_loaded
local win_is_valid = vim.api.nvim_win_is_valid
local buf_get_lines = vim.api.nvim_buf_get_lines
local buf_set_lines = vim.api.nvim_buf_set_lines
local buf_line_count = vim.api.nvim_buf_line_count
local buf_call = vim.api.nvim_buf_call
local win_get_cursor = vim.api.nvim_win_get_cursor

local M = {}

local function entry_id(entry, fallback)
    return entry._csub_id or fallback
end

local function ensure_loaded(bufnr)
    if buf_is_valid(bufnr) and not buf_is_loaded(bufnr) then
        vim.fn.bufload(bufnr)
    end
end

local function save_buffer(bufnr)
    if not (bufnr and buf_is_valid(bufnr) and buf_is_loaded(bufnr)) then
        return
    end

    local no_save = vim.g.csub_no_save or vim.g.csubstitute_no_save or 0
    buf_call(bufnr, function()
        if vim.o.hidden and no_save ~= 0 then
            if vim.bo.modified then
                vim.bo.buflisted = true
            end
        elseif vim.bo.modified then
            vim.cmd.update({ bang = vim.v.cmdbang == 1 })
        end
    end)
end

--- Build lookup tables from current_entries: set for membership, index for position
local function build_entry_index(entries)
    local set, index = {}, {}
    for i, entry in ipairs(entries) do
        local key = entry_id(entry, i)
        set[key] = true
        index[key] = i
    end
    return set, index
end

local function strip_internal_fields(entries)
    for _, entry in ipairs(entries) do
        entry._csub_deleted = nil
        entry._csub_id = nil
        entry._csub_chunks = nil
    end
    return entries
end

--- Apply changes in "replace" mode: edit lines in source files
local function apply_replace(qf_orig, current_entries, new_text_lines)
    local _, current_index = build_entry_index(current_entries)
    local dirty_bufnrs = {}

    for _, entry in ipairs(qf_orig) do
        local key = entry_id(entry)
        local line_idx = current_index[key]

        -- If entry is not in current_entries, it was deleted
        if not line_idx or line_idx > #new_text_lines then
            entry._csub_deleted = true
            goto continue
        end

        local new_text = new_text_lines[line_idx]
        if entry.text == new_text then
            goto continue
        end

        if not (entry.bufnr and entry.bufnr ~= 0) then
            entry.text = new_text
            goto continue
        end

        ensure_loaded(entry.bufnr)

        local current_line = buf_get_lines(entry.bufnr, entry.lnum - 1, entry.lnum, false)[1] or ""
        local original_text = utils.chomp(entry.text)
        if current_line ~= original_text then
            if current_line ~= new_text then
                utils.echoerr(("csub: text can't be changed: %s:%d"):format(
                    vim.fn.bufname(entry.bufnr), entry.lnum))
            end
        else
            buf_set_lines(entry.bufnr, entry.lnum - 1, entry.lnum, false, { new_text })
            entry.text = new_text
            current_entries[line_idx].text = new_text
            dirty_bufnrs[entry.bufnr] = true
        end

        ::continue::
    end

    for buf in pairs(dirty_bufnrs) do
        save_buffer(buf)
    end
end

--- Apply changes in "buffers" mode: close deleted buffers, ignore text edits
local function apply_buffers(qf_orig, current_entries)
    local current_set = build_entry_index(current_entries)
    local buffers_to_close = {}

    for _, entry in ipairs(qf_orig) do
        if not current_set[entry_id(entry)] then
            entry._csub_deleted = true
            local buf = entry.bufnr
            if buf and buf ~= 0 and buf_is_valid(buf) then
                buffers_to_close[buf] = true
            end
        end
    end

    local bang = vim.v.cmdbang == 1
    for buf in pairs(buffers_to_close) do
        if buf_is_valid(buf) then
            local ok, err = pcall(vim.cmd.bdelete, { args = { buf }, bang = bang })
            if not ok then
                utils.echoerr(("csub: Failed to close buffer %s: %s"):format(
                    vim.fn.bufname(buf), err))
            end
        end
    end
end

function M.apply(bufnr, winid, source_bufnr)
    local state = buffer.get_state(bufnr) or { orig = {}, current = {}, lines = {} }
    local qf_stored = state.orig
    local current_entries = state.current
    local scope = state.scope
    local full_orig_stored = state.full_orig or qf_stored
    local mode = vim.b[bufnr].csub_mode or "replace"
    local target = {
        kind = vim.b[bufnr].csub_target_kind or "qf",
        winid = vim.b[bufnr].csub_target_winid or 0,
    }
    if target.winid == 0 then target.winid = nil end
    local qf_orig = vim.deepcopy(qf_stored, true)
    local new_text_lines = buf_get_lines(bufnr, 0, -1, false)

    if #new_text_lines > #qf_orig then
        utils.echoerr(("csub: Cannot add lines (list: %d, buffer: %d)"):format(#qf_orig, #new_text_lines))
        return
    end

    local desired_line = (winid and win_is_valid(winid))
        and win_get_cursor(winid)[1] or 1
    local saved_view = view.save(winid, bufnr)

    vim.bo[bufnr].modified = false
    if mode == "buffers" then
        apply_buffers(qf_orig, current_entries)
    else
        apply_replace(qf_orig, current_entries, new_text_lines)
    end

    local survivors = vim.iter(qf_orig):filter(function(e)
        return not e._csub_deleted
    end):totable()

    -- Build the full new list. When scoped, splice survivors into the
    -- original surrounding entries; otherwise the survivors *are* the list.
    local final_list
    local new_scope
    if scope then
        final_list = {}
        for i = 1, scope.first - 1 do
            final_list[#final_list + 1] = full_orig_stored[i]
        end
        for _, e in ipairs(survivors) do
            final_list[#final_list + 1] = e
        end
        local suffix_start = scope.last + 1
        for i = suffix_start, #full_orig_stored do
            final_list[#final_list + 1] = full_orig_stored[i]
        end
        if #survivors == 0 then
            new_scope = nil  -- scope collapsed; drop and show full list next time
        else
            new_scope = { first = scope.first, last = scope.first + #survivors - 1 }
        end
    else
        final_list = survivors
        new_scope = nil
    end

    local items_for_write = strip_internal_fields(vim.deepcopy(final_list, true))
    -- Target the list by id and use the dict form so the title and context
    -- are preserved. The bare setqflist({list}, "r") form clobbers the title
    -- to ":setqflist()", which then breaks mode detection on the next :Csub.
    local target_id = vim.b[bufnr].csub_list_id or list.current_id(target)
    list.set(target, "r", { id = target_id, items = items_for_write })

    local list_info = list.get(target, { id = target_id, qfbufnr = 1 })
    local list_id = list_info and list_info.id or target_id
    local signature = list.signature(target, list_id, new_scope)
    buffer.populate(bufnr, final_list, mode, {
        list_id = list_id,
        target = target,
        signature = signature,
        scope = new_scope,
    })

    local target_listbuf = list_info and list_info.qfbufnr or source_bufnr
    if not target_listbuf then return end

    vim.schedule(function()
        local win = (window.find_window_with_buf(bufnr) or winid)
        if not (win and win_is_valid(win)) then
            win = window.ensure_list_window(target)
        end
        if win and buf_is_valid(target_listbuf) then
            window.use_buf(win, target_listbuf)
            local line = math.max(1, math.min(desired_line, buf_line_count(target_listbuf)))
            view.restore(win, target_listbuf, saved_view, line)
        end
    end)
end

return M
