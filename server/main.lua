-- server/main.lua
local QBCore = exports['qb-core']:GetCoreObject()
local pendingPaymentCheckInterval = 10 -- minutes
local lastPendingPaymentCheck = 0

-- Database initialization
local function InitializeDatabase()
    exports.oxmysql:execute([[
        CREATE TABLE IF NOT EXISTS fundraisers (
            id INT AUTO_INCREMENT PRIMARY KEY,
            creator_identifier VARCHAR(50) NOT NULL,
            creator_name VARCHAR(50) NOT NULL,
            title VARCHAR(100) NOT NULL,
            description TEXT NOT NULL,
            goal INT NOT NULL,
            current_amount INT DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            active BOOLEAN DEFAULT TRUE
        )
    ]], {})

    exports.oxmysql:execute([[
        CREATE TABLE IF NOT EXISTS fundraiser_contributions (
            id INT AUTO_INCREMENT PRIMARY KEY,
            fundraiser_id INT NOT NULL,
            contributor_identifier VARCHAR(50) NOT NULL,
            contributor_name VARCHAR(50) NOT NULL,
            amount INT NOT NULL,
            contributed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (fundraiser_id) REFERENCES fundraisers(id)
        )
    ]], {})

    exports.oxmysql:execute([[
    CREATE TABLE IF NOT EXISTS fundraiser_pending_payments (
        id INT AUTO_INCREMENT PRIMARY KEY,
        fundraiser_id INT NOT NULL,
        recipient_identifier VARCHAR(50) NOT NULL,
        amount INT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        processed BOOLEAN DEFAULT FALSE,
        FOREIGN KEY (fundraiser_id) REFERENCES fundraisers(id)
    )
]], {})
end

AddEventHandler('onResourceStart', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then return end
    InitializeDatabase()
end)

RegisterNetEvent('QBCore:Server:PlayerLoaded')
AddEventHandler('QBCore:Server:PlayerLoaded', function()
    local src = source
    ProcessPendingPayments(src)
end)

-- Get all active fundraisers
QBCore.Functions.CreateCallback('ss-gosendme:getAllFundraisers', function(source, cb)
    exports.oxmysql:execute('SELECT * FROM fundraisers WHERE active = 1 ORDER BY created_at DESC', {}, function(results)
        cb(results)
    end)
end)

-- Get fundraisers created by player
QBCore.Functions.CreateCallback('ss-gosendme:getPlayerFundraisers', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    local identifier = Player.PlayerData.citizenid

    exports.oxmysql:execute('SELECT * FROM fundraisers WHERE creator_identifier = ? ORDER BY created_at DESC', {identifier}, function(results)
        cb(results)
    end)
end)

-- Get fundraiser details including contributions
QBCore.Functions.CreateCallback('ss-gosendme:getFundraiserDetails', function(source, cb, fundraiserId)
    exports.oxmysql:execute('SELECT * FROM fundraisers WHERE id = ?', {fundraiserId}, function(fundraiser)
        if fundraiser[1] then
            exports.oxmysql:execute('SELECT * FROM fundraiser_contributions WHERE fundraiser_id = ? ORDER BY contributed_at DESC', {fundraiserId}, function(contributions)
                cb(fundraiser[1], contributions)
            end)
        else
            cb(nil, nil)
        end
    end)
end)

-- Create new fundraiser
RegisterNetEvent('ss-gosendme:createFundraiser')
AddEventHandler('ss-gosendme:createFundraiser', function(title, description, goal)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    local identifier = Player.PlayerData.citizenid
    local playerName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
    
    -- Check if player has reached maximum fundraisers limit
    exports.oxmysql:execute('SELECT COUNT(*) as count FROM fundraisers WHERE creator_identifier = ? AND active = 1', {identifier}, function(result)
        if result[1].count >= Config.MaximumFundraisers then
            TriggerClientEvent('QBCore:Notify', src, 'You have reached the maximum number of active fundraisers', 'error')
            return
        end
        
        -- Create the fundraiser
        exports.oxmysql:insert('INSERT INTO fundraisers (creator_identifier, creator_name, title, description, goal) VALUES (?, ?, ?, ?, ?)', 
        {identifier, playerName, title, description, goal}, function(id)
            if id > 0 then
                TriggerClientEvent('QBCore:Notify', src, 'Fundraiser created successfully!', 'success')
                
                -- Send Discord webhook if enabled
                if Config.UseDiscordWebhook then
                    SendDiscordWebhook('New Fundraiser Created', 
                    '**Title:** ' .. title .. 
                    '\n**Created By:** ' .. playerName .. 
                    '\n**Goal:** $' .. goal .. 
                    '\n**Description:** ' .. description)
                end
                
                -- Refresh the UI for the player
                TriggerClientEvent('ss-gosendme:refreshFundraisers', src)
            else
                TriggerClientEvent('QBCore:Notify', src, 'Failed to create fundraiser', 'error')
            end
        end)
    end)
end)

-- Contribute to a fundraiser
RegisterNetEvent('ss-gosendme:contributeFundraiser')
AddEventHandler('ss-gosendme:contributeFundraiser', function(fundraiserId, amount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    -- Check if the amount is valid
    if amount < Config.MinimumContribution then
        TriggerClientEvent('QBCore:Notify', src, 'Minimum contribution is $' .. Config.MinimumContribution, 'error')
        return
    end
    
    -- Check if player has enough money
    if Player.PlayerData.money.cash < amount then
        TriggerClientEvent('QBCore:Notify', src, 'You don\'t have enough cash', 'error')
        return
    end
    
    -- Get fundraiser details
    exports.oxmysql:execute('SELECT * FROM fundraisers WHERE id = ? AND active = 1', {fundraiserId}, function(fundraiser)
        if not fundraiser[1] then
            TriggerClientEvent('QBCore:Notify', src, 'Fundraiser not found or inactive', 'error')
            return
        end
        
        -- Remove money from contributor
        Player.Functions.RemoveMoney('cash', amount, 'fundraiser-contribution')
        
        local identifier = Player.PlayerData.citizenid
        local playerName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
        
        -- Record the contribution
        exports.oxmysql:insert('INSERT INTO fundraiser_contributions (fundraiser_id, contributor_identifier, contributor_name, amount) VALUES (?, ?, ?, ?)', 
        {fundraiserId, identifier, playerName, amount}, function(contributionId)
            if contributionId > 0 then
                -- Update the fundraiser current amount
                exports.oxmysql:execute('UPDATE fundraisers SET current_amount = current_amount + ? WHERE id = ?', {amount, fundraiserId})
                
                -- Notify contributor
                TriggerClientEvent('QBCore:Notify', src, 'Thank you for your contribution of $' .. amount, 'success')
                
                -- Find and notify the fundraiser creator if they're online
                local creator = fundraiser[1].creator_identifier
                local creatorSource = QBCore.Functions.GetPlayerByCitizenId(creator)
                if creatorSource then
                    TriggerClientEvent('QBCore:Notify', creatorSource.PlayerData.source, playerName .. ' contributed $' .. amount .. ' to your fundraiser!', 'success')
                end
                
                -- Send to all contributors to refresh their UI
                TriggerClientEvent('ss-gosendme:refreshFundraisers', -1)
                
                -- When a fundraiser reaches its goal, transfer money to creator
                exports.oxmysql:execute('SELECT current_amount, goal FROM fundraisers WHERE id = ?', {fundraiserId}, function(updatedFundraiser)
                    if updatedFundraiser[1].current_amount >= updatedFundraiser[1].goal then
                        -- Transfer funds to creator if they're online
                        if creatorSource then
                            creatorSource.Functions.AddMoney('bank', updatedFundraiser[1].current_amount, 'fundraiser-completed')
                            TriggerClientEvent('QBCore:Notify', creatorSource.PlayerData.source, 'Your fundraiser has reached its goal! $' .. updatedFundraiser[1].current_amount .. ' has been transferred to your bank account.', 'success')
                            
                            -- Mark fundraiser as inactive
                            exports.oxmysql:execute('UPDATE fundraisers SET active = 0 WHERE id = ?', {fundraiserId})
                            
                            -- Send Discord webhook if enabled
                            if Config.UseDiscordWebhook then
                                SendDiscordWebhook('Fundraiser Completed', 
                                '**Title:** ' .. fundraiser[1].title .. 
                                '\n**Created By:** ' .. fundraiser[1].creator_name .. 
                                '\n**Goal Reached:** $' .. updatedFundraiser[1].current_amount)
                            end
                            
                            -- Notify all players to refresh
                            TriggerClientEvent('ss-gosendme:refreshFundraisers', -1)
                        else
                            -- Store the pending transfer in the database if creator is offline
                            exports.oxmysql:insert('INSERT INTO fundraiser_pending_payments (fundraiser_id, recipient_identifier, amount) VALUES (?, ?, ?)', 
                            {fundraiserId, creator, updatedFundraiser[1].current_amount}, function(pendingId)
                                if pendingId > 0 then
                                    -- Mark fundraiser as inactive
                                    exports.oxmysql:execute('UPDATE fundraisers SET active = 0 WHERE id = ?', {fundraiserId})
                                    
                                    -- Send Discord webhook if enabled
                                    if Config.UseDiscordWebhook then
                                        SendDiscordWebhook('Fundraiser Completed (Payment Pending)', 
                                        '**Title:** ' .. fundraiser[1].title .. 
                                        '\n**Created By:** ' .. fundraiser[1].creator_name .. 
                                        '\n**Goal Reached:** $' .. updatedFundraiser[1].current_amount ..
                                        '\n**Payment Status:** Pending (Creator offline)')
                                    end
                                    
                                    -- Notify all players to refresh
                                    TriggerClientEvent('qb-fundraisers:refreshFundraisers', -1)
                                end
                            end)
                        end
                    end
                end)
            else
                TriggerClientEvent('QBCore:Notify', src, 'Failed to process contribution', 'error')
                -- Refund the player
                Player.Functions.AddMoney('cash', amount, 'fundraiser-contribution-refund')
            end
        end)
    end)
end)

-- Administrative functions

-- Close a fundraiser (admin only)
RegisterNetEvent('ss-gosendme:closeFundraiser')
AddEventHandler('ss-gosendme:closeFundraiser', function(fundraiserId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    -- Check if player is admin
    if not Config.AdminPermissions[Player.PlayerData.permission] then
        TriggerClientEvent('QBCore:Notify', src, 'You do not have permission to do this', 'error')
        return
    end
    
    exports.oxmysql:execute('UPDATE fundraisers SET active = 0 WHERE id = ?', {fundraiserId}, function(rowsChanged)
        if rowsChanged > 0 then
            TriggerClientEvent('QBCore:Notify', src, 'Fundraiser closed successfully', 'success')
            TriggerClientEvent('ss-gosendme:refreshFundraisers', -1)
        else
            TriggerClientEvent('QBCore:Notify', src, 'Failed to close fundraiser', 'error')
        end
    end)
end)

-- Discord webhook function
function SendDiscordWebhook(title, message)
    if not Config.UseDiscordWebhook or Config.DiscordWebhook == "YOUR_WEBHOOK_URL_HERE" then return end
    
    local embed = {
        {
            ["title"] = title,
            ["description"] = message,
            ["color"] = Config.WebhookColor,
            ["footer"] = {
                ["text"] = "Server Fundraisers - " .. os.date("%Y-%m-%d %H:%M:%S")
            }
        }
    }
    
    PerformHttpRequest(Config.DiscordWebhook, function(err, text, headers) end, 'POST', json.encode({embeds = embed}), { ['Content-Type'] = 'application/json' })
end

function ProcessPendingPayments(playerId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return end
    
    local identifier = Player.PlayerData.citizenid
    
    exports.oxmysql:execute('SELECT * FROM fundraiser_pending_payments WHERE recipient_identifier = ? AND processed = 0', {identifier}, function(pendingPayments)
        if pendingPayments and #pendingPayments > 0 then
            for _, payment in ipairs(pendingPayments) do
                -- Add money to player's bank account
                Player.Functions.AddMoney('bank', payment.amount, 'fundraiser-completed-offline')
                
                -- Mark payment as processed
                exports.oxmysql:execute('UPDATE fundraiser_pending_payments SET processed = 1 WHERE id = ?', {payment.id})
                
                -- Get fundraiser details for the notification
                exports.oxmysql:execute('SELECT title FROM fundraisers WHERE id = ?', {payment.fundraiser_id}, function(fundraiser)
                    local title = fundraiser[1] and fundraiser[1].title or "Unknown Fundraiser"
                    
                    -- Notify player
                    TriggerClientEvent('QBCore:Notify', Player.PlayerData.source, 'You received $' .. payment.amount .. ' from your fundraiser "' .. title .. '" that completed while you were offline!', 'success')
                    
                    -- Send webhook notification if enabled
                    if Config.UseDiscordWebhook then
                        SendDiscordWebhook('Offline Fundraiser Payment Processed', 
                        '**Player:** ' .. Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname .. 
                        '\n**Fundraiser:** ' .. title .. 
                        '\n**Amount:** $' .. payment.amount)
                    end
                end)
            end
        end
    end)
end

function CheckPendingPayments()
    local currentTime = os.time()
    
    if currentTime - lastPendingPaymentCheck < (pendingPaymentCheckInterval * 60) then
        return -- Not time to check yet
    end
    
    lastPendingPaymentCheck = currentTime
    
    -- Check for pending payments
    exports.oxmysql:execute('SELECT * FROM fundraiser_pending_payments WHERE processed = 0', {}, function(pendingPayments)
        if not pendingPayments or #pendingPayments == 0 then
            return
        end
        
        local processed = 0
        
        for _, payment in ipairs(pendingPayments) do
            local recipient = payment.recipient_identifier
            local recipientPlayer = QBCore.Functions.GetPlayerByCitizenId(recipient)
            
            if recipientPlayer then
                -- Player is online, process payment
                recipientPlayer.Functions.AddMoney('bank', payment.amount, 'scheduled-fundraiser-payment')
                exports.oxmysql:execute('UPDATE fundraiser_pending_payments SET processed = 1 WHERE id = ?', {payment.id})
                
                -- Get fundraiser info
                exports.oxmysql:execute('SELECT title FROM fundraisers WHERE id = ?', {payment.fundraiser_id}, function(fundraiser)
                    local title = fundraiser[1] and fundraiser[1].title or "Unknown Fundraiser"
                    
                    TriggerClientEvent('QBCore:Notify', recipientPlayer.PlayerData.source, 'You received $' .. payment.amount .. ' from your fundraiser "' .. title .. '" that completed earlier.', 'success')
                end)
                
                processed = processed + 1
            end
        end
        
        if processed > 0 and Config.UseDiscordWebhook then
            SendDiscordWebhook('Scheduled Fundraiser Payments', 
            '**Payments Processed:** ' .. processed)
        end
    end)
end

-- Run the pending payment check function once per minute
CreateThread(function()
    while true do
        CheckPendingPayments()
        Wait(60000) -- Check every minute if it's time to process payments
    end
end)

-- Admin command to process all pending payments
RegisterCommand('processfundraiserpayments', function(source, args)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player or not Config.AdminPermissions[Player.PlayerData.permission] then
        TriggerClientEvent('QBCore:Notify', src, 'You do not have permission to use this command', 'error')
        return
    end
    
    -- Get all pending payments
    exports.oxmysql:execute('SELECT * FROM fundraiser_pending_payments WHERE processed = 0', {}, function(pendingPayments)
        if not pendingPayments or #pendingPayments == 0 then
            TriggerClientEvent('QBCore:Notify', src, 'No pending payments found', 'inform')
            return
        end
        
        local processed = 0
        local failed = 0
        
        for _, payment in ipairs(pendingPayments) do
            local recipientPlayer = QBCore.Functions.GetPlayerByCitizenId(payment.recipient_identifier)
            
            if recipientPlayer then
                -- Player is online, process payment
                recipientPlayer.Functions.AddMoney('bank', payment.amount, 'admin-processed-fundraiser')
                exports.oxmysql:execute('UPDATE fundraiser_pending_payments SET processed = 1 WHERE id = ?', {payment.id})
                
                TriggerClientEvent('QBCore:Notify', recipientPlayer.PlayerData.source, 'You received $' .. payment.amount .. ' from a fundraiser that completed previously.', 'success')
                processed = processed + 1
            else
                failed = failed + 1
            end
        end
        
        TriggerClientEvent('QBCore:Notify', src, 'Processed ' .. processed .. ' payments. ' .. failed .. ' payments pending (players offline).', 'inform')
        
        if processed > 0 and Config.UseDiscordWebhook then
            SendDiscordWebhook('Admin Processed Fundraiser Payments', 
            '**Admin:** ' .. Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname .. 
            '\n**Payments Processed:** ' .. processed .. 
            '\n**Payments Pending:** ' .. failed)
        end
    end)
end, false)

-- Close fundraisers and transfer funds when server restarts
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    -- Check for completed fundraisers and handle payments
    exports.oxmysql:execute('SELECT * FROM fundraisers WHERE active = 1 AND current_amount >= goal', {}, function(completedFundraisers)
        if completedFundraisers and #completedFundraisers > 0 then
            for _, fundraiser in ipairs(completedFundraisers) do
                local creatorId = fundraiser.creator_identifier
                local creatorSource = QBCore.Functions.GetPlayerByCitizenId(creatorId)
                
                -- Mark fundraiser as inactive
                exports.oxmysql:execute('UPDATE fundraisers SET active = 0 WHERE id = ?', {fundraiser.id})
                
                if creatorSource then
                    -- Creator is online, add money directly
                    creatorSource.Functions.AddMoney('bank', fundraiser.current_amount, 'fundraiser-completed-on-resource-stop')
                    TriggerClientEvent('QBCore:Notify', creatorSource.PlayerData.source, 'Your fundraiser "' .. fundraiser.title .. '" has reached its goal! $' .. fundraiser.current_amount .. ' has been transferred to your bank account.', 'success')
                else
                    -- Creator is offline, store pending payment
                    exports.oxmysql:insert('INSERT INTO fundraiser_pending_payments (fundraiser_id, recipient_identifier, amount) VALUES (?, ?, ?)', 
                    {fundraiser.id, creatorId, fundraiser.current_amount})
                end
                
                -- Send webhook notification
                if Config.UseDiscordWebhook then
                    SendDiscordWebhook('Fundraiser Completed (Resource Stopping)', 
                    '**Title:** ' .. fundraiser.title .. 
                    '\n**Created By:** ' .. fundraiser.creator_name .. 
                    '\n**Goal Reached:** $' .. fundraiser.current_amount .. 
                    '\n**Payment Status:** ' .. (creatorSource and 'Processed' or 'Pending (Creator offline)'))
                end
            end
        end
    end)
    
    print('[ss-gosendme] Resource stopping - Completed fundraisers processed')
end)