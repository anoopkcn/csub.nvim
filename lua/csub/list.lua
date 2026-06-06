-- Quickfix / location list dispatcher. A target is { kind, winid } where
-- kind is "qf" or "loclist". For loclist, winid is the OWNER window (the
-- code window the loclist is attached to) — it survives the loclist window
-- being closed, unlike the loclist window's own id.

local M = {}

local win_is_valid = vim.api.nvim_win_is_valid

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

return M
