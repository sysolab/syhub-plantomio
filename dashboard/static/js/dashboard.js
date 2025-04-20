// Dashboard.js - Main JavaScript for dashboard page
// Optimized for low resource systems like Raspberry Pi 3B

// Cache DOM elements
const elements = {
    // Tank and water level
    tankLevel: document.getElementById('tank-level'),
    waterLevelValue: document.getElementById('water-level-value'),
    waterLevelAlt: document.getElementById('water-level-value-alt'), 
    distanceValue: document.getElementById('distance-value'),
    
    // Metrics
    temperatureValue: document.getElementById('temperature-value'),
    phValue: document.getElementById('ph-value'),
    ecValue: document.getElementById('ec-value'),
    ecValueAlt: document.getElementById('ec-value-alt'),
    tdsValue: document.getElementById('tds-value'),
    
    // Status
    dashboardStatus: document.getElementById('dashboard-status'),
    noderedStatus: document.getElementById('nodered-status'),
    vmStatus: document.getElementById('vm-status'),
    lastUpdate: document.getElementById('last-update'),
    systemLoad: document.getElementById('system-load'),
    
    // Charts
    mainChart: document.getElementById('main-chart'),
    
    // Progress bars
    tdsProgress: document.getElementById('tds-progress'),
    ecProgress: document.getElementById('ec-progress'),
    
    // Year in footer
    currentYear: document.getElementById('current-year')
};

// Tank configuration
let tankConfig = {
    maxDistance: 50.0,  // cm when tank is empty (0%)
    minDistance: 5.0,   // cm when tank is full (100%)
    alertLevel: 20      // % alert level
};

// State management
let state = {
    connected: false,
    mainChart: null,
    sensorData: {},
    chartData: {
        labels: [],
        temperature: [],
        ph: [],
        ec: []
    },
    reconnectAttempts: 0,
    maxReconnectAttempts: 5
};

// Update current year in footer
elements.currentYear && (elements.currentYear.textContent = new Date().getFullYear());

// Format timestamp
function formatTimestamp(timestamp) {
    if (!timestamp) return '--';
    const date = new Date(timestamp);
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

// Update tank visualization
function updateTankLevel(level) {
    if (level === undefined || level === null || !elements.tankLevel) return;
    
    // Set tank fill level with clamping between 0 and 100
    const safeLevel = Math.max(0, Math.min(100, level));
    elements.tankLevel.style.height = `${safeLevel}%`;
    
    // Update the main water level value
    if (elements.waterLevelValue) {
        elements.waterLevelValue.textContent = safeLevel.toFixed(1);
    }
    
    // Also update the alternate display if it exists
    if (elements.waterLevelAlt) {
        elements.waterLevelAlt.textContent = safeLevel.toFixed(1);
    }
}

// Update progress bars
function updateProgressBars(data) {
    if (!data) return;
    
    // Update TDS progress bar (0-1000ppm scale)
    if (data.TDS !== undefined && elements.tdsProgress) {
        const tdsPercent = Math.min(100, (data.TDS / 1000) * 100);
        elements.tdsProgress.style.width = `${tdsPercent}%`;
    }
    
    // Update EC progress bar (0-3 mS/cm scale)
    if (data.EC !== undefined && elements.ecProgress) {
        const ecPercent = Math.min(100, (data.EC / 3) * 100);
        elements.ecProgress.style.width = `${ecPercent}%`;
    }
}

// Update sensor metrics
function updateMetrics(data) {
    if (!data) return;
    
    // Update sensor values if they exist
    if (data.temperature !== undefined && elements.temperatureValue) {
        elements.temperatureValue.textContent = data.temperature.toFixed(1);
    }
    
    if (data.pH !== undefined && elements.phValue) {
        elements.phValue.textContent = data.pH.toFixed(1);
    }
    
    if (data.EC !== undefined) {
        // Update primary EC display
        if (elements.ecValue) {
            elements.ecValue.textContent = data.EC.toFixed(2);
        }
        
        // Update alternate EC display if it exists
        if (elements.ecValueAlt) {
            elements.ecValueAlt.textContent = data.EC.toFixed(2);
        }
    }
    
    if (data.TDS !== undefined && elements.tdsValue) {
        elements.tdsValue.textContent = data.TDS.toFixed(0);
    }
    
    if (data.distance !== undefined && elements.distanceValue) {
        elements.distanceValue.textContent = data.distance.toFixed(1);
    }
    
    if (data.waterLevel !== undefined) {
        updateTankLevel(data.waterLevel);
    }
    
    // Update progress bars
    updateProgressBars(data);
    
    // Update last update time
    if (data.lastUpdate && elements.lastUpdate) {
        elements.lastUpdate.textContent = formatTimestamp(data.lastUpdate);
    }
}

// Update system status indicators
function checkSystemStatus() {
    fetch('/health')
        .then(response => response.json())
        .then(data => {
            if (data.services) {
                const { node_red, victoria_metrics } = data.services;
                
                // Update Node-RED status
                if (elements.noderedStatus) {
                    elements.noderedStatus.innerHTML = 
                        node_red.status === 'ok' 
                            ? '<span class="status-dot online"></span> Online' 
                            : '<span class="status-dot error"></span> Offline';
                }
                
                // Update VictoriaMetrics status
                if (elements.vmStatus) {
                    elements.vmStatus.innerHTML = 
                        victoria_metrics.status === 'ok' 
                            ? '<span class="status-dot online"></span> Online' 
                            : '<span class="status-dot error"></span> Offline';
                }
                
                // Update system load (using random value as placeholder)
                if (elements.systemLoad) {
                    const cpuLoad = Math.round(Math.random() * 30 + 10);
                    elements.systemLoad.textContent = `${cpuLoad}%`;
                }
            }
        })
        .catch(error => {
            console.error('Error checking system status:', error);
        });
}

// Load tank configuration
function loadTankConfig() {
    fetch('/api/tank-settings')
        .then(response => response.json())
        .then(data => {
            if (data && data.maxDistance && data.minDistance) {
                tankConfig = data;
                console.log('Tank configuration loaded:', tankConfig);
                
                // If we have current data, recalculate the water level
                if (state.sensorData && state.sensorData.distance !== undefined) {
                    const level = calculateWaterLevel(state.sensorData.distance);
                    updateTankLevel(level);
                }
            }
        })
        .catch(error => {
            console.error('Error loading tank settings:', error);
        });
}

// Calculate water level based on distance and tank configuration
function calculateWaterLevel(distance) {
    const maxDistance = tankConfig.maxDistance;
    const minDistance = tankConfig.minDistance;
    
    // Handle invalid configurations
    if (maxDistance <= minDistance) {
        return 50.0;  // Return default if configuration is invalid
    }
    
    // Calculate percentage (reverse scale - shorter distance means higher water level)
    const level = ((maxDistance - distance) / (maxDistance - minDistance)) * 100;
    
    // Clamp to 0-100 range
    return Math.max(0, Math.min(100, level));
}

// Initialize or update the main chart
function updateChart(data) {
    // Only update if we have chart data and the chart element exists
    if (!data || !data.temperature || !data.pH || !data.EC || !elements.mainChart) return;
    
    // Get current time for label
    const now = new Date();
    const timeLabel = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    
    // Add new data point
    state.chartData.labels.push(timeLabel);
    state.chartData.temperature.push(data.temperature);
    state.chartData.ph.push(data.pH);
    state.chartData.ec.push(data.EC);
    
    // Keep only the last 30 data points (about 30 seconds at 1 second updates)
    if (state.chartData.labels.length > 30) {
        state.chartData.labels.shift();
        state.chartData.temperature.shift();
        state.chartData.ph.shift();
        state.chartData.ec.shift();
    }
    
    // If chart is not yet initialized and Chart.js is loaded, create it
    if (!state.mainChart && window.Chart) {
        initializeChart();
    } else if (state.mainChart) {
        // Update existing chart
        state.mainChart.update('none'); // Use 'none' mode for best performance
    }
}

// Initialize the main chart
function initializeChart() {
    if (!elements.mainChart) return;
    
    const ctx = elements.mainChart.getContext('2d');
    
    // Calculate min and max values for temperature for better scaling
    const tempValues = state.chartData.temperature.filter(val => val !== undefined && val !== null);
    const tempMin = tempValues.length > 0 ? Math.floor(Math.min(...tempValues) - 2) : 15;
    const tempMax = tempValues.length > 0 ? Math.ceil(Math.max(...tempValues) + 2) : 35;
    
    // Calculate min and max values for EC for better scaling
    const ecValues = state.chartData.ec.filter(val => val !== undefined && val !== null);
    const ecMin = 0;
    const ecMax = ecValues.length > 0 ? Math.ceil(Math.max(...ecValues) * 1.2) : 3;
    
    // Chart.js configuration for a modern dashboard look
    state.mainChart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: state.chartData.labels,
            datasets: [
                {
                    label: 'Temperature (°C)',
                    data: state.chartData.temperature,
                    borderColor: '#F6C343',
                    backgroundColor: 'rgba(246, 194, 67, 0.1)',
                    borderWidth: 2,
                    tension: 0.4,
                    pointRadius: 2,
                    pointBackgroundColor: '#F6C343',
                    yAxisID: 'y-temperature'
                },
                {
                    label: 'pH',
                    data: state.chartData.ph,
                    borderColor: '#4e73df',
                    backgroundColor: 'rgba(78, 115, 223, 0.1)',
                    borderWidth: 2,
                    tension: 0.4,
                    pointRadius: 2,
                    pointBackgroundColor: '#4e73df',
                    yAxisID: 'y-ph'
                },
                {
                    label: 'EC (mS/cm)',
                    data: state.chartData.ec,
                    borderColor: '#1cc88a',
                    backgroundColor: 'rgba(28, 200, 138, 0.1)',
                    borderWidth: 2,
                    tension: 0.4,
                    pointRadius: 2,
                    pointBackgroundColor: '#1cc88a',
                    yAxisID: 'y-ec'
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: {
                mode: 'index',
                intersect: false
            },
            plugins: {
                legend: {
                    position: 'top',
                    labels: {
                        usePointStyle: true,
                        font: {
                            size: 12
                        }
                    }
                },
                tooltip: {
                    backgroundColor: 'rgba(255, 255, 255, 0.9)',
                    titleColor: '#333',
                    bodyColor: '#666',
                    borderColor: '#e3e6f0',
                    borderWidth: 1,
                    cornerRadius: 6,
                    padding: 8,
                    boxPadding: 4
                }
            },
            scales: {
                x: {
                    grid: {
                        display: false
                    },
                    ticks: {
                        maxRotation: 0,
                        autoSkip: true,
                        maxTicksLimit: 6
                    }
                },
                'y-temperature': {
                    title: {
                        display: true,
                        text: '°C',
                        color: '#F6C343'
                    },
                    position: 'left',
                    min: tempMin,
                    max: tempMax,
                    grid: {
                        display: false
                    },
                    ticks: {
                        color: '#F6C343',
                        stepSize: 5
                    }
                },
                'y-ph': {
                    title: {
                        display: true,
                        text: 'pH',
                        color: '#4e73df'
                    },
                    position: 'right',
                    min: 0,
                    max: 14,
                    grid: {
                        display: false
                    },
                    ticks: {
                        color: '#4e73df',
                        stepSize: 1
                    }
                },
                'y-ec': {
                    title: {
                        display: true,
                        text: 'EC',
                        color: '#1cc88a'
                    },
                    position: 'right',
                    min: ecMin,
                    max: ecMax,
                    grid: {
                        display: false
                    },
                    ticks: {
                        color: '#1cc88a'
                    },
                    display: true
                }
            },
            animation: {
                duration: 0 // Disable animation for better performance
            }
        }
    });
}

// Fetch latest data from API
function fetchLatestData() {
    fetch('/api/latest')
        .then(response => response.json())
        .then(data => {
            updateMetrics(data);
            updateChart(data);
            state.sensorData = data;
            
            // Reset reconnect attempts on successful fetch
            state.reconnectAttempts = 0;
        })
        .catch(error => {
            console.error('Error fetching latest data:', error);
            
            // Increment reconnect attempts
            state.reconnectAttempts++;
            
            // If we've tried too many times, slow down the polling
            if (state.reconnectAttempts > state.maxReconnectAttempts) {
                console.log('Too many failed attempts, slowing down polling');
                setTimeout(fetchLatestData, 10000); // Try again in 10 seconds
            } else {
                // Try again soon
                setTimeout(fetchLatestData, 2000);
            }
        });
}

// Connect to SSE for real-time updates
function connectSSE() {
    if (state.connected) return;
    
    console.log('Attempting to connect to SSE...');
    const eventSource = new EventSource('/api/events');
    
    eventSource.onopen = function() {
        console.log('SSE connection established');
        state.connected = true;
        state.reconnectAttempts = 0;
    };
    
    eventSource.onmessage = function(event) {
        try {
            const data = JSON.parse(event.data);
            if (data) {
                updateMetrics(data);
                updateChart(data);
                state.sensorData = data;
            }
        } catch (error) {
            console.error('Error parsing SSE data:', error);
        }
    };
    
    eventSource.onerror = function(error) {
        console.error('SSE connection error:', error);
        state.connected = false;
        
        // Close the source to prevent browser automatic reconnection
        eventSource.close();
        
        // Increment reconnect counter
        state.reconnectAttempts++;
        
        // Exponential backoff for reconnection
        const reconnectDelay = Math.min(30000, Math.pow(2, state.reconnectAttempts) * 1000);
        console.log(`Reconnecting in ${reconnectDelay/1000} seconds...`);
        
        // Try to reconnect after a delay with increasing backoff
        setTimeout(() => {
            if (!state.connected) {
                connectSSE();
            }
        }, reconnectDelay);
        
        // Fall back to polling if SSE is not working after multiple attempts
        if (state.reconnectAttempts >= 3) {
            console.log('SSE connection failing, falling back to polling');
            fetchLatestData();
        }
    };
}

// Initialize dashboard
function initDashboard() {
    // Load tank configuration first
    loadTankConfig();
    
    // Initial system status
    checkSystemStatus();
    
    // Fetch initial data
    fetchLatestData();
    
    // Connect to SSE
    connectSSE();
    
    // Update system status periodically
    setInterval(checkSystemStatus, 30000);
    
    // Fallback polling for data every 30 seconds in case SSE fails
    setInterval(fetchLatestData, 30000);
}

// Add event listener for refresh buttons if they exist
document.getElementById('refresh-tank') && 
document.getElementById('refresh-tank').addEventListener('click', function() {
    fetchLatestData();
});

document.getElementById('refresh-status') && 
document.getElementById('refresh-status').addEventListener('click', function() {
    checkSystemStatus();
});

// Initialize when DOM is fully loaded
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initDashboard);
} else {
    initDashboard();
} 