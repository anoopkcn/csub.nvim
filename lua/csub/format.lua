local M = {}

-- Cache frequently used API functions
local buf_get_name = vim.api.nvim_buf_get_name

M.META_WIDTH = 50
M.separator = "|"

local function normalize_name(entry)
    local name = ""
    if entry.bufnr and entry.bufnr ~= 0 then
        name = buf_get_name(entry.bufnr)
    elseif entry.filename then
        name = entry.filename
    end
    -- Leave empty for entries without a file (e.g., compiler context lines)
    -- Make path relative to cwd
    local cwd = vim.uv.cwd()
    if cwd and name:sub(1, #cwd) == cwd then
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

local function is_context_line(entry, name)
    return name == "" and (entry.lnum or 0) == 0 and (entry.col or 0) == 0
end

function M.format_meta(entry, opts)
    local width = (opts and opts.width) or M.META_WIDTH
    local name = normalize_name(entry)
    local lnum = entry.lnum or 0
    local col = entry.col or 0

    -- For context lines (no file, no position), just use padding
    if is_context_line(entry, name) then
        return string.rep(" ", width)
    end

    -- Always use "|" in the actual quickfix text (when separator is not empty)
    -- so Neovim's native highlighting (QuickFixLine, etc.) works correctly.
    -- The visual separator from M.separator is applied via virtual text overlay.
    local suffix
    if M.separator == "" then
        suffix = string.format(" %5d:%-4d  ", lnum, col)
    else
        suffix = string.format("|%5d:%-4d| ", lnum, col)
    end
    local name_width = math.max(width - #suffix, 1)

    local display_name = truncate_path(name, name_width)

    return string.format("%-" .. name_width .. "s%s", display_name, suffix)
end

function M.format_meta_chunks(entry, opts)
    local width = (opts and opts.width) or M.META_WIDTH
    local name = normalize_name(entry)

    -- For context lines (no file, no position), just use padding
    if is_context_line(entry, name) then
        return {
            { string.rep(" ", width), "CsubMetaFileName" },
        }
    end

    local lnum = entry.lnum or 0
    local col = entry.col or 0
    local sep = M.separator
    local suffix = string.format("%5d:%-4d", lnum, col)

    local decorated_suffix_width
    if sep == "" then
        decorated_suffix_width = #suffix + 3 -- spaces around numbers plus trailing space
    else
        decorated_suffix_width = #suffix + #sep * 2 + 1 -- two separators plus trailing space
    end
    local name_width = math.max(width - decorated_suffix_width, 1)

    local display_name = truncate_path(name, name_width)
    local padded_name = string.format("%-" .. name_width .. "s", display_name)

    if sep == "" then
        return {
            { padded_name, "CsubMetaFileName" },
            { " ", "CsubMetaFileName" },
            { suffix, "CsubMetaNumber" },
            { "  ", "CsubMetaFileName" },
        }
    end

    return {
        { padded_name, "CsubMetaFileName" },
        { sep, "CsubSeparator" },
        { suffix, "CsubMetaNumber" },
        { sep, "CsubSeparator" },
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

    -- Pre-allocate table with known size
    local count = info.end_idx - info.start_idx + 1
    local lines = {}
    for i = 1, count do
        local idx = info.start_idx + i - 1
        local e = items[idx]
        local meta = M.format_meta(e, { width = M.META_WIDTH })
        lines[i] = meta .. (e.text or "")
    end
    return lines
end

return M
