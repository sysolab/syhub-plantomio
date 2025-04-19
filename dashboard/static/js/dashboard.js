// Dashboard.js - Main JavaScript for dashboard page
// Optimized for low resource systems like Raspberry Pi 3B

// Cache DOM elements
const elements = {
    // Tank and water level
    tankLevel: document.getElementById('tank-level'),
    waterLevelValue: document.getElementById('water-level-value'),
    distanceValue: document.getElementById('distance-value'),
    
    // Metrics
    temperatureValue: document.getElementById('temperature-value'),
    phValue: document.getElementById('ph-value'),
    ecValue: document.getElementById('ec-value'),
    tdsValue: document.getElementById('tds-value'),
    
    // Status
    dashboardStatus: document.getElementById('dashboard-status'),
    noderedStatus: document.getElementById('nodered-status'),
    vmStatus: document.getElementById('vm-status'),
    lastUpdate: document.getElementById('last-update'),
    
    // Year in footer
    currentYear: document.getElementById('current-year')
};

// State management
let state = {
    connected: false,
    phEcChart: null,
    sensorData: {},
    chartData: {
        labels: [],
        ph: [],
        ec: []
    }
};

// Update current year in footer
elements.currentYear.textContent = new Date().getFullYear();

// Format timestamp
function formatTimestamp(timestamp) {
    if (!timestamp) return '--';
    const date = new Date(timestamp);
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

// Update tank visualization
function updateTankLevel(level) {
    if (level === undefined || level === null) return;
    
    // Set tank fill level with clamping between 0 and 100
    const safeLevel = Math.max(0, Math.min(100, level));
    elements.tankLevel.style.height = `${safeLevel}%`;
    elements.waterLevelValue.textContent = safeLevel.toFixed(1);
}

// Update sensor metrics
function updateMetrics(data) {
    if (!data) return;
    
    // Update sensor values if they exist
    if (data.temperature !== undefined) {
        elements.temperatureValue.textContent = data.temperature.toFixed(1);
    }
    
    if (data.pH !== undefined) {
        elements.phValue.textContent = data.pH.toFixed(1);
    }
    
    if (data.EC !== undefined) {
        elements.ecValue.textContent = data.EC.toFixed(2);
    }
    
    if (data.TDS !== undefined) {
        elements.tdsValue.textContent = data.TDS.toFixed(0);
    }
    
    if (data.distance !== undefined) {
        elements.distanceValue.textContent = data.distance.toFixed(1);
    }
    
    if (data.waterLevel !== undefined) {
        updateTankLevel(data.waterLevel);
    }
    
    // Update last update time
    if (data.lastUpdate) {
        elements.lastUpdate.textContent = formatTimestamp(data.lastUpdate);
    }
}

// Update system status indicators
function updateSystemStatus() {
    fetch('/health')
        .then(response => response.json())
        .then(data => {
            if (data.services) {
                const { node_red, victoria_metrics } = data.services;
                
                // Update Node-RED status
                elements.noderedStatus.innerHTML = 
                    node_red.status === 'ok' 
                        ? '<span class="status-dot online"></span> Online' 
                        : '<span class="status-dot error"></span> Offline';
                
                // Update VictoriaMetrics status
                elements.vmStatus.innerHTML = 
                    victoria_metrics.status === 'ok' 
                        ? '<span class="status-dot online"></span> Online' 
                        : '<span class="status-dot error"></span> Offline';
            }
        })
        .catch(error => {
            console.error('Error checking system status:', error);
        });
}

// Initialize or update the pH & EC chart
function updateChart(data) {
    // Only update if we have chart data
    if (!data || !data.pH || !data.EC) return;
    
    // Get current time for label
    const now = new Date();
    const timeLabel = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    
    // Add new data point
    state.chartData.labels.push(timeLabel);
    state.chartData.ph.push(data.pH);
    state.chartData.ec.push(data.EC);
    
    // Keep only the last 10 data points
    if (state.chartData.labels.length > 10) {
        state.chartData.labels.shift();
        state.chartData.ph.shift();
        state.chartData.ec.shift();
    }
    
    // If chart is not yet initialized and Chart.js is loaded, create it
    if (!state.phEcChart && window.Chart) {
        initializeChart();
    } else if (state.phEcChart) {
        // Update existing chart
        state.phEcChart.update();
    }
}

// Initialize the pH & EC chart
function initializeChart() {
    const ctx = document.getElementById('ph-ec-chart').getContext('2d');
    
    state.phEcChart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: state.chartData.labels,
            datasets: [
                {
                    label: 'pH',
                    data: state.chartData.ph,
                    borderColor: '#e63757',
                    backgroundColor: 'rgba(230, 55, 87, 0.1)',
                    tension: 0.4,
                    yAxisID: 'y'
                },
                {
                    label: 'EC (mS/cm)',
                    data: state.chartData.ec,
                    borderColor: '#2c7be5',
                    backgroundColor: 'rgba(44, 123, 229, 0.1)',
                    tension: 0.4,
                    yAxisID: 'y1'
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
            scales: {
                y: {
                    title: {
                        display: true,
                        text: 'pH'
                    },
                    min: 0,
                    max: 14,
                    grid: {
                        display: true
                    }
                },
                y1: {
                    title: {
                        display: true,
                        text: 'EC (mS/cm)'
                    },
                    position: 'right',
                    min: 0,
                    grid: {
                        display: false
                    }
                }
            },
            animation: false // Disable animations to save CPU
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
        })
        .catch(error => {
            console.error('Error fetching latest data:', error);
        });
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
        
        // Close the connection
        eventSource.close();
        
        // Try to reconnect after 5 seconds
        setTimeout(connectSSE, 5000);
    };
}

// Initialize dashboard
function initDashboard() {
    // Update system status
    updateSystemStatus();
    
    // Fetch initial data
    fetchLatestData();
    
    // Connect to SSE for real-time updates
    connectSSE();
    
    // Check system status every 30 seconds
    setInterval(updateSystemStatus, 30000);
    
    // Fallback polling for data every 30 seconds in case SSE fails
    setInterval(fetchLatestData, 30000);
    
    // Lazy load Chart.js
    if (document.getElementById('ph-ec-chart')) {
        const chartScript = document.createElement('script');
        chartScript.src = '/static/js/chart.min.js';
        chartScript.onload = function() {
            if (state.chartData.labels.length > 0) {
                initializeChart();
            }
        };
        document.body.appendChild(chartScript);
    }
}

// Start the dashboard when DOM is loaded
document.addEventListener('DOMContentLoaded', initDashboard); 