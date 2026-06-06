if vim.g.loaded_csub == 1 then
    return
end
vim.g.loaded_csub = 1

local set_hl = vim.api.nvim_set_hl
set_hl(0, "CsubMeta", { link = "Comment", default = true })
set_hl(0, "CsubDirtyLine", { link = "DiffChange", default = true })

local augroup = vim.api.nvim_create_augroup("csub", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = { "csub" },
    callback = function()
        vim.wo.wrap = false
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
