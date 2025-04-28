-- config.lua
Config = {}

Config.UseDiscordWebhook = true
Config.DiscordWebhook = "YOUR_WEBHOOK_URL_HERE"

Config.WebhookColor = 65280 -- Green color in decimal

Config.MinimumContribution = 100 -- Minimum amount players can contribute
Config.MaximumFundraisers = 5 -- Maximum number of active fundraisers per player

Config.CommandName = "fundraisers" -- Command to open the fundraiser menu
Config.AdminCommandName = "managefundraisers" -- Admin command to manage fundraisers

Config.PendingPaymentCheckInterval = 10 -- Minutes between checking for pending payments
Config.PayPendingOnJoin = true -- Process pending payments when player joins
Config.PendingPaymentNotify = true -- Send notification to creator when they receive a pending payment

-- Debug and logging
Config.LogPaymentActivity = true -- Log payment activity to server console

-- Permission levels for admin commands (adjust as needed for your server)
Config.AdminPermissions = {
    ['god'] = true,
    ['admin'] = true,
    ['mod'] = true
}

-- UI settings
Config.UISettings = {
    primary_color = "#4CAF50",
    secondary_color = "#2196F3",
    accent_color = "#FF9800",
    background_color = "#424242",
    text_color = "#FFFFFF"
}