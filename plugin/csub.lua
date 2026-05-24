if vim.g.loaded_csub == 1 then
    return
end
vim.g.loaded_csub = 1

-- Only claim quickfixtextfunc if nothing else has set it, so we don't
-- silently override a user/other-plugin setting. Users who want csub to
-- take it over can clear theirs (`set quickfixtextfunc=`) before loading
-- csub, or explicitly set it to our function themselves.
if vim.o.quickfixtextfunc == "" then
    vim.o.quickfixtextfunc = "v:lua.require'csub'.quickfix_text"
end

local set_hl = vim.api.nvim_set_hl
set_hl(0, "CsubSeparator", { link = "Comment", default = true })
set_hl(0, "CsubMetaFileName", { link = "Comment", default = true })
set_hl(0, "CsubMetaNumber", { link = "Number", default = true })
set_hl(0, "CsubDirtyLine", { link = "DiffChange", default = true })

local augroup = vim.api.nvim_create_augroup("csub", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = { "qf", "csub" },
    callback = function()
        vim.wo.wrap = false
    end,
})

vim.api.nvim_create_autocmd("QuickFixCmdPost", {
    group = augroup,
    pattern = "*",
    callback = function()
        vim.schedule(function()
            require("csub")._refresh_all_list_buffers()
        end)
    end,
})

vim.api.nvim_create_autocmd("BufWinEnter", {
    group = augroup,
    callback = function(args)
        if vim.bo[args.buf].buftype == "quickfix" then
            local bufnr = args.buf
            vim.schedule(function()
                require("csub")._highlight_list_buffer(bufnr)
            end)
        end
    end,
})

vim.api.nvim_create_user_command("Csub", function(opts)
    require("csub").start({
        range = opts.range,
        line1 = opts.line1,
        line2 = opts.line2,
    })
end, {
    desc = "Toggle an editable quickfix buffer",
    range = true,
    nargs = 0,
})
