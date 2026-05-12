local buffer = require("csub.buffer")
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
        entry._csub_path = nil
        entry._csub_new = nil
    end
    return entries
end

--- Apply changes in "replace" mode: edit lines in source files
local function apply_replace(qf_orig, current_entries, new_text_lines)
    local _, current_index = build_entry_index(current_entries)
    local prev_bufnr = -1

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

        if prev_bufnr ~= entry.bufnr then
            if prev_bufnr ~= -1 then
                save_buffer(prev_bufnr)
            end
            ensure_loaded(entry.bufnr)
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
            current_entries[line_idx].text = new_text
        end

        prev_bufnr = entry.bufnr
        ::continue::
    end

    save_buffer(prev_bufnr)
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

local function resolve_abs(path)
    if path == nil or path == "" then return path end
    if path:sub(1, 1) == "/" then return path end
    local cwd = vim.uv.cwd() or ""
    return vim.fs.joinpath(cwd, path)
end

local function find_buf_for_path(path)
    if not path or path == "" then return -1 end
    local bnr = vim.fn.bufnr(path)
    if bnr ~= -1 and buf_is_valid(bnr) then return bnr end
    local resolved = vim.uv.fs_realpath(path)
    if resolved and resolved ~= path then
        bnr = vim.fn.bufnr(resolved)
        if bnr ~= -1 and buf_is_valid(bnr) then return bnr end
    end
    return -1
end

--- Apply changes in "files" mode: create/rename/delete files and folders.
--- Returns true on success, false if refused (destructive ops pending without :w!).
local function apply_files(qf_orig, current_entries, new_text_lines, bang)
    local current_ids = {}
    for _, e in ipairs(current_entries) do
        if e._csub_id then current_ids[e._csub_id] = true end
    end

    local deletes, renames, creates = {}, {}, {}

    for _, entry in ipairs(qf_orig) do
        if entry._csub_id and not current_ids[entry._csub_id] then
            local old_rel = entry._csub_path or ""
            local old_abs = resolve_abs(old_rel)
            deletes[#deletes + 1] = {
                entry = entry,
                rel = old_rel,
                abs = old_abs,
                is_dir = old_abs and vim.fn.isdirectory(old_abs) == 1,
            }
        end
    end

    for line_idx, entry in ipairs(current_entries) do
        local line = new_text_lines[line_idx] or ""
        if entry._csub_new then
            if line ~= "" then
                local abs = resolve_abs(line)
                local is_folder = line:sub(-1) == "/"
                creates[#creates + 1] = {
                    entry = entry,
                    rel = line,
                    abs = abs,
                    is_folder = is_folder,
                    overwrite = not is_folder and vim.uv.fs_stat(abs) ~= nil,
                }
            end
        elseif entry._csub_id then
            local old_rel = entry._csub_path or ""
            if line ~= "" and line ~= old_rel then
                local old_abs = resolve_abs(old_rel)
                local new_abs = resolve_abs(line)
                renames[#renames + 1] = {
                    entry = entry,
                    old_rel = old_rel,
                    old_abs = old_abs,
                    new_rel = line,
                    new_abs = new_abs,
                    overwrite = new_abs ~= old_abs and vim.uv.fs_stat(new_abs) ~= nil,
                    is_dir = old_abs and vim.fn.isdirectory(old_abs) == 1,
                }
            end
        end
    end

    if not bang then
        local destructive = {}
        for _, op in ipairs(deletes) do
            destructive[#destructive + 1] = string.format("delete %s%s",
                op.rel, op.is_dir and "/" or "")
        end
        for _, op in ipairs(renames) do
            if op.overwrite then
                destructive[#destructive + 1] = string.format("overwrite %s → %s",
                    op.old_rel, op.new_rel)
            end
        end
        for _, op in ipairs(creates) do
            if op.overwrite then
                destructive[#destructive + 1] = string.format("overwrite %s", op.rel)
            end
        end
        if #destructive > 0 then
            vim.notify("[csub] Use :w! to apply: " .. table.concat(destructive, ", "),
                vim.log.levels.WARN)
            return false
        end
    end

    for _, op in ipairs(deletes) do
        local flags = op.is_dir and "rf" or ""
        local rc = vim.fn.delete(op.abs, flags)
        if rc == -1 then
            utils.echoerr(("csub: Failed to delete %s"):format(op.rel))
        else
            op.entry._csub_deleted = true
            local bnr = find_buf_for_path(op.abs)
            if bnr ~= -1 then
                pcall(vim.cmd.bdelete, { args = { bnr }, bang = true })
            end
        end
    end

    for _, op in ipairs(renames) do
        local parent = vim.fs.dirname(op.new_abs)
        if parent and parent ~= "" then
            vim.fn.mkdir(parent, "p")
        end
        local rc = vim.fn.rename(op.old_abs, op.new_abs)
        if rc ~= 0 then
            utils.echoerr(("csub: Failed to rename %s → %s"):format(op.old_rel, op.new_rel))
        else
            local old_bnr = find_buf_for_path(op.old_abs)
            if old_bnr ~= -1 then
                pcall(vim.api.nvim_buf_set_name, old_bnr, op.new_abs)
                pcall(vim.cmd.checktime, old_bnr)
            end
            op.entry._csub_path = op.new_rel
            op.entry.filename = op.new_abs
            op.entry.bufnr = nil
            op.entry.text = op.new_rel
        end
    end

    for _, op in ipairs(creates) do
        local parent = vim.fs.dirname(op.abs)
        if parent and parent ~= "" then
            vim.fn.mkdir(parent, "p")
        end
        local ok
        if op.is_folder then
            ok = pcall(vim.fn.mkdir, op.abs, "p")
        else
            ok = pcall(vim.fn.writefile, {}, op.abs)
        end
        if not ok then
            utils.echoerr(("csub: Failed to create %s"):format(op.rel))
        else
            op.entry._csub_new = nil
            op.entry._csub_path = op.rel
            op.entry.filename = op.abs
            op.entry.text = op.rel
            op.entry.lnum = op.entry.lnum or 1
            op.entry.col = op.entry.col or 1
        end
    end

    return true
end

function M.apply(bufnr, winid, qf_bufnr)
    local qf_stored = vim.b[bufnr].csub_orig_qflist or {}
    local current_entries = vim.b[bufnr].csub_current_entries or qf_stored
    local mode = vim.b[bufnr].csub_mode or "replace"
    local qf_orig = vim.deepcopy(qf_stored, true)
    local current_copy = vim.deepcopy(current_entries, true)
    local new_text_lines = buf_get_lines(bufnr, 0, -1, false)

    if mode ~= "files" and #new_text_lines > #qf_orig then
        utils.echoerr(("csub: Cannot add lines (quickfix: %d, buffer: %d)"):format(#qf_orig, #new_text_lines))
        return
    end

    local desired_line = (winid and win_is_valid(winid))
        and win_get_cursor(winid)[1] or 1
    local saved_view = view.save(winid, bufnr)

    local filtered_qf
    if mode == "files" then
        local ok = apply_files(qf_orig, current_copy, new_text_lines, vim.v.cmdbang == 1)
        if not ok then
            return
        end
        vim.bo[bufnr].modified = false
        filtered_qf = vim.iter(current_copy):filter(function(e)
            return not e._csub_deleted and not e._csub_new
        end):totable()
    else
        vim.bo[bufnr].modified = false
        if mode == "buffers" then
            apply_buffers(qf_orig, current_entries)
        else
            apply_replace(qf_orig, current_entries, new_text_lines)
        end
        filtered_qf = vim.iter(qf_orig):filter(function(e)
            return not e._csub_deleted
        end):totable()
    end

    local qf_for_write = strip_internal_fields(vim.deepcopy(filtered_qf, true))
    -- Target the qf list by id and use the dict form so the title and context
    -- are preserved. The bare setqflist({list}, "r") form clobbers the title
    -- to ":setqflist()", which then breaks mode detection on the next :Csub.
    local target_id = vim.b[bufnr].csub_qf_id or vim.fn.getqflist({ id = 0 }).id
    vim.fn.setqflist({}, "r", { id = target_id, items = qf_for_write })

    local qf_info = vim.fn.getqflist({ id = target_id, qfbufnr = 1 })
    local qf_id = qf_info and qf_info.id or target_id
    buffer.populate(bufnr, filtered_qf, mode, { qf_id = qf_id })

    local target_qfbuf = qf_info and qf_info.qfbufnr or qf_bufnr
    if not target_qfbuf then return end

    vim.schedule(function()
        local win = (window.find_window_with_buf(bufnr) or winid)
        if not (win and win_is_valid(win)) then
            win = window.find_quickfix_window()
        end
        if not (win and win_is_valid(win)) then
            win = window.ensure_quickfix_window()
        end
        if win and buf_is_valid(target_qfbuf) then
            window.use_buf(win, target_qfbuf)
            local line = math.max(1, math.min(desired_line, buf_line_count(target_qfbuf)))
            view.restore(win, target_qfbuf, saved_view, line)
        end
    end)
end

return M
