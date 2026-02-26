--[[
    ps-mdt – Server-side Framework Bridge
    ======================================
    Provides a QBCore-compatible API when running alongside CBK_Core_Framework.
    This file must be listed BEFORE server/utils.lua, server/dbm.lua and
    server/main.lua in fxmanifest.lua so that the global `QBCore` table is
    available when those scripts execute.

    When qb-core is the active framework this file sets nothing and the normal
    qb-core export path is taken by the other scripts.
]]

-- Only activate this bridge when CBK_core is the active framework.
if GetResourceState('CBK_core') ~= 'started' then return end

-- Wrap a CBKPlayer instance into the QBCore Player shape that ps-mdt expects.
-- The wrapper is intentionally a snapshot so callers always see a consistent
-- view.  Do NOT cache the returned table – call QBCore.Functions.GetPlayer()
-- again if you need a fresh copy.
local function wrapPlayer(player)
    if not player then return nil end

    -- Build a job table that includes the `onduty` flag (stored at player
    -- top-level in CBK, inside job in QBCore).
    local job = {
        name    = player.job and player.job.name   or 'unemployed',
        label   = player.job and player.job.label  or 'Unemployed',
        type    = player.job and player.job.type   or 'civilian',
        onduty  = player.onduty == true,
        grade   = player.job and player.job.grade  or { name = 'Recruit', label = 'Recruit', level = 0 },
    }

    local playerData = {
        citizenid = player.citizenid,
        license   = player.license,
        charinfo  = player.charinfo  or {},
        metadata  = player.metadata  or {},
        money     = player.money     or {},
        gang      = player.gang      or {},
        group     = player.group     or 'user',
        job       = job,
    }

    -- Expose a `Functions` sub-table mirroring QBCore player methods that
    -- ps-mdt's dbm.lua uses (SetMetaData).
    local functions = {
        SetMetaData = function(key, value)
            player:SetMetadata(key, value)
            player:Save()
        end,
        Notify = function(msg, ntype, duration)
            player:Notify(msg, ntype or 'inform', duration or 5000)
        end,
    }

    return { PlayerData = playerData, Functions = functions }
end

-- ── Public CBK-backed QBCore object ────────────────────────────────────────

QBCore          = QBCore          or {}
QBCore.Functions = QBCore.Functions or {}
QBCore.Commands  = QBCore.Commands  or {}
QBCore.Shared    = QBCore.Shared    or {}

-- Vehicles table stub – CBK does not expose a flat shared-vehicles table.
-- ps-mdt guards all lookups with `if vehData then`, so an empty table is safe.
QBCore.Shared.Vehicles = QBCore.Shared.Vehicles or {}

-- ── Player lookups ──────────────────────────────────────────────────────────

function QBCore.Functions.GetPlayer(src)
    return wrapPlayer(CBKServer.Players[tonumber(src)])
end

function QBCore.Functions.GetPlayerByCitizenId(cid)
    return wrapPlayer(CBKServer.PlayersByCitizenId[tostring(cid)])
end

-- ── Identifiers ─────────────────────────────────────────────────────────────

-- Returns the full identifier string, e.g. 'license:abc123' (same as QBCore).
function QBCore.Functions.GetIdentifier(src, idType)
    if idType == 'license' then
        return CBKServer.GetLicense(tonumber(src))
    end
    return CBKServer.GetIdentifier(tonumber(src), idType)
end

-- ── Callbacks ───────────────────────────────────────────────────────────────

-- Signature matches QBCore: function(source, cb, ...)
function QBCore.Functions.CreateCallback(name, cb)
    CBKServer.RegisterCallback(name, cb)
end

-- ── Commands ────────────────────────────────────────────────────────────────

-- Mirrors QBCore.Commands.Add(name, help, params, restricted, handler, perm).
function QBCore.Commands.Add(name, help, params, restricted, handler, perm)
    RegisterCommand(tostring(name), function(source, args, rawCommand)
        if restricted and source ~= 0 then
            local allowed = CBKServer.HasPermission(source, perm or 'cbk.admin')
            if not allowed then
                CBKServer.Notify(source, "You don't have permission to use this command.", 'error')
                return
            end
        end
        handler(source, args, rawCommand)
    end, false)
end

-- ── Duty toggle ─────────────────────────────────────────────────────────────

-- QBCore client fires TriggerServerEvent('QBCore:ToggleDuty') to flip duty.
-- In CBK, duty lives on the player object rather than inside the job row.
RegisterNetEvent('QBCore:ToggleDuty')
AddEventHandler('QBCore:ToggleDuty', function()
    local src    = source
    local player = CBKServer.Players[src]
    if player then
        player:SetDuty(not player.onduty)
        player:Save()
    end
end)

print('^2[ps-mdt] CBK_core server bridge loaded.^7')
