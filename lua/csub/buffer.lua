local fmt = require("csub.format")
local utils = require("csub.utils")
local window = require("csub.window")

local ns = vim.api.nvim_create_namespace("csub_meta")

local M = {}

local function set_metadata(bufnr, entries)
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    for idx, entry in ipairs(entries) do
        if idx > line_count then break end
        vim.api.nvim_buf_set_extmark(bufnr, ns, idx - 1, 0, {
            virt_text = fmt.format_meta_chunks(entry, { width = fmt.META_WIDTH }),
            virt_text_pos = "inline",
            hl_mode = "combine",
        })
    end
end

--- Update current_entries by removing entries at deleted line indices
local function remove_deleted_entries(current_entries, previous, lines)
    local new_entries = {}
    local curr_idx = 1
    for prev_idx, prev_line in ipairs(previous) do
        if curr_idx <= #lines and lines[curr_idx] == prev_line then
            new_entries[#new_entries + 1] = current_entries[prev_idx]
            curr_idx = curr_idx + 1
        end
    end
    return new_entries
end

local function on_changed(bufnr)
    local orig_entries = vim.b[bufnr].csub_orig_qflist or {}
    local current_entries = vim.b[bufnr].csub_current_entries or orig_entries
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local previous = vim.b[bufnr].csub_lines or lines

    -- Reject additions (more lines than original)
    if #lines > #orig_entries then
        vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(bufnr) then return end
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, previous)
            set_metadata(bufnr, current_entries)
            utils.silence_modified(bufnr)
            vim.notify("[csub] Cannot add lines beyond quickfix entries.", vim.log.levels.WARN)
        end)
        return
    end

    -- Update current_entries if lines were deleted
    if #lines < #previous then
        current_entries = remove_deleted_entries(current_entries, previous, lines)
        vim.b[bufnr].csub_current_entries = current_entries
    end

    vim.b[bufnr].csub_lines = lines
    set_metadata(bufnr, current_entries)
    utils.silence_modified(bufnr)
end

function M.populate(bufnr, qflist, mode)
    qflist = qflist or {}
    vim.b[bufnr].csub_orig_qflist = qflist
    vim.b[bufnr].csub_current_entries = vim.deepcopy(qflist)
    vim.b[bufnr].csub_mode = mode or "replace"

    local lines = {}
    for i, entry in ipairs(qflist) do
        lines[i] = utils.chomp(entry.text)
    end

    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    set_metadata(bufnr, qflist)
    vim.b[bufnr].csub_lines = lines
    vim.bo[bufnr].modified = false
end

function M.ensure_buffer(state, winid, qf_bufnr, on_write)
    if not (winid and vim.api.nvim_win_is_valid(winid)) then
        return
    end

    -- Safety check: only allow csub buffer in quickfix windows
    if not window.is_quickfix_window(winid) then
        return
    end

    -- First check if state has a valid csub buffer
    if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
        local is_csub = vim.b[state.bufnr].csub_buffer
        if not is_csub then
            state.bufnr = nil
        end
    end

    -- If state doesn't have a valid buffer, search for existing csub buffer
    if not (state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr)) then
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].csub_buffer then
                state.bufnr = buf
                break
            end
        end
    end

    local bufnr = state.bufnr

    -- If we have a valid buffer, reuse it
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        vim.b[bufnr].csub_qf_bufnr = qf_bufnr
        vim.b[bufnr].csub_qf_winid = winid
        window.use_buf(winid, bufnr)
        window.apply_window_opts(winid)
        return bufnr
    end

    -- Create a new buffer only if no existing buffer found
    bufnr = vim.api.nvim_create_buf(false, false)
    state.bufnr = bufnr

    -- Set buftype FIRST to prevent file association
    vim.bo[bufnr].buftype = "acwrite"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].bufhidden = "hide"
    vim.bo[bufnr].filetype = "csub"
    vim.api.nvim_buf_set_name(bufnr, "[csub]")

    -- Mark this as a csub buffer for reliable identification
    vim.b[bufnr].csub_buffer = true

    -- Display the new buffer in the target window
    window.use_buf(winid, bufnr)

    vim.b[bufnr].csub_qf_bufnr = qf_bufnr
    vim.b[bufnr].csub_qf_winid = winid
    vim.api.nvim_create_autocmd("BufWriteCmd", {
        buffer = bufnr,
        nested = true,
        callback = function()
            on_write(bufnr, vim.b[bufnr].csub_qf_winid, vim.b[bufnr].csub_qf_bufnr)
        end,
    })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
        buffer = bufnr,
        callback = function()
            on_changed(bufnr)
        end,
    })
    vim.api.nvim_create_autocmd("BufWinEnter", {
        buffer = bufnr,
        callback = function()
            window.apply_window_opts(vim.api.nvim_get_current_win())
        end,
    })
    return bufnr
end

return M
