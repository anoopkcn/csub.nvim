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
                utils.echoerr(string.format("csub: Original text has changed: %s:%d", vim.fn.bufname(entry.bufnr),
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

    local target_win = window.find_window_with_buf(bufnr) or winid
    local fallback_qfwin = window.ensure_quickfix_window()
    local target_qfbuf = qf_bufnr

    if not (target_qfbuf and vim.api.nvim_buf_is_valid(target_qfbuf)) and fallback_qfwin then
        target_qfbuf = vim.api.nvim_win_get_buf(fallback_qfwin)
    end

    if target_win and target_qfbuf then
        window.use_buf(target_win, target_qfbuf)
    elseif fallback_qfwin and target_qfbuf then
        window.use_buf(fallback_qfwin, target_qfbuf)
    end
end

return M
