local M = {}

-- Cache frequently used API functions
local buf_get_name = vim.api.nvim_buf_get_name

M.META_WIDTH = 50

function M.normalize_name(entry)
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

local normalize_name = M.normalize_name

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

-- Right-pad with spaces to `width`. Faster than `string.format("%-Ns", ...)`
-- with a dynamic spec, because string.rep is a tight C loop and we skip
-- building a one-shot format string per call.
local function pad_right(s, width)
    local pad = width - #s
    if pad <= 0 then return s end
    return s .. string.rep(" ", pad)
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

    local suffix = string.format("|%5d:%-4d| ", lnum, col)
    local name_width = math.max(width - #suffix, 1)
    local display_name = truncate_path(name, name_width)

    return pad_right(display_name, name_width) .. suffix
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
    local suffix = string.format("%5d:%-4d", lnum, col)
    local name_width = math.max(width - #suffix - 3, 1) -- 3 = two "|" + trailing space

    local display_name = truncate_path(name, name_width)

    return {
        { pad_right(display_name, name_width), "CsubMetaFileName" },
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
