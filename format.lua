local M = {}

M.META_WIDTH = 50

local function normalize_name(entry)
    local name = ""
    if entry.bufnr and entry.bufnr ~= 0 then
        name = vim.fn.bufname(entry.bufnr)
    elseif entry.filename then
        name = entry.filename
    end
    if name == "" then
        name = "[No Name]"
    end
    return vim.fn.fnamemodify(name, ":.")
end

function M.format_meta(entry, opts)
    local width = (opts and opts.width) or M.META_WIDTH
    local name = normalize_name(entry)
    local lnum = entry.lnum or 0
    local col = entry.col or 0
    local suffix = string.format("|%5d:%-4d| ", lnum, col)
    local name_width = math.max(width - #suffix, 1)

    local display_name = name
    if #display_name > name_width then
        display_name = vim.fn.pathshorten(display_name)
    end
    if #display_name > name_width then
        display_name = vim.fn.strcharpart(display_name, #display_name - name_width, name_width)
    end

    return string.format("%-" .. name_width .. "s%s", display_name, suffix)
end

function M.quickfix_text(info)
    local items
    if info.quickfix == 1 then
        items = vim.fn.getqflist({ id = info.id, items = 1 }).items
    else
        items = vim.fn.getloclist(info.winid, { id = info.id, items = 1 }).items
    end
    if not items then
        return {}
    end

    vim.cmd("setlocal nowrap")

    local lines = {}
    for i = info.start_idx, info.end_idx do
        local e = items[i]
        local meta = M.format_meta(e, { width = M.META_WIDTH })
        table.insert(lines, meta .. (e.text or ""))
    end
    return lines
end

return M
