local M = {}

-- Cache frequently used API functions
local buf_is_valid = vim.api.nvim_buf_is_valid

function M.chomp(str)
    local s = str or ""
    return s:gsub("\r$", "")
end

function M.silence_modified(bufnr)
    if bufnr and buf_is_valid(bufnr) then
        vim.bo[bufnr].modified = false
    end
end

function M.echoerr(msg)
    vim.notify(msg, vim.log.levels.ERROR)
end

return M
