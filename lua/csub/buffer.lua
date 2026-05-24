local fmt = require("csub.format")
local utils = require("csub.utils")
local window = require("csub.window")

-- Cache frequently used API functions
local buf_is_valid = vim.api.nvim_buf_is_valid
local win_is_valid = vim.api.nvim_win_is_valid
local buf_get_lines = vim.api.nvim_buf_get_lines
local buf_set_lines = vim.api.nvim_buf_set_lines
local buf_line_count = vim.api.nvim_buf_line_count
local buf_set_extmark = vim.api.nvim_buf_set_extmark
local buf_clear_namespace = vim.api.nvim_buf_clear_namespace
local buf_attach = vim.api.nvim_buf_attach
local create_buf = vim.api.nvim_create_buf
local buf_set_name = vim.api.nvim_buf_set_name
local list_bufs = vim.api.nvim_list_bufs
local create_autocmd = vim.api.nvim_create_autocmd

local ns = vim.api.nvim_create_namespace("csub_meta")
local dirty_ns = vim.api.nvim_create_namespace("csub_dirty")

local M = {}

-- Per-csub-buffer state. Holds the heavy tables that would otherwise be
-- deep-copied across the Lua/vimscript boundary every time we read them
-- from vim.b. Scalars (mode, list_id, dirty, signature, etc.) stay in
-- vim.b so they remain externally inspectable.
--
-- Shape: { orig, current, lines, scope (reserved) }
--   orig    - immutable original entries (clone of input qflist)
--   current - live editable entries; same _csub_id as orig for tracking
--   lines   - cached buffer text (lines[i] is row i's text)
local state_by_bufnr = {}

function M.get_state(bufnr)
    return state_by_bufnr[bufnr]
end

function M.clear_state(bufnr)
    state_by_bufnr[bufnr] = nil
end

local function clone_entries(qflist)
    local entries = vim.deepcopy(qflist or {}, true)
    for i, entry in ipairs(entries) do
        entry._csub_id = i
        -- Cache the metadata chunks once per entry. Each entry's chunks
        -- depend only on bufnr/filename/lnum/col, which don't change
        -- during an edit session, so the hot-path set_metadata reduces to
        -- bare extmark calls.
        entry._csub_chunks = fmt.format_meta_chunks(entry, { width = fmt.META_WIDTH })
    end
    return entries
end

local function set_metadata(bufnr, entries)
    buf_clear_namespace(bufnr, ns, 0, -1)
    local line_count = buf_line_count(bufnr)
    for idx, entry in ipairs(entries) do
        if idx > line_count then break end
        buf_set_extmark(bufnr, ns, idx - 1, 0, {
            virt_text = entry._csub_chunks,
            virt_text_pos = "inline",
            hl_mode = "combine",
            strict = false,
        })
    end
end

local function shrink_entry_range(current_entries, firstline, lastline, new_lastline)
    if lastline <= firstline then
        return current_entries
    end

    local keep_in_range = math.max(new_lastline - firstline, 0)
    local new_entries = {}
    for idx, entry in ipairs(current_entries) do
        local line_idx = idx - 1
        local in_prefix = line_idx < firstline
        local in_kept_range = line_idx >= firstline and line_idx < (firstline + keep_in_range)
        local in_suffix = line_idx >= lastline
        if in_prefix or in_kept_range or in_suffix then
            new_entries[#new_entries + 1] = entry
        end
    end
    return new_entries
end

--- Rebuild "~" signs for all dirty rows. Each row's originating entry is
--- looked up by _csub_id in state.orig_by_id for O(1) compare. We rebuild
--- the whole namespace because extmarks drift through nvim_buf_set_lines
--- replacements; cheaper to re-render than to track migration.
local function refresh_dirty_signs(bufnr, state)
    buf_clear_namespace(bufnr, dirty_ns, 0, -1)
    local lines = state.lines
    local current = state.current
    local orig_by_id = state.orig_by_id or {}
    for i = 1, #lines do
        local entry = current[i]
        if entry and entry._csub_id then
            local orig_entry = orig_by_id[entry._csub_id]
            if orig_entry and lines[i] ~= utils.chomp(orig_entry.text) then
                buf_set_extmark(bufnr, dirty_ns, i - 1, 0, {
                    sign_text = "~",
                    sign_hl_group = "CsubDirtyLine",
                    strict = false,
                })
            end
        end
    end
end

local function update_dirty(bufnr, state)
    refresh_dirty_signs(bufnr, state)

    local lines, orig, current = state.lines, state.orig, state.current
    local dirty = (#lines ~= #orig) or (#current ~= #orig)
    if not dirty then
        for idx, entry in ipairs(orig) do
            if lines[idx] ~= utils.chomp(entry.text) then
                dirty = true
                break
            end
        end
    end
    vim.b[bufnr].csub_dirty = dirty
end

local function on_lines(bufnr, firstline, lastline, new_lastline)
    if not buf_is_valid(bufnr) or vim.b[bufnr].csub_updating then
        return
    end

    local state = state_by_bufnr[bufnr]
    if not state then return end

    local previous_lines = state.lines
    local previous_entries = state.current
    local previous_dirty = vim.b[bufnr].csub_dirty or false
    local delta = new_lastline - lastline

    -- Reject additions: csub buffer maintains a 1:1 line/entry mapping.
    -- Set csub_updating synchronously so any keystroke landing between now
    -- and the scheduled rollback early-returns at the top of on_lines.
    if delta > 0 then
        vim.b[bufnr].csub_updating = true
        vim.schedule(function()
            if not buf_is_valid(bufnr) then return end

            buf_set_lines(bufnr, 0, -1, false, previous_lines)
            vim.b[bufnr].csub_updating = false

            -- state may have been swapped out by a re-populate while we
            -- were waiting; only restore if it's still the same instance.
            local s = state_by_bufnr[bufnr]
            if s then
                s.current = previous_entries
                s.lines = previous_lines
            end
            vim.b[bufnr].csub_dirty = previous_dirty
            set_metadata(bufnr, previous_entries)
            utils.silence_modified(bufnr)
            vim.notify("[csub] Cannot add lines beyond quickfix entries.", vim.log.levels.WARN)
        end)
        return
    end

    local current_entries = previous_entries
    if delta < 0 then
        current_entries = shrink_entry_range(previous_entries, firstline, lastline, new_lastline)
        state.current = current_entries
    end

    state.lines = buf_get_lines(bufnr, 0, -1, false)
    set_metadata(bufnr, current_entries)
    update_dirty(bufnr, state)
    utils.silence_modified(bufnr)
end

function M.populate(bufnr, qflist, mode, opts)
    opts = opts or {}
    mode = mode or "replace"
    local scope = opts.scope

    -- full_orig is the entire input list (used for round-trip reassembly
    -- on write when scope is set). orig/current/lines reflect only the
    -- scoped slice the user sees and edits.
    local full_orig = clone_entries(qflist)
    local orig_entries
    if scope then
        orig_entries = {}
        for i = scope.first, scope.last do
            local entry = full_orig[i]
            if entry then orig_entries[#orig_entries + 1] = entry end
        end
    else
        orig_entries = full_orig
    end

    -- Shallow per-entry copy is enough for `current`: qf entry values
    -- (bufnr, lnum, col, text, _csub_id, ...) are scalars, and apply only
    -- mutates `.text`. Avoids a second full deepcopy on large lists.
    local current_entries = {}
    for i, entry in ipairs(orig_entries) do
        local copy = {}
        for k, v in pairs(entry) do copy[k] = v end
        current_entries[i] = copy
    end

    local lines = {}
    for i, entry in ipairs(current_entries) do
        lines[i] = utils.chomp(entry.text)
    end

    local orig_by_id = {}
    for _, entry in ipairs(orig_entries) do
        orig_by_id[entry._csub_id] = entry
    end

    -- Always assign a fresh state table so any closure holding the old
    -- reference becomes harmlessly stale.
    state_by_bufnr[bufnr] = {
        full_orig = full_orig,
        orig = orig_entries,
        current = current_entries,
        lines = lines,
        orig_by_id = orig_by_id,
        scope = scope,
    }

    vim.b[bufnr].csub_mode = mode
    vim.b[bufnr].csub_list_id = opts.list_id
    vim.b[bufnr].csub_target_kind = opts.target and opts.target.kind or "qf"
    vim.b[bufnr].csub_target_winid = opts.target and opts.target.winid or 0
    vim.b[bufnr].csub_list_signature = opts.signature

    vim.b[bufnr].csub_updating = true
    vim.bo[bufnr].modifiable = true
    buf_set_lines(bufnr, 0, -1, false, lines)
    vim.b[bufnr].csub_updating = false

    set_metadata(bufnr, current_entries)
    buf_clear_namespace(bufnr, dirty_ns, 0, -1)
    vim.b[bufnr].csub_dirty = false
    vim.bo[bufnr].modified = false
end

function M.ensure_buffer(state, winid, source_bufnr, on_write)
    if not (winid and win_is_valid(winid)) then
        return
    end

    -- Safety check: only allow csub buffer in quickfix-typed windows
    if not window.is_quickfix_window(winid) then
        return
    end

    if state.bufnr and buf_is_valid(state.bufnr) then
        local is_csub = vim.b[state.bufnr].csub_buffer
        if not is_csub then
            state.bufnr = nil
        end
    end

    if not (state.bufnr and buf_is_valid(state.bufnr)) then
        for _, buf in ipairs(list_bufs()) do
            if buf_is_valid(buf) and vim.b[buf].csub_buffer then
                state.bufnr = buf
                break
            end
        end
    end

    local bufnr = state.bufnr

    if bufnr and buf_is_valid(bufnr) then
        vim.b[bufnr].csub_source_bufnr = source_bufnr
        vim.b[bufnr].csub_source_winid = winid
        window.use_buf(winid, bufnr)
        window.apply_window_opts(winid)
        return bufnr
    end

    bufnr = create_buf(false, false)
    state.bufnr = bufnr

    vim.bo[bufnr].buftype = "acwrite"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].bufhidden = "hide"
    vim.bo[bufnr].filetype = "csub"
    buf_set_name(bufnr, "[csub]")

    vim.b[bufnr].csub_buffer = true

    window.use_buf(winid, bufnr)

    vim.b[bufnr].csub_source_bufnr = source_bufnr
    vim.b[bufnr].csub_source_winid = winid
    create_autocmd("BufWriteCmd", {
        buffer = bufnr,
        nested = true,
        callback = function()
            on_write(bufnr, vim.b[bufnr].csub_source_winid, vim.b[bufnr].csub_source_bufnr)
        end,
    })
    buf_attach(bufnr, false, {
        on_lines = function(_, changed_bufnr, _, firstline, lastline, new_lastline)
            on_lines(changed_bufnr, firstline, lastline, new_lastline)
        end,
    })
    create_autocmd("BufWinEnter", {
        buffer = bufnr,
        callback = function()
            window.apply_window_opts(vim.api.nvim_get_current_win())
        end,
    })
    create_autocmd("BufWipeout", {
        buffer = bufnr,
        callback = function() M.clear_state(bufnr) end,
    })
    return bufnr
end

return M
