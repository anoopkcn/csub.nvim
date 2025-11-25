local M = {}

function M.chomp(str)
    local s = str or ""
    local without_cr = s:gsub("\r$", "")
    return without_cr
end

function M.with_buf(bufnr, fn)
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        fn(bufnr)
    end
end

function M.silence_modified(bufnr)
    M.with_buf(bufnr, function(b)
        vim.bo[b].modified = false
    end)
end

function M.echoerr(msg)
    vim.notify(msg, vim.log.levels.ERROR)
end

return M
