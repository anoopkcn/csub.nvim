local buffer = require("csub.buffer")
local fmt = require("csub.format")
local replace = require("csub.replace")
local window = require("csub.window")

local M = {}

local state = {
    bufnr = nil,
}

local function open_replace_window(cmd, close_lists)
    local current_qflist = vim.fn.getqflist()
    if not current_qflist or vim.tbl_isempty(current_qflist) then
        vim.notify("[csub] No quickfix list available.", vim.log.levels.INFO)
        return
    end

    local bufnr = buffer.ensure_buffer(state, cmd, replace.apply)

    if close_lists then
        window.close_list_windows()
    end

    buffer.populate(bufnr, current_qflist)
    window.apply_window_opts(vim.api.nvim_get_current_win())
end

function M.start(cmd, close_lists)
    open_replace_window(cmd, close_lists)
end

function M.quickfix_text(info)
    return fmt.quickfix_text(info)
end

function M.setup()
    vim.o.quickfixtextfunc = "v:lua.require'csub'.quickfix_text"

    vim.api.nvim_create_user_command("Csub", function(opts)
        M.start(opts.args, opts.bang)
    end, { nargs = "?", bang = true })
end

return M
