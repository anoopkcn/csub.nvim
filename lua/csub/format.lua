local M = {}

M.META_WIDTH = 50

local function normalize_name(entry)
    local name = ""
    if entry.bufnr and entry.bufnr ~= 0 then
        name = vim.api.nvim_buf_get_name(entry.bufnr)
    elseif entry.filename then
        name = entry.filename
    end
    -- Leave empty for entries without a file (e.g., compiler context lines)
    -- Make path relative to cwd
    local cwd = vim.uv.cwd() or ""
    if cwd ~= "" and name:sub(1, #cwd) == cwd then
        name = name:sub(#cwd + 2) -- +2 to skip the trailing slash
    end
    return name
end

local function truncate_path(path, max_width)
    if #path <= max_width then
        return path
    end
    -- First try shortening path components (e.g., /foo/bar/baz -> /f/b/baz)
    local short = vim.fn.pathshorten(path)
    if #short <= max_width then
        return short
    end
    -- If still too long, truncate from left (keep the end)
    return short:sub(-max_width)
end

function M.format_meta(entry, opts)
    local width = (opts and opts.width) or M.META_WIDTH
    local name = normalize_name(entry)
    local lnum = entry.lnum or 0
    local col = entry.col or 0
    local suffix = string.format("|%5d:%-4d| ", lnum, col)
    local name_width = math.max(width - #suffix, 1)

    local display_name = truncate_path(name, name_width)

    return string.format("%-" .. name_width .. "s%s", display_name, suffix)
end

function M.format_meta_chunks(entry, opts)
    local width = (opts and opts.width) or M.META_WIDTH
    local name = normalize_name(entry)
    local lnum = entry.lnum or 0
    local col = entry.col or 0
    local suffix = string.format("%5d:%-4d", lnum, col)
    local decorated_suffix_width = #suffix + 3 -- two pipes plus trailing space
    local name_width = math.max(width - decorated_suffix_width, 1)

    local display_name = truncate_path(name, name_width)
    local padded_name = string.format("%-" .. name_width .. "s", display_name)

    return {
        { padded_name, "CsubMetaFileName" },
        { "|", "CsubSeparator" },
        { suffix, "CsubMetaNumber" },
        { "|", "CsubSeparator" },
        { " ", "CsubMetaFileName" },
    }
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

    local lines = {}
    for i = info.start_idx, info.end_idx do
        local e = items[i]
        local meta = M.format_meta(e, { width = M.META_WIDTH })
        table.insert(lines, meta .. (e.text or ""))
    end
    return lines
end

return M
