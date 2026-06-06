local M = {}

-- Cache frequently used API functions
local buf_get_name = vim.api.nvim_buf_get_name

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

-- Plain "relpath:lnum:col" label for an entry. No padding, truncation, or
-- separators — just the raw position info. Returns "" for context lines
-- (entries with no file and no position, e.g. compiler context).
function M.meta_label(entry)
    local name = normalize_name(entry)
    if is_context_line(entry, name) then
        return ""
    end
    return string.format("%s:%d:%d", name, entry.lnum or 0, entry.col or 0)
end

-- A single virt_text chunk for `label`, right-padded to `width` so all
-- entries' text aligns to one gutter. One subdued highlight, no separators.
function M.meta_chunk(label, width)
    return { { pad_right(label, width), "CsubMeta" } }
end

return M
