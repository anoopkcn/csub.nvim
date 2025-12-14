local utils = require("csub.utils")
local view = require("csub.view")
local window = require("csub.window")

-- Cache frequently used API functions
local buf_is_valid = vim.api.nvim_buf_is_valid
local win_is_valid = vim.api.nvim_win_is_valid
local buf_get_lines = vim.api.nvim_buf_get_lines
local buf_set_lines = vim.api.nvim_buf_set_lines
local buf_line_count = vim.api.nvim_buf_line_count
local set_current_buf = vim.api.nvim_set_current_buf
local win_get_cursor = vim.api.nvim_win_get_cursor

local M = {}

--- Generate unique key for an entry
local function entry_key(entry)
    return (entry.bufnr or 0) * 1000000 + (entry.lnum or 0)
end

local function save_current_buffer()
    local no_save = vim.g.csub_no_save or vim.g.csubstitute_no_save or 0
    if vim.o.hidden and no_save ~= 0 then
        if vim.bo.modified then
            vim.bo.buflisted = true
        end
    else
        if vim.bo.modified then
            vim.cmd.update({ bang = vim.v.cmdbang == 1 })
        end
    end
end

--- Build lookup tables from current_entries: set for membership, index for position
local function build_entry_index(entries)
    local set, index = {}, {}
    for i, entry in ipairs(entries) do
        local key = entry_key(entry)
        set[key] = true
        index[key] = i
    end
    return set, index
end

--- Apply changes in "replace" mode: edit lines in source files
local function apply_replace(qf_orig, current_entries, new_text_lines)
    local current_set, current_index = build_entry_index(current_entries)
    local prev_bufnr = -1

    for _, entry in ipairs(qf_orig) do
        local key = entry_key(entry)
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

        if prev_bufnr ~= entry.bufnr then
            if prev_bufnr ~= -1 then
                save_current_buffer()
            end
            set_current_buf(entry.bufnr)
        end

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
        end

        prev_bufnr = entry.bufnr
        ::continue::
    end

    save_current_buffer()
end

--- Apply changes in "buffers" mode: close deleted buffers, ignore text edits
local function apply_buffers(qf_orig, current_entries)
    local current_set = build_entry_index(current_entries)
    local buffers_to_close = {}

    for _, entry in ipairs(qf_orig) do
        if not current_set[entry_key(entry)] then
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

function M.apply(bufnr, winid, qf_bufnr)
    local qf_stored = vim.b[bufnr].csub_orig_qflist or {}
    local current_entries = vim.b[bufnr].csub_current_entries or qf_stored
    local mode = vim.b[bufnr].csub_mode or "replace"
    local qf_orig = vim.deepcopy(qf_stored)
    local new_text_lines = buf_get_lines(bufnr, 0, -1, false)

    if #new_text_lines > #qf_orig then
        utils.echoerr(("csub: Cannot add lines (quickfix: %d, buffer: %d)"):format(#qf_orig, #new_text_lines))
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

    set_current_buf(qf_bufnr)

    -- vim.iter available in 0.10+
    local filtered_qf = vim.iter(qf_orig):filter(function(e)
        return not e._csub_deleted
    end):totable()
    vim.fn.setqflist(filtered_qf, "r")

    local qf_info = vim.fn.getqflist({ qfbufnr = 1 })
    local target_qfbuf = qf_info and qf_info.qfbufnr or qf_bufnr
    if not target_qfbuf then return end

    local target_win = window.find_window_with_buf(bufnr) or winid
    local qfwin = window.find_quickfix_window() or window.ensure_quickfix_window()

    vim.schedule(function()
        local win = (target_win and win_is_valid(target_win) and target_win)
            or (qfwin and win_is_valid(qfwin) and qfwin)
        if win and buf_is_valid(target_qfbuf) then
            window.use_buf(win, target_qfbuf)
            local line = math.max(1, math.min(desired_line, buf_line_count(target_qfbuf)))
            view.restore(win, target_qfbuf, saved_view, line)
        end
    end)
end

return M
