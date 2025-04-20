// Settings.js - JavaScript for the settings page
// Optimized for low resource systems like Raspberry Pi 3B

// Cache DOM elements
const elements = {
    form: document.getElementById('tank-settings-form'),
    maxDistance: document.getElementById('max-distance'),
    minDistance: document.getElementById('min-distance'),
    settingsMessage: document.getElementById('settings-message'),
    tankPreviewLevel: document.getElementById('tank-preview-level'),
    previewLevelValue: document.getElementById('preview-level-value'),
    previewDistanceValue: document.getElementById('preview-distance-value'),
    currentYear: document.getElementById('current-year')
};

// State management
let state = {
    settings: {
        maxDistance: 100,
        minDistance: 0
    },
    currentDistance: 50,
    connected: false
};

// Set current year in footer
elements.currentYear.textContent = new Date().getFullYear();

// Fetch current tank settings
async function fetchTankSettings() {
    try {
        const response = await fetch('/api/tank-settings');
        const data = await response.json();
        
        if (data) {
            state.settings = data;
            
            // Update form values
            elements.maxDistance.value = data.maxDistance;
            elements.minDistance.value = data.minDistance;
            
            // Update preview
            updatePreview();
        }
    } catch (error) {
        console.error('Error fetching tank settings:', error);
        showMessage('Error loading settings. Please try again.', 'error');
    }
}

// Save tank settings
async function saveTankSettings(data) {
    try {
        const response = await fetch('/api/tank-settings', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(data)
        });
        
        const result = await response.json();
        
        if (result.status === 'success') {
            showMessage('Settings saved successfully!', 'success');
            state.settings = data;
            updatePreview();
        } else {
            showMessage(result.message || 'Error saving settings.', 'error');
        }
    } catch (error) {
        console.error('Error saving tank settings:', error);
        showMessage('Error saving settings. Please try again.', 'error');
    }
}

// Show message
function showMessage(message, type) {
    elements.settingsMessage.textContent = message;
    elements.settingsMessage.className = 'settings-message';
    elements.settingsMessage.classList.add(type);
    
    // Hide message after 5 seconds
    setTimeout(() => {
        elements.settingsMessage.style.display = 'none';
    }, 5000);
}

// Calculate water level from distance
function calculateWaterLevel(distance) {
    const { maxDistance, minDistance } = state.settings;
    const range = maxDistance - minDistance;
    
    if (range <= 0) return 0;
    
    // Constrain distance within the range
    const clampedDistance = Math.max(minDistance, Math.min(maxDistance, distance));
    
    // Calculate percentage (inverted: max distance = 0%, min distance = 100%)
    const level = 100 - ((clampedDistance - minDistance) / range * 100);
    
    // Round to 1 decimal place
    return Math.round(level * 10) / 10;
}

// Update tank level preview
function updatePreview() {
    const waterLevel = calculateWaterLevel(state.currentDistance);
    
    // Update tank level visualization
    elements.tankPreviewLevel.style.height = `${waterLevel}%`;
    elements.previewLevelValue.textContent = waterLevel.toFixed(1);
    elements.previewDistanceValue.textContent = state.currentDistance.toFixed(1);
}

// Fetch latest sensor data for preview
async function fetchLatestData() {
    try {
        const response = await fetch('/api/latest');
        const data = await response.json();
        
        if (data && data.distance !== undefined) {
            state.currentDistance = data.distance;
            updatePreview();
        }
    } catch (error) {
        console.error('Error fetching latest data:', error);
    }
}

// Connect to SSE for real-time updates
function connectSSE() {
    if (state.connected) return;
    
    const eventSource = new EventSource('/api/events');
    
    eventSource.onopen = function() {
        console.log('SSE connection established');
        state.connected = true;
    };
    
    eventSource.onmessage = function(event) {
        try {
            const data = JSON.parse(event.data);
            if (data && data.distance !== undefined) {
                state.currentDistance = data.distance;
                updatePreview();
            }
        } catch (error) {
            console.error('Error parsing SSE data:', error);
        }
    };
    
    eventSource.onerror = function(error) {
        console.error('SSE connection error:', error);
        state.connected = false;
        
        // Close the connection
        eventSource.close();
        
        // Try to reconnect after 5 seconds
        setTimeout(connectSSE, 5000);
    };
}

// Initialize settings page
function initSettings() {
    // Fetch current settings
    fetchTankSettings();
    
    // Fetch latest sensor data
    fetchLatestData();
    
    // Connect to SSE for real-time updates
    connectSSE();
    
    // Form submission event listener
    elements.form.addEventListener('submit', function(event) {
        event.preventDefault();
        
        const maxDistance = parseFloat(elements.maxDistance.value);
        const minDistance = parseFloat(elements.minDistance.value);
        
        // Validate inputs
        if (isNaN(maxDistance) || isNaN(minDistance)) {
            showMessage('Please enter valid numbers.', 'error');
            return;
        }
        
        if (minDistance >= maxDistance) {
            showMessage('Minimum distance must be less than maximum distance.', 'error');
            return;
        }
        
        // Save settings
        saveTankSettings({
            maxDistance,
            minDistance
        });
    });
}

// Start the settings page when DOM is loaded
document.addEventListener('DOMContentLoaded', initSettings); 