local M = {}
local api = vim.api
local config = require("neominimap.config")
local coord = require("neominimap.map.coord")
local fold = require("neominimap.map.fold")
local logger = require("neominimap.logger")

local ns = api.nvim_create_namespace("neominimap_viewport")

---@class Neominimap.Viewport.Cache
---@field w0 integer
---@field w_dollar integer
---@field sbufnr integer
---@field mbufnr integer
---@field line_count integer
---@field m_start_row integer
---@field m_end_row integer

---@type table<integer, Neominimap.Viewport.Cache>
local cache = {}

api.nvim_set_decoration_provider(ns, {
    on_win = function(_, _, _, _, _)
        -- empty: decoration provider must have on_win to trigger on_line
    end,
    on_line = function(_, winid, bufnr, row)
        local vp = cache[winid]
        if not vp then
            return
        end
        if row < vp.m_start_row - 1 or row >= vp.m_end_row then
            return
        end
        api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
            end_row = row + 1,
            hl_group = config.viewport.hl_group,
            hl_mode = "combine",
            ephemeral = true,
            priority = config.viewport.priority,
        })
    end,
})

---@param swinid integer
---@param mwinid integer
M.refresh = function(swinid, mwinid)
    if not config.viewport.enabled then
        return
    end
    if not api.nvim_win_is_valid(swinid) or not api.nvim_win_is_valid(mwinid) then
        return
    end

    local mbufnr = api.nvim_win_get_buf(mwinid)
    if not mbufnr or not api.nvim_buf_is_valid(mbufnr) then
        return
    end

    local sbufnr = api.nvim_win_get_buf(swinid)
    if not sbufnr or not api.nvim_buf_is_valid(sbufnr) then
        return
    end

    local w0 = vim.fn.line("w0", swinid)
    local w_dollar = vim.fn.line("w$", swinid)
    if w0 == 0 or w_dollar == 0 then
        return
    end

    local cached_folds = fold.get_cached_folds(sbufnr) or {}
    local start_row, end_row = fold.get_visible_range(cached_folds, w0, w_dollar)
    local m_start_row = coord.codepoint_to_mcodepoint(start_row, 1)
    local m_end_row = coord.codepoint_to_mcodepoint(end_row, 1)
    local line_count = api.nvim_buf_line_count(mbufnr)

    local cached = cache[mwinid]
    if
        cached
        and cached.w0 == w0
        and cached.w_dollar == w_dollar
        and cached.sbufnr == sbufnr
        and cached.mbufnr == mbufnr
        and cached.line_count == line_count
    then
        return
    end

    logger.log.trace("Refreshing viewport overlay for minimap window %d", mwinid)

    if m_start_row > line_count then
        cache[mwinid] = {
            w0 = w0,
            w_dollar = w_dollar,
            sbufnr = sbufnr,
            mbufnr = mbufnr,
            line_count = line_count,
            m_start_row = m_start_row,
            m_end_row = m_end_row,
        }
        logger.log.trace("Viewport overlay cleared (out of range) for minimap window %d", mwinid)
        return
    end

    cache[mwinid] = {
        w0 = w0,
        w_dollar = w_dollar,
        sbufnr = sbufnr,
        mbufnr = mbufnr,
        line_count = line_count,
        m_start_row = m_start_row,
        m_end_row = math.min(m_end_row, line_count),
    }

    logger.log.trace("Viewport overlay refreshed for minimap window %d", mwinid)
end

---@param mwinid integer
M.clear = function(mwinid)
    cache[mwinid] = nil
end

return M
