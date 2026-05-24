-- Quickfix / location list dispatcher. A target is { kind, winid } where
-- kind is "qf" or "loclist". For loclist, winid is the OWNER window (the
-- code window the loclist is attached to) — it survives the loclist window
-- being closed, unlike the loclist window's own id.

local M = {}

local win_is_valid = vim.api.nvim_win_is_valid
local win_get_buf = vim.api.nvim_win_get_buf
local list_wins = vim.api.nvim_list_wins

function M.is_loclist_window(winid)
    if not winid or not win_is_valid(winid) then return false end
    local info = vim.fn.getwininfo(winid)[1]
    return info ~= nil and info.loclist == 1
end

--- Classify the window that invoked :Csub.
--- @param winid integer
--- @return table target { kind = "qf"|"loclist", winid = owner_winid|nil }
function M.classify(winid)
    if winid and win_is_valid(winid) and M.is_loclist_window(winid) then
        local fi = vim.fn.getloclist(winid, { filewinid = 0 })
        local owner = fi and fi.filewinid or 0
        if owner ~= 0 then
            return { kind = "loclist", winid = owner }
        end
    end
    return { kind = "qf", winid = nil }
end

function M.get(target, what)
    if target.kind == "loclist" then
        return vim.fn.getloclist(target.winid or 0, what)
    end
    return vim.fn.getqflist(what)
end

function M.set(target, action, dict)
    if target.kind == "loclist" then
        return vim.fn.setloclist(target.winid or 0, {}, action, dict)
    end
    return vim.fn.setqflist({}, action, dict)
end

function M.current_id(target)
    local info = M.get(target, { id = 0 })
    return (info and info.id) or 0
end

--- Stable string signature for "are these two list contexts the same?"
--- Used to detect when an unsaved csub buffer belongs to a different list
--- (or the same list but a different scoped region).
function M.signature(target, id, scope)
    local scope_part = scope and (scope.first .. "-" .. scope.last) or "-"
    return string.format("%s:%s:%d:%s",
        target.kind,
        tostring(target.winid or 0),
        id or 0,
        scope_part)
end

--- Find the buffer hosting `bufnr`'s list items, if any. Returns
--- { target, items, list_bufnr } or nil. Used by the metadata-column
--- highlighter to figure out which list a quickfix-typed buffer belongs to.
function M.find_for_buffer(bufnr)
    if not bufnr then return nil end
    local qf_info = vim.fn.getqflist({
        qfbufnr = 1, items = 1, id = 0, changedtick = 0,
    })
    if qf_info.qfbufnr == bufnr then
        return {
            target = { kind = "qf", winid = nil },
            items = qf_info.items or {},
            list_bufnr = bufnr,
            id = qf_info.id or 0,
            changedtick = qf_info.changedtick or 0,
        }
    end
    for _, win in ipairs(list_wins()) do
        if M.is_loclist_window(win) and win_get_buf(win) == bufnr then
            local fi = vim.fn.getloclist(win, { filewinid = 0 })
            local owner = fi and fi.filewinid or 0
            if owner ~= 0 then
                local ll = vim.fn.getloclist(owner, {
                    qfbufnr = 1, items = 1, id = 0, changedtick = 0,
                })
                if ll.qfbufnr == bufnr then
                    return {
                        target = { kind = "loclist", winid = owner },
                        items = ll.items or {},
                        list_bufnr = bufnr,
                        id = ll.id or 0,
                        changedtick = ll.changedtick or 0,
                    }
                end
            end
        end
    end
    return nil
end

return M
