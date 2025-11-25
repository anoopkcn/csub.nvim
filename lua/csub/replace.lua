local utils = require("csub.utils")
local window = require("csub.window")

local M = {}

local function compute_after_cmd()
    local no_save = vim.g.csub_no_save or vim.g.csubstitute_no_save or 0
    if vim.o.hidden and no_save ~= 0 then
        return "if &modified | setlocal buflisted | endif"
    end
    return "update" .. (vim.v.cmdbang == 1 and "!" or "")
end

function M.apply(bufnr, winid, qf_bufnr)
    local qf_orig = vim.b[bufnr].csub_orig_qflist or {}
    local new_text_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local desired_line = 1
    if winid and vim.api.nvim_win_is_valid(winid) then
        desired_line = vim.api.nvim_win_get_cursor(winid)[1]
    end

    if #new_text_lines ~= #qf_orig then
        utils.echoerr(string.format("csub: Illegal edit: line number was changed from %d to %d.", #qf_orig,
            #new_text_lines))
        return
    end

    vim.bo[bufnr].modified = false

    local after_cmd = compute_after_cmd()
    local prev_bufnr = -1

    for i, entry in ipairs(qf_orig) do
        local new_text = new_text_lines[i]
        if entry.text == new_text then
            goto continue
        end

        if not (entry.bufnr and entry.bufnr ~= 0) then
            entry.text = new_text
            goto continue
        end

        if prev_bufnr ~= entry.bufnr then
            if prev_bufnr ~= -1 then
                vim.cmd(after_cmd)
            end
            vim.cmd(string.format("%dbuffer", entry.bufnr))
        end

        local current_line = (vim.api.nvim_buf_get_lines(entry.bufnr, entry.lnum - 1, entry.lnum, false)[1]) or ""
        local original_text = utils.chomp(entry.text)
        if current_line ~= original_text then
            if current_line ~= new_text then
                utils.echoerr(string.format("csub: text can't be changed: %s:%d", vim.fn.bufname(entry.bufnr),
                    entry.lnum))
            end
        else
            vim.api.nvim_buf_set_lines(entry.bufnr, entry.lnum - 1, entry.lnum, false, { new_text })
            entry.text = new_text
        end

        prev_bufnr = entry.bufnr
        ::continue::
    end

    vim.cmd(after_cmd)
    vim.cmd(string.format("%dbuffer", qf_bufnr))
    vim.fn.setqflist(qf_orig, "r")

    local qf_info = vim.fn.getqflist({ qfbufnr = 0 })
    local target_qfbuf = qf_info and qf_info.qfbufnr or qf_bufnr

    local target_win = window.find_window_with_buf(bufnr) or winid
    local qfwin = window.find_quickfix_window() or window.ensure_quickfix_window()

    if target_qfbuf then
        vim.schedule(function()
            if target_win and vim.api.nvim_win_is_valid(target_win) and vim.api.nvim_buf_is_valid(target_qfbuf) then
                window.use_buf(target_win, target_qfbuf)
                local lc = vim.api.nvim_buf_line_count(target_qfbuf)
                local l = math.max(1, math.min(desired_line, lc))
                pcall(vim.api.nvim_win_set_cursor, target_win, { l, 0 })
            elseif qfwin and vim.api.nvim_win_is_valid(qfwin) and vim.api.nvim_buf_is_valid(target_qfbuf) then
                window.use_buf(qfwin, target_qfbuf)
                local lc = vim.api.nvim_buf_line_count(target_qfbuf)
                local l = math.max(1, math.min(desired_line, lc))
                pcall(vim.api.nvim_win_set_cursor, qfwin, { l, 0 })
            end
        end)
    end
end

return M
