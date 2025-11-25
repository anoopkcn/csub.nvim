local buffer = require("csub.buffer")
local fmt = require("csub.format")
local replace = require("csub.replace")
local window = require("csub.window")

local M = {}

local state = {
    bufnr = nil,
    qf_bufnr = nil,
    qf_winid = nil,
}

local function open_replace_window()
    local current_qflist = vim.fn.getqflist()
    if not current_qflist or vim.tbl_isempty(current_qflist) then
        vim.notify("[csub] No quickfix list available.", vim.log.levels.INFO)
        return
    end

    local target_win = state.qf_winid
    if not (target_win and vim.api.nvim_win_is_valid(target_win)) then
        target_win = window.ensure_quickfix_window()
    end
    if not target_win then
        vim.notify("[csub] Unable to open quickfix window.", vim.log.levels.ERROR)
        return
    end

    state.qf_winid = target_win
    state.qf_bufnr = vim.api.nvim_win_get_buf(target_win)

    local bufnr = buffer.ensure_buffer(state, target_win, state.qf_bufnr, replace.apply)
    if not bufnr then
        vim.notify("[csub] Unable to prepare csub buffer.", vim.log.levels.ERROR)
        return
    end

    buffer.populate(bufnr, current_qflist)
    window.apply_window_opts(target_win)
end

function M.start()
    open_replace_window()
end

function M.quickfix_text(info)
    return fmt.quickfix_text(info)
end

function M.setup()
    vim.o.quickfixtextfunc = "v:lua.require'csub'.quickfix_text"

    if vim.fn.hlexists("CsubSeparator") == 0 then
        pcall(vim.api.nvim_set_hl, 0, "CsubSeparator", { link = "Comment" })
    end
    if vim.fn.hlexists("CsubMetaFileName") == 0 then
        pcall(vim.api.nvim_set_hl, 0, "CsubMetaFileName", { link = "Comment" })
    end
    if vim.fn.hlexists("CsubMetaNumber") == 0 then
        pcall(vim.api.nvim_set_hl, 0, "CsubMetaNumber", { link = "Number" })
    end

    vim.api.nvim_create_user_command("Csub", function()
        M.start()
    end, { nargs = 0 })
end

return M
