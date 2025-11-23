local fmt = require("csubstitute.format")

local M = {}

local state = {
    bufnr = nil,
}
local ns = vim.api.nvim_create_namespace("csubstitute_meta")

local function chomp(str)
    local s = str or ""
    local without_cr = s:gsub("\r$", "")
    return without_cr
end

local function with_buf(bufnr, fn)
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        fn(bufnr)
    end
end

local function silence_modified(bufnr)
    with_buf(bufnr, function(b)
        vim.bo[b].modified = false
    end)
end

local function apply_window_opts(winid)
    if winid and vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_set_option_value("wrap", false, { scope = "local", win = winid })
    end
end

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
    local qf_entries = vim.b[bufnr].csubstitute_orig_qflist or {}
    local target = #qf_entries
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local previous = vim.b[bufnr].csubstitute_lines or lines

    if #lines ~= target then
        vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(bufnr) then
                return
            end
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, previous)
            set_metadata(bufnr, qf_entries)
            silence_modified(bufnr)
            vim.notify("[csubstitute] Line count must remain unchanged.", vim.log.levels.WARN)
        end)
        return
    end

    vim.b[bufnr].csubstitute_lines = lines
    set_metadata(bufnr, qf_entries)
    silence_modified(bufnr)
end

local function echoerr(msg)
    vim.api.nvim_echo({ { msg, "ErrorMsg" } }, true, {})
end

local function close_list_windows()
    for _, win in ipairs(vim.fn.getwininfo()) do
        if win.quickfix == 1 then
            pcall(vim.api.nvim_win_close, win.winid, false)
        end
    end
end

local function populate_buffer(bufnr, qflist)
    vim.b[bufnr].csubstitute_orig_qflist = qflist
    local lines = {}
    for _, entry in ipairs(qflist or {}) do
        table.insert(lines, chomp(entry.text))
    end
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    set_metadata(bufnr, qflist or {})
    vim.b[bufnr].csubstitute_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    vim.bo[bufnr].modified = false
end

local function do_replace(bufnr)
    local qf_orig = vim.b[bufnr].csubstitute_orig_qflist or {}
    local new_text_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    if #new_text_lines ~= #qf_orig then
        echoerr(string.format("csubstitute: Illegal edit: line number was changed from %d to %d.", #qf_orig,
            #new_text_lines))
        return
    end

    vim.bo[bufnr].modified = false

    local after_cmd
    if vim.o.hidden and (vim.g.csubstitute_no_save or 0) ~= 0 then
        after_cmd = "if &modified | setlocal buflisted | endif"
    else
        after_cmd = "update" .. (vim.v.cmdbang == 1 and "!" or "")
    end

    local prev_bufnr = -1
    local qf_bufnr = bufnr

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
        local original_text = chomp(entry.text)
        if current_line ~= original_text then
            if current_line ~= new_text then
                echoerr(string.format("csubstitute: Original text has changed: %s:%d", vim.fn.bufname(entry.bufnr),
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
end

local function open_replace_window(cmd, close_lists)
    local current_qflist = vim.fn.getqflist()
    if not current_qflist or vim.tbl_isempty(current_qflist) then
        vim.notify("[csubstitute] No quickfix list available.", vim.log.levels.INFO)
        return
    end

    local open_cmd = (cmd and cmd ~= "") and cmd or "new"
    local bufnr = state.bufnr
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        local wins = vim.fn.win_findbuf(bufnr)
        if wins[1] then
            vim.api.nvim_set_current_win(wins[1])
            apply_window_opts(wins[1])
        else
            vim.cmd(open_cmd)
            vim.api.nvim_set_current_buf(bufnr)
            apply_window_opts(vim.api.nvim_get_current_win())
        end
    else
        vim.cmd(open_cmd)
        vim.cmd("enew")
        bufnr = vim.api.nvim_get_current_buf()
        state.bufnr = bufnr
        vim.bo[bufnr].swapfile = false
        vim.bo[bufnr].bufhidden = "hide"
        vim.bo[bufnr].buftype = "acwrite"
        vim.bo[bufnr].filetype = "csubstitute"
        vim.api.nvim_buf_set_name(bufnr, "[csubstitute]")
        vim.api.nvim_create_autocmd("BufWriteCmd", {
            buffer = bufnr,
            nested = true,
            callback = function()
                do_replace(bufnr)
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
                apply_window_opts(vim.api.nvim_get_current_win())
            end,
        })
    end

    if close_lists then
        close_list_windows()
    end

    populate_buffer(bufnr, current_qflist)
    apply_window_opts(vim.api.nvim_get_current_win())
end

function M.start(cmd, close_lists)
    open_replace_window(cmd, close_lists)
end

function M.quickfix_text(info)
    return require("csubstitute.format").quickfix_text(info)
end

function M.setup()
    vim.o.quickfixtextfunc = "v:lua.require'csubstitute'.quickfix_text"

    vim.api.nvim_create_user_command("Csubstitute", function(opts)
        M.start(opts.args, opts.bang)
    end, { nargs = "?", bang = true })

    vim.api.nvim_create_user_command("Csub", function(opts)
        M.start(opts.args, opts.bang)
    end, { nargs = "?", bang = true })
end

return M
