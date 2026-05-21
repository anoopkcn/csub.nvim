local fmt = require("csub.format")

local buf_is_valid = vim.api.nvim_buf_is_valid
local buf_get_lines = vim.api.nvim_buf_get_lines
local buf_line_count = vim.api.nvim_buf_line_count
local buf_set_extmark = vim.api.nvim_buf_set_extmark
local buf_clear_namespace = vim.api.nvim_buf_clear_namespace

local ns = vim.api.nvim_create_namespace("csub_syntax")

-- ft -> lang | false (false = no parser, cached miss)
local lang_cache = {}
-- lang -> Query | false (false = no highlights query, cached miss)
local query_cache = {}

local M = {}

local function resolve_lang(entry)
    local name = fmt.normalize_name(entry)
    if not name or name == "" then
        return false
    end
    local ft = vim.filetype.match({ filename = name })
    if not ft or ft == "" then
        return false
    end
    local cached = lang_cache[ft]
    if cached ~= nil then
        return cached
    end
    local ok, lang = pcall(vim.treesitter.language.get_lang, ft)
    if not ok or not lang then
        lang_cache[ft] = false
        return false
    end
    -- Probe that a parser is actually installed for this language.
    local has_parser = pcall(vim.treesitter.language.add, lang)
    if not has_parser then
        lang_cache[ft] = false
        return false
    end
    lang_cache[ft] = lang
    return lang
end

local function get_query(lang)
    local cached = query_cache[lang]
    if cached ~= nil then
        return cached or nil
    end
    local ok, query = pcall(vim.treesitter.query.get, lang, "highlights")
    if not ok or not query then
        query_cache[lang] = false
        return nil
    end
    query_cache[lang] = query
    return query
end

local function annotate_entries(entries)
    for _, entry in ipairs(entries) do
        if entry._csub_lang == nil then
            entry._csub_lang = resolve_lang(entry) or false
        end
    end
end

--- Apply highlights for a contiguous range of rows [first_row, last_row) using
--- a single parse per language. Rows whose entry has no language are skipped.
local function apply_rows(bufnr, first_row, last_row)
    if last_row <= first_row then
        return
    end
    local entries = vim.b[bufnr].csub_current_entries or {}
    local line_count = buf_line_count(bufnr)
    last_row = math.min(last_row, line_count)
    if last_row <= first_row then
        return
    end

    local lines = buf_get_lines(bufnr, first_row, last_row, false)

    -- Group rows by language. lang -> { texts = {...}, rows = {...} }
    local groups = {}
    for offset, text in ipairs(lines) do
        local row = first_row + offset - 1
        local entry = entries[row + 1]
        local lang = entry and entry._csub_lang or false
        if lang then
            local group = groups[lang]
            if not group then
                group = { texts = {}, rows = {} }
                groups[lang] = group
            end
            -- Strip newlines defensively; chomped lines should already be single-line,
            -- but guard against rare quickfix entries that contain embedded \n.
            local sanitized = text:gsub("[\r\n]", " ")
            group.texts[#group.texts + 1] = sanitized
            group.rows[#group.rows + 1] = row
        end
    end

    for lang, group in pairs(groups) do
        local query = get_query(lang)
        if query then
            local joined = table.concat(group.texts, "\n")
            local ok, parser = pcall(vim.treesitter.get_string_parser, joined, lang)
            if ok and parser then
                local tree = (parser:parse() or {})[1]
                if tree then
                    local root = tree:root()
                    for capture_id, node in query:iter_captures(root, joined, 0, -1) do
                        local capture_name = query.captures[capture_id]
                        if capture_name then
                            local s_row, s_col, e_row, e_col = node:range()
                            -- Each row in the joined buffer maps 1:1 to group.rows.
                            -- Skip captures that span joined rows (shouldn't happen with
                            -- single-line inputs, but guard defensively).
                            if s_row == e_row then
                                local real_row = group.rows[s_row + 1]
                                if real_row then
                                    buf_set_extmark(bufnr, ns, real_row, s_col, {
                                        end_row = real_row,
                                        end_col = e_col,
                                        hl_group = "@" .. capture_name .. "." .. lang,
                                        priority = 100,
                                        strict = false,
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function is_active(bufnr)
    if not bufnr or not buf_is_valid(bufnr) then
        return false
    end
    local mode = vim.b[bufnr].csub_mode
    return mode ~= nil and mode ~= "files"
end

-- vim.b deep-copies tables on assignment, so we must re-store after annotating
-- to make the language cache visible to later apply_rows / on_lines calls.
local function persist_entries(bufnr, entries)
    vim.b[bufnr].csub_current_entries = entries
end

function M.attach(bufnr, entries, mode, enabled)
    if not enabled then
        return
    end
    if not bufnr or not buf_is_valid(bufnr) then
        return
    end
    if mode == "files" then
        return
    end
    annotate_entries(entries)
    persist_entries(bufnr, entries)
    buf_clear_namespace(bufnr, ns, 0, -1)
    apply_rows(bufnr, 0, buf_line_count(bufnr))
end

function M.refresh_range(bufnr, firstline, new_lastline)
    if not is_active(bufnr) then
        return
    end
    local entries = vim.b[bufnr].csub_current_entries
    if not entries then
        return
    end
    -- Ensure any newly-shifted entries (after a deletion) have a resolved lang.
    annotate_entries(entries)
    persist_entries(bufnr, entries)
    buf_clear_namespace(bufnr, ns, firstline, new_lastline)
    apply_rows(bufnr, firstline, new_lastline)
end

function M.ensure(bufnr)
    if not is_active(bufnr) then
        return
    end
    local entries = vim.b[bufnr].csub_current_entries
    if not entries then
        return
    end
    annotate_entries(entries)
    persist_entries(bufnr, entries)
    buf_clear_namespace(bufnr, ns, 0, -1)
    apply_rows(bufnr, 0, buf_line_count(bufnr))
end

function M.detach(bufnr)
    if bufnr and buf_is_valid(bufnr) then
        buf_clear_namespace(bufnr, ns, 0, -1)
    end
end

return M
