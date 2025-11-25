local fmt = require("csub.format")
local utils = require("csub.utils")
local window = require("csub.window")

local ns = vim.api.nvim_create_namespace("csub_meta")

local M = {}

local function set_metadata(bufnr, qf_entries)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    for idx, entry in ipairs(qf_entries) do
        if idx > line_count then
            break
        end
        local meta = fmt.format_meta(entry, { width = fmt.META_WIDTH })
        vim.api.nvim_buf_set_extmark(bufnr, ns, idx - 1, 0, {
            virt_text = { { meta, "Comment" } },
            virt_text_pos = "inline",
            hl_mode = "combine",
        })
    end
end

local function on_changed(bufnr)
    local qf_entries = vim.b[bufnr].csub_orig_qflist or {}
    local target = #qf_entries
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local previous = vim.b[bufnr].csub_lines or lines

    if #lines ~= target then
        vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(bufnr) then
                return
            end
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, previous)
            set_metadata(bufnr, qf_entries)
            utils.silence_modified(bufnr)
            vim.notify("[csub] Line count must remain unchanged.", vim.log.levels.WARN)
        end)
        return
    end

    vim.b[bufnr].csub_lines = lines
    set_metadata(bufnr, qf_entries)
    utils.silence_modified(bufnr)
end

function M.populate(bufnr, qflist)
    vim.b[bufnr].csub_orig_qflist = qflist
    local lines = {}
    for _, entry in ipairs(qflist or {}) do
        table.insert(lines, utils.chomp(entry.text))
    end
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    set_metadata(bufnr, qflist or {})
    vim.b[bufnr].csub_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    vim.bo[bufnr].modified = false
end

function M.ensure_buffer(state, open_cmd, on_write)
    local bufnr = state.bufnr
    local cmd = (open_cmd and open_cmd ~= "") and open_cmd or "new"

    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        local wins = vim.fn.win_findbuf(bufnr)
        if wins[1] then
            vim.api.nvim_set_current_win(wins[1])
            window.apply_window_opts(wins[1])
        else
            vim.cmd(cmd)
            vim.api.nvim_set_current_buf(bufnr)
            window.apply_window_opts(vim.api.nvim_get_current_win())
        end
        return bufnr
    end

    vim.cmd(cmd)
    vim.cmd("enew")
    bufnr = vim.api.nvim_get_current_buf()
    state.bufnr = bufnr
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].bufhidden = "hide"
    vim.bo[bufnr].buftype = "acwrite"
    vim.bo[bufnr].filetype = "csub"
    vim.api.nvim_buf_set_name(bufnr, "[csub]")
    vim.api.nvim_create_autocmd("BufWriteCmd", {
        buffer = bufnr,
        nested = true,
        callback = function()
            on_write(bufnr)
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
