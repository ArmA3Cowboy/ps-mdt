--[[
    ps-mdt – Client-side Framework Bridge
    ======================================
    Provides a QBCore-compatible API when running alongside CBK_Core_Framework.
    This file must be listed FIRST in the client_scripts block of fxmanifest.lua
    so that the global `QBCore` table is available when main.lua executes.

    When qb-core is the active framework this file exits early and the normal
    qb-core export path is taken by the other scripts.
]]

-- Only activate when CBK_core is the active framework.
if GetResourceState('CBK_core') ~= 'started' then return end

-- ── Public CBK-backed QBCore object ────────────────────────────────────────

QBCore          = QBCore          or {}
QBCore.Functions = QBCore.Functions or {}
QBCore.Shared    = QBCore.Shared    or {}

-- Vehicles stub – CBK does not expose a flat shared-vehicles table.
-- ps-mdt guards all lookups with `if vehData then`, so an empty table is safe.
QBCore.Shared.Vehicles = QBCore.Shared.Vehicles or {}

-- ── Player data ─────────────────────────────────────────────────────────────

-- Return CBKClient.PlayerData in the shape ps-mdt expects.
-- The returned table is the LIVE CBKClient.PlayerData reference so mutations
-- from update events are visible immediately.
function QBCore.Functions.GetPlayerData()
    local data = CBKClient.PlayerData or {}
    -- Inject `onduty` into the job sub-table so callers can read
    -- PlayerData.job.onduty (QBCore convention) instead of data.onduty (CBK).
    if data.job then
        data.job.onduty = data.onduty == true
    end
    return data
end

-- ── Callbacks ───────────────────────────────────────────────────────────────

-- Mirrors QBCore.Functions.TriggerCallback(name, cb, ...).
-- Routes through CBKClient.TriggerCallback which sends
-- 'cbk:server:triggerCallback' to the server and handles the reply.
function QBCore.Functions.TriggerCallback(name, cb, ...)
    CBKClient.TriggerCallback(name, cb, ...)
end

-- ── Notifications ───────────────────────────────────────────────────────────

function QBCore.Functions.Notify(msg, ntype, duration)
    CBKClient.Notify(msg, ntype, duration)
end

-- ── Vehicle helpers ─────────────────────────────────────────────────────────

function QBCore.Functions.GetPlate(veh)
    return CBKClient.GetPlate(veh)
end

-- Simplified vehicle spawner that mirrors the QBCore.Functions.SpawnVehicle
-- signature: SpawnVehicle(model, callback, coords, isNetwork)
function QBCore.Functions.SpawnVehicle(model, cb, coords, isNetwork)
    local hash = type(model) == 'string' and GetHashKey(model) or model
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(10) end
    local pos = (coords and type(coords.x) == 'number')
        and coords
        or GetEntityCoords(PlayerPedId())
    local heading = (type(pos) == 'vector4' or (type(pos) == 'table' and type(pos.w) == 'number'))
        and pos.w or 0.0
    local veh = CreateVehicle(hash, pos.x, pos.y, pos.z, heading, isNetwork ~= false, false)
    SetModelAsNoLongerNeeded(hash)
    if cb then cb(veh) end
end

-- Apply stored vehicle properties.  Uses lib.setVehicleProperties from ox_lib
-- when available; otherwise falls back to basic colour/plate assignment.
function QBCore.Functions.SetVehicleProperties(veh, props)
    if not props or not DoesEntityExist(veh) then return end
    if lib and lib.setVehicleProperties then
        lib.setVehicleProperties(veh, props)
    else
        -- Minimal fallback: plate text only
        if props.plate then
            SetVehicleNumberPlateText(veh, props.plate)
        end
    end
end

-- Load an animation dictionary synchronously (matches QBCore behaviour).
function QBCore.Functions.RequestAnimDict(animDict)
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do Wait(10) end
end

-- ── QBCore notification event (server → client) ─────────────────────────────

-- Some server handlers call TriggerClientEvent('QBCore:Notify', src, msg, type, duration).
-- Register the net-event here so the client receives it even without qb-core.
RegisterNetEvent('QBCore:Notify')
AddEventHandler('QBCore:Notify', function(msg, ntype, duration)
    CBKClient.Notify(msg, ntype, duration)
end)

-- ── CBK → QBCore event re-mappings ─────────────────────────────────────────
-- ps-mdt's client/main.lua listens for QBCore events to update its local
-- PlayerData.  Translate CBK events into the matching QBCore events so that
-- the existing handlers fire correctly.

-- Player loaded
AddEventHandler('cbk:client:playerDataLoaded', function(data)
    -- Inject onduty into job so QBCore:Client:OnPlayerLoaded handlers get the
    -- right shape immediately.
    if data and data.job then
        data.job.onduty = data.onduty == true
    end
    TriggerEvent('QBCore:Client:OnPlayerLoaded')
end)

-- Job changed
AddEventHandler('cbk:client:jobChanged', function(job)
    if job then
        local player = CBKClient.PlayerData or {}
        job.onduty = player.onduty == true
    end
    TriggerEvent('QBCore:Client:OnJobUpdate', job)
end)

-- Gang changed
AddEventHandler('cbk:client:gangChanged', function(gang)
    TriggerEvent('QBCore:Client:OnGangUpdate', gang)
end)

-- Duty state changed – re-fire as QBCore:Client:SetDuty(job, state)
AddEventHandler('cbk:client:dutyStateChanged', function(state)
    local player = CBKClient.PlayerData or {}
    if player.job then
        player.job.onduty = state == true
    end
    TriggerEvent('QBCore:Client:SetDuty', player.job, state)
end)

-- Generic metadata / money / any update – fire the QBCore catch-all
-- so that ps-mdt's QBCore:Player:SetPlayerData handler keeps PlayerData fresh.
local function _onAnyUpdate()
    TriggerEvent('QBCore:Player:SetPlayerData', CBKClient.PlayerData or {})
end
AddEventHandler('cbk:client:metadataChanged', _onAnyUpdate)
AddEventHandler('cbk:client:moneyChanged',    _onAnyUpdate)

-- Player unloaded (no explicit CBK event; handle via resource stop)
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == 'CBK_core' then
        TriggerEvent('QBCore:Client:OnPlayerUnload')
    end
end)

print('^2[ps-mdt] CBK_core client bridge loaded.^7')
