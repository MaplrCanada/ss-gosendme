// html/script.js
let fundraiserId = 0;
let uiSettings = {
    primary_color: "#4CAF50",
    secondary_color: "#2196F3",
    accent_color: "#FF9800",
    background_color: "#424242",
    text_color: "#FFFFFF"
};

$(function() {
    // Hide UI by default
    $("#fundraiser-container").hide();
    
    // Listen for NUI messages from client script
    window.addEventListener('message', function(event) {
        var data = event.data;
        
        if (data.type === "ui") {
            if (data.status) {
                $("#fundraiser-container").fadeIn(300);
                
                // Apply UI settings if provided
                if (data.settings) {
                    uiSettings = data.settings;
                    applyUISettings();
                }
            } else {
                $("#fundraiser-container").fadeOut(300);
            }
        } else if (data.type === "openMenu") {
            // Reset to browse tab and load fundraisers
            $('.tab').removeClass('active');
            $('.tab[data-tab="browse"]').addClass('active');
            $('.tab-content').removeClass('active');
            $('#browse-content').addClass('active');
            
            // Show admin tab if player is admin
            if (data.isAdmin) {
                $('.admin-tab').show();
            } else {
                $('.admin-tab').hide();
            }
            
            loadAllFundraisers();
            
        } else if (data.type === "openAdminMenu") {
            // Switch to admin tab
            $('.tab').removeClass('active');
            $('.tab[data-tab="admin"]').addClass('active');
            $('.tab-content').removeClass('active');
            $('#admin-content').addClass('active');
            $('.admin-tab').show();
            
            loadAdminFundraisers();
            
        } else if (data.type === "refreshFundraisers") {
            // Refresh active tab content
            if ($('#browse-content').hasClass('active')) {
                loadAllFundraisers();
            } else if ($('#my-fundraisers-content').hasClass('active')) {
                loadPlayerFundraisers();
            } else if ($('#admin-content').hasClass('active')) {
                loadAdminFundraisers();
            }
        }
    });
    
    // Apply initial UI settings
    applyUISettings();
    
    // Close button
    $("#close-btn").click(function() {
        $.post('https://ss-gosendme/close', JSON.stringify({}));
    });
    
    // Tab switching
    $(".tab").click(function() {
        $('.tab').removeClass('active');
        $(this).addClass('active');
        
        var tab = $(this).data('tab');
        $('.tab-content').removeClass('active');
        $('#' + tab + '-content').addClass('active');
        
        // Load content based on tab
        switch(tab) {
            case 'browse':
                loadAllFundraisers();
                break;
            case 'my-fundraisers':
                loadPlayerFundraisers();
                break;
            case 'admin':
                loadAdminFundraisers();
                break;
        }
    });
    
    // Create fundraiser form submission
    $("#create-fundraiser-form").submit(function(e) {
        e.preventDefault();
        
        const title = $("#title").val().trim();
        const description = $("#description").val().trim();
        const goal = parseInt($("#goal").val());
        const durationValue = parseInt($("#duration-value").val());
        const durationUnit = $("#duration-unit").val();
        
        if (!title || !description || isNaN(goal) || goal <= 0 || isNaN(durationValue) || durationValue <= 0) {
            return;
        }
        
        $.post('https://ss-gosendme/createFundraiser', JSON.stringify({
            title: title,
            description: description,
            goal: goal,
            duration: {
                value: durationValue,
                unit: durationUnit
            }
        }));
        
        // Reset form
        $("#create-fundraiser-form")[0].reset();
        
        // Switch to browse tab
        $('.tab[data-tab="browse"]').click();
    });
    
    // Close modals when clicking on X or outside
    $(".close-modal").click(function() {
        $(".modal").hide();
    });
    
    $(window).click(function(e) {
        if ($(e.target).hasClass('modal')) {
            $(".modal").hide();
        }
    });
    
    // Handle contribution submission
    $("#contribute-btn").click(function() {
        const amount = parseInt($("#contribution-amount").val());
        
        if (isNaN(amount) || amount <= 0) {
            // You could add a notification here
            return;
        }
        
        $.post('https://ss-gosendme/contributeFundraiser', JSON.stringify({
            fundraiserId: fundraiserId,
            amount: amount
        }));
        
        // Close modal and reset form
        $("#contribution-modal").hide();
        $("#contribution-amount").val('');
    });
});

// Load all active fundraisers
function loadAllFundraisers() {
    $("#all-fundraisers").html('<div class="loading">Loading fundraisers...</div>');
    
    $.post('https://ss-gosendme/getAllFundraisers', JSON.stringify({}), function(fundraisers) {
        if (fundraisers.length === 0) {
            $("#all-fundraisers").html(`
                <div class="empty-state">
                    <i class="fas fa-search"></i>
                    <p>No active fundraisers found.</p>
                    <p>Be the first to create one!</p>
                </div>
            `);
            return;
        }
        
        let fundraisersHtml = '';
        
        fundraisers.forEach(fundraiser => {
            const progressPercentage = Math.min((fundraiser.current_amount / fundraiser.goal) * 100, 100);
            
            // Calculate time remaining if expires_at exists
            let timeRemainingHtml = '';
            if (fundraiser.expires_at) {
                const expiryDate = new Date(fundraiser.expires_at);
                const now = new Date();
                const timeRemaining = expiryDate - now;
                
                if (timeRemaining > 0) {
                    const days = Math.floor(timeRemaining / (1000 * 60 * 60 * 24));
                    const hours = Math.floor((timeRemaining % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
                    const minutes = Math.floor((timeRemaining % (1000 * 60 * 60)) / (1000 * 60));
                    
                    timeRemainingHtml = `<div class="time-remaining">Time remaining: `;
                    if (days > 0) timeRemainingHtml += `${days}d `;
                    if (hours > 0 || days > 0) timeRemainingHtml += `${hours}h `;
                    timeRemainingHtml += `${minutes}m</div>`;
                } else {
                    timeRemainingHtml = `<div class="time-remaining expired">Expired</div>`;
                }
            }
            
            fundraisersHtml += `
                <div class="fundraiser-card" data-id="${fundraiser.id}">
                    <h3>${fundraiser.title}</h3>
                    <div class="creator-info">Created by: ${fundraiser.creator_name}</div>
                    <div class="fundraiser-details">
                        ${fundraiser.description.length > 100 ? fundraiser.description.substring(0, 100) + '...' : fundraiser.description}
                    </div>
                    ${timeRemainingHtml}
                    <div class="fundraiser-progress">
                        <div class="progress-bar">
                            <div class="progress-fill" style="width: ${progressPercentage}%"></div>
                        </div>
                        <div class="progress-text">
                            <span>$${fundraiser.current_amount}</span>
                            <span>$${fundraiser.goal}</span>
                        </div>
                    </div>
                    ${progressPercentage >= 100 ? '<div class="goal-reached">Goal Reached!</div>' : ''}
                    <button class="btn btn-contribute">View Details</button>
                </div>
            `;
        });
        
        $("#all-fundraisers").html(fundraisersHtml);
        
        // Add event listeners to new cards
        $(".fundraiser-card").click(function() {
            const id = $(this).data('id');
            openFundraiserDetails(id);
        });
    });
}

// Load player's own fundraisers
function loadPlayerFundraisers() {
    $("#player-fundraisers").html('<div class="loading">Loading your fundraisers...</div>');
    
    $.post('https://ss-gosendme/getPlayerFundraisers', JSON.stringify({}), function(fundraisers) {
        if (fundraisers.length === 0) {
            $("#player-fundraisers").html(`
                <div class="empty-state">
                    <i class="fas fa-plus-circle"></i>
                    <p>You haven't created any fundraisers yet.</p>
                    <p>Go to the "Create Fundraiser" tab to get started!</p>
                </div>
            `);
            return;
        }
        
        let fundraisersHtml = '';
        
        fundraisers.forEach(fundraiser => {
            const progressPercentage = Math.min((fundraiser.current_amount / fundraiser.goal) * 100, 100);
            const isActive = fundraiser.active == 1;
            
            fundraisersHtml += `
                <div class="fundraiser-card" data-id="${fundraiser.id}" style="${!isActive ? 'opacity: 0.7;' : ''}">
                    <h3>${fundraiser.title} ${!isActive ? '(Closed)' : ''}</h3>
                    <div class="fundraiser-details">
                        ${fundraiser.description.length > 100 ? fundraiser.description.substring(0, 100) + '...' : fundraiser.description}
                    </div>
                    <div class="fundraiser-progress">
                        <div class="progress-bar">
                            <div class="progress-fill" style="width: ${progressPercentage}%"></div>
                        </div>
                        <div class="progress-text">
                            <span>$${fundraiser.current_amount}</span>
                            <span>$${fundraiser.goal}</span>
                        </div>
                    </div>
                    ${progressPercentage >= 100 ? '<div class="goal-reached">Goal Reached!</div>' : ''}
                    <button class="btn btn-contribute">View Details</button>
                </div>
            `;
        });
        
        $("#player-fundraisers").html(fundraisersHtml);
        
        // Add event listeners to new cards
        $(".fundraiser-card").click(function() {
            const id = $(this).data('id');
            openFundraiserDetails(id);
        });
    });
}

// Load fundraisers for admin panel
function loadAdminFundraisers() {
    $("#admin-fundraisers").html('<div class="loading">Loading all fundraisers...</div>');
    
    $.post('https://ss-gosendme/getAllFundraisers', JSON.stringify({}), function(fundraisers) {
        if (fundraisers.length === 0) {
            $("#admin-fundraisers").html(`
                <div class="empty-state">
                    <i class="fas fa-clipboard-list"></i>
                    <p>No fundraisers found in the system.</p>
                </div>
            `);
            return;
        }
        
        let fundraisersHtml = '';
        
        fundraisers.forEach(fundraiser => {
            const progressPercentage = Math.min((fundraiser.current_amount / fundraiser.goal) * 100, 100);
            
            fundraisersHtml += `
                <div class="admin-fundraiser-card">
                    <div class="fundraiser-info">
                        <h3>${fundraiser.title}</h3>
                        <div class="creator-info">Created by: ${fundraiser.creator_name} - $${fundraiser.current_amount}/$${fundraiser.goal}</div>
                    </div>
                    <div class="admin-actions">
                        <button class="admin-btn admin-view" data-id="${fundraiser.id}">View</button>
                        <button class="admin-btn admin-close" data-id="${fundraiser.id}">Close</button>
                    </div>
                </div>
            `;
        });
        
        $("#admin-fundraisers").html(fundraisersHtml);
        
        // Add event listeners to admin buttons
        $(".admin-view").click(function() {
            const id = $(this).data('id');
            openFundraiserDetails(id);
        });
        
        $(".admin-close").click(function() {
            const id = $(this).data('id');
            $.post('https://ss-gosendme/closeFundraiser', JSON.stringify({
                fundraiserId: id
            }));
        });
    });
}

// Open fundraiser details
function openFundraiserDetails(id) {
    $.post('https://ss-gosendme/getFundraiserDetails', JSON.stringify({
        fundraiserId: id
    }), function(data) {
        if (!data.fundraiser) {
            return;
        }
        
        const fundraiser = data.fundraiser;
        const contributions = data.contributions || [];
        const progressPercentage = Math.min((fundraiser.current_amount / fundraiser.goal) * 100, 100);
        const isActive = fundraiser.active == 1;
        
        let detailsHtml = `
            <h2>${fundraiser.title} ${!isActive ? '(Closed)' : ''}</h2>
            
            <div class="detail-section">
                <h3>Details</h3>
                <p><strong>Created by:</strong> ${fundraiser.creator_name}</p>
                <p><strong>Created on:</strong> ${new Date(fundraiser.created_at).toLocaleDateString()}</p>
                <p>${fundraiser.description}</p>
            </div>
            
            <div class="detail-section">
                <h3>Progress</h3>
                <div class="fundraiser-progress">
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: ${progressPercentage}%"></div>
                    </div>
                    <div class="progress-text">
                        <span>$${fundraiser.current_amount}</span>
                        <span>$${fundraiser.goal}</span>
                    </div>
                </div>
                ${progressPercentage >= 100 ? '<div class="goal-reached">Goal Reached!</div>' : ''}
            </div>
        `;
        
        if (contributions.length > 0) {
            detailsHtml += `
                <div class="detail-section">
                    <h3>Contributions</h3>
                    <div class="contribution-list">
            `;
            
            contributions.forEach(contribution => {
                detailsHtml += `
                    <div class="contribution-item">
                        <span>${contribution.contributor_name}</span>
                        <span>$${contribution.amount}</span>
                    </div>
                `;
            });
            
            detailsHtml += `
                    </div>
                </div>
            `;
        }
        
        if (isActive) {
            detailsHtml += `
                <div class="fundraiser-actions">
                    <button id="open-contribute" class="btn btn-contribute">Make Contribution</button>
                </div>
            `;
        }
        
        $("#fundraiser-details").html(detailsHtml);
        $("#fundraiser-details-modal").show();
        
        // Store fundraiser ID for contribution
        fundraiserId = id;
        
        // Add event listener to contribution button
        $("#open-contribute").click(function() {
            $("#fundraiser-details-modal").hide();
            $("#contribution-modal").show();
        });
    });
}

// Apply UI settings from config
function applyUISettings() {
    document.documentElement.style.setProperty('--primary-color', uiSettings.primary_color);
    document.documentElement.style.setProperty('--secondary-color', uiSettings.secondary_color);
    document.documentElement.style.setProperty('--accent-color', uiSettings.accent_color);
    document.documentElement.style.setProperty('--background-color', uiSettings.background_color);
    document.documentElement.style.setProperty('--text-color', uiSettings.text_color);
}