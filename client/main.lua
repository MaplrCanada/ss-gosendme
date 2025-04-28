-- client/main.lua
local QBCore = exports['qb-core']:GetCoreObject()
local display = false

-- Command to open fundraiser menu
RegisterCommand(Config.CommandName, function()
    OpenFundraiserMenu()
end, false)

-- Register key mapping (optional)
RegisterKeyMapping(Config.CommandName, 'Open Fundraiser Menu', 'keyboard', 'F6')

-- Admin command
RegisterCommand(Config.AdminCommandName, function()
    local playerData = QBCore.Functions.GetPlayerData()
    if Config.AdminPermissions[playerData.permission] then
        OpenAdminFundraiserMenu()
    else
        QBCore.Functions.Notify('You do not have permission to use this command', 'error')
    end
end, false)

-- NUI Callbacks
RegisterNUICallback('close', function(data, cb)
    SetDisplay(false)
    cb('ok')
end)

RegisterNUICallback('getAllFundraisers', function(data, cb)
    QBCore.Functions.TriggerCallback('ss-gosendme:getAllFundraisers', function(fundraisers)
        cb(fundraisers)
    end)
end)

RegisterNUICallback('getPlayerFundraisers', function(data, cb)
    QBCore.Functions.TriggerCallback('ss-gosendme:getPlayerFundraisers', function(fundraisers)
        cb(fundraisers)
    end)
end)

RegisterNUICallback('getFundraiserDetails', function(data, cb)
    QBCore.Functions.TriggerCallback('ss-gosendme:getFundraiserDetails', function(fundraiser, contributions)
        cb({fundraiser = fundraiser, contributions = contributions})
    end, data.fundraiserId)
end)

RegisterNUICallback('createFundraiser', function(data, cb)
    TriggerServerEvent('ss-gosendme:createFundraiser', data.title, data.description, data.goal)
    cb('ok')
end)

RegisterNUICallback('contributeFundraiser', function(data, cb)
    TriggerServerEvent('ss-gosendme:contributeFundraiser', data.fundraiserId, data.amount)
    cb('ok')
end)

RegisterNUICallback('closeFundraiser', function(data, cb)
    TriggerServerEvent('ss-gosendme:closeFundraiser', data.fundraiserId)
    cb('ok')
end)

-- Set display function for NUI
function SetDisplay(bool)
    display = bool
    SetNuiFocus(bool, bool)
    SendNUIMessage({
        type = "ui",
        status = bool,
        settings = Config.UISettings
    })
end

-- Open fundraiser menu
function OpenFundraiserMenu()
    SetDisplay(true)
    SendNUIMessage({
        type = "openMenu",
        isAdmin = IsPlayerAdmin()
    })
end

-- Open admin fundraiser menu
function OpenAdminFundraiserMenu()
    SetDisplay(true)
    SendNUIMessage({
        type = "openAdminMenu"
    })
end

-- Check if player is admin
function IsPlayerAdmin()
    local playerData = QBCore.Functions.GetPlayerData()
    return Config.AdminPermissions[playerData.permission] or false
end

-- Event to refresh fundraisers
RegisterNetEvent('ss-gosendme:refreshFundraisers')
AddEventHandler('ss-gosendme:refreshFundraisers', function()
    if display then
        SendNUIMessage({
            type = "refreshFundraisers"
        })
    end
end)

-- Close UI when player dies
AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    SetDisplay(false)
end)