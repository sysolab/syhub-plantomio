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
    systemLoad: document.getElementById('system-load'),
    
    // Charts
    mainChart: document.getElementById('main-chart'),
    
    // Progress bars
    tdsProgress: document.getElementById('tds-progress'),
    ecProgress: document.getElementById('ec-progress'),
    
    // Year in footer
    currentYear: document.getElementById('current-year')
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

// Update progress bars
function updateProgressBars(data) {
    if (!data) return;
    
    // Update TDS progress bar (0-1000ppm scale)
    if (data.TDS !== undefined) {
        const tdsPercent = Math.min(100, (data.TDS / 1000) * 100);
        elements.tdsProgress.style.width = `${tdsPercent}%`;
    }
    
    // Update EC progress bar (0-3 mS/cm scale)
    if (data.EC !== undefined) {
        const ecPercent = Math.min(100, (data.EC / 3) * 100);
        elements.ecProgress.style.width = `${ecPercent}%`;
    }
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
    
    // Update progress bars
    updateProgressBars(data);
    
    // Update last update time
    if (data.lastUpdate) {
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
                elements.noderedStatus.innerHTML = 
                    node_red.status === 'ok' 
                        ? '<span class="status-dot online"></span> Online' 
                        : '<span class="status-dot error"></span> Offline';
                
                // Update VictoriaMetrics status
                elements.vmStatus.innerHTML = 
                    victoria_metrics.status === 'ok' 
                        ? '<span class="status-dot online"></span> Online' 
                        : '<span class="status-dot error"></span> Offline';
                
                // Update system load (using random value as placeholder)
                const cpuLoad = Math.round(Math.random() * 30 + 10);
                elements.systemLoad.textContent = `${cpuLoad}%`;
            }
        })
        .catch(error => {
            console.error('Error checking system status:', error);
        });
}

// Initialize or update the main chart
function updateChart(data) {
    // Only update if we have chart data
    if (!data || !data.temperature || !data.pH || !data.EC) return;
    
    // Get current time for label
    const now = new Date();
    const timeLabel = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    
    // Add new data point
    state.chartData.labels.push(timeLabel);
    state.chartData.temperature.push(data.temperature);
    state.chartData.ph.push(data.pH);
    state.chartData.ec.push(data.EC);
    
    // Keep only the last 12 data points
    if (state.chartData.labels.length > 12) {
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
        state.mainChart.update();
    }
}

// Initialize the main chart
function initializeChart() {
    if (!elements.mainChart) return;
    
    const ctx = elements.mainChart.getContext('2d');
    
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
                    pointRadius: 3,
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
                    pointRadius: 3,
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
                    pointRadius: 3,
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
                    padding: 12,
                    boxPadding: 6
                }
            },
            scales: {
                x: {
                    grid: {
                        display: false
                    }
                },
                'y-temperature': {
                    title: {
                        display: true,
                        text: '°C',
                        color: '#F6C343'
                    },
                    position: 'left',
                    grid: {
                        display: false
                    },
                    ticks: {
                        color: '#F6C343'
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
                        color: '#4e73df'
                    }
                },
                'y-ec': {
                    title: {
                        display: true,
                        text: 'EC',
                        color: '#1cc88a'
                    },
                    position: 'right',
                    min: 0,
                    max: 3,
                    grid: {
                        display: false
                    },
                    ticks: {
                        color: '#1cc88a'
                    },
                    display: false  // Hidden by default, can be toggled
                }
            },
            animation: {
                duration: 250  // Fast animations
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
        
        // Try to reconnect after a delay
        setTimeout(() => {
            if (!state.connected) {
                connectSSE();
            }
        }, 5000);
    };
}

// Initialize dashboard
function initDashboard() {
    // Initial system status
    checkSystemStatus();
    
    // Fetch initial data
    fetchLatestData();
    
    // Connect to SSE
    connectSSE();
    
    // Update system status periodically
    setInterval(checkSystemStatus, 30000);
}

// Initialize when DOM is fully loaded
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initDashboard);
} else {
    initDashboard();
} 