// trends.js - Optimized JavaScript for the trends page
// Handles chart rendering and data loading with improved error handling

// State management
const state = {
    timeRange: 1440, // Default time range in minutes (24 hours)
    charts: {},
    currentDevice: null,
    isLoading: false
};

// Chart configuration for different metrics
const chartConfig = {
    temperature: {
        label: 'Temperature (°C)',
        color: '#4e73df',
        background: 'rgba(78, 115, 223, 0.1)',
        min: 10,
        max: 40
    },
    pH: {
        label: 'pH Level',
        color: '#e74a3b',
        background: 'rgba(231, 74, 59, 0.1)',
        min: 0, 
        max: 14
    },
    TDS: {
        label: 'TDS (ppm)',
        color: '#1cc88a',
        background: 'rgba(28, 200, 138, 0.1)',
        min: 0,
        max: 2000
    },
    EC: {
        label: 'EC (μS/cm)',
        color: '#36b9cc',
        background: 'rgba(54, 185, 204, 0.1)',
        min: 0,
        max: 50
    },
    distance: {
        label: 'Distance (m)',
        color: '#f6c23e',
        background: 'rgba(246, 194, 62, 0.1)',
        min: 0,
        max: 10
    },
    ORP: {
        label: 'ORP (mV)',
        color: '#6f42c1',
        background: 'rgba(111, 66, 193, 0.1)',
        min: 0,
        max: 500
    }
};

// Format timestamp for display
function formatTimestamp(timestamp) {
    if (!timestamp) return '';
    const date = new Date(timestamp * 1000);
    
    // For time ranges > 24 hours, include date
    if (state.timeRange > 1440) {
        return date.toLocaleDateString([], {month: 'short', day: 'numeric'}) + ' ' +
               date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
    }
    
    return date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
}

// Handle time range selection
function setupTimeRangeButtons() {
    document.querySelectorAll('.time-btn').forEach(button => {
        button.addEventListener('click', function() {
            // Remove active class from all buttons
            document.querySelectorAll('.time-btn').forEach(btn => {
                btn.classList.remove('active');
            });
            
            // Add active class to this button
            this.classList.add('active');
            
            // Get time range in minutes
            const minutes = parseInt(this.dataset.minutes || 1440);
            if (minutes !== state.timeRange) {
                state.timeRange = minutes;
                loadAllChartData();
            }
        });
    });
}

// Handle export buttons
function setupExportButtons() {
    document.querySelectorAll('.btn-export').forEach(button => {
        button.addEventListener('click', function() {
            // Find parent panel to determine which chart to export
            const panel = this.closest('.chart-panel');
            if (!panel) return;
            
            // Determine which chart to export based on panel heading
            const heading = panel.querySelector('h2');
            if (!heading) return;
            
            const headingText = heading.textContent.trim().toLowerCase();
            let metric = '';
            
            if (headingText.includes('temperature')) metric = 'temperature';
            else if (headingText.includes('ph')) metric = 'pH';
            else if (headingText.includes('tds')) metric = 'TDS';
            else if (headingText.includes('ec')) metric = 'EC';
            else if (headingText.includes('distance')) metric = 'distance';
            else if (headingText.includes('orp')) metric = 'ORP';
            
            if (!metric || !state.charts[metric]) {
                alert('Cannot export: Chart not found');
                return;
            }
            
            // Create CSV data from chart
            const chart = state.charts[metric];
            const labels = chart.data.labels;
            const data = chart.data.datasets[0].data;
            
            let csv = 'Time,' + chartConfig[metric].label + '\n';
            for (let i = 0; i < labels.length; i++) {
                csv += labels[i] + ',' + (data[i] !== null ? data[i] : '') + '\n';
            }
            
            // Create download link
            const blob = new Blob([csv], { type: 'text/csv' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `${metric}_data.csv`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
        });
    });
}

// Initialize the page
document.addEventListener('DOMContentLoaded', function() {
    // Setup event handlers
    setupTimeRangeButtons();
    setupExportButtons();
    
    // Mobile menu toggle
    const mobileToggle = document.getElementById('mobile-toggle');
    if (mobileToggle) {
        mobileToggle.addEventListener('click', function() {
            document.querySelector('.sidebar').classList.toggle('active');
        });
    }
    
    // Initialize charts and load data
    initializeAllCharts();
    
    // Update service status
    if (typeof updateServiceStatus === 'function') {
        updateServiceStatus();
        // Update every 60 seconds
        setInterval(updateServiceStatus, 60000);
    }
});

// Set loading state for all charts
function setLoading(isLoading) {
    state.isLoading = isLoading;
    
    // Update UI to reflect loading state
    document.querySelectorAll('.chart-container').forEach(container => {
        const messageEl = container.querySelector('.chart-message');
        if (messageEl) {
            if (isLoading) {
                messageEl.textContent = "Loading data...";
                messageEl.style.display = 'block';
            } else {
                messageEl.style.display = 'none';
            }
        }
        
        // Adjust opacity of canvas
        const canvas = container.querySelector('canvas');
        if (canvas) {
            canvas.style.opacity = isLoading ? '0.5' : '1';
        }
    });
}

// Show error message for a specific chart
function showChartError(metricId, message) {
    const container = document.getElementById(`${metricId}-chart-container`);
    const messageEl = document.getElementById(`${metricId}-chart-message`);
    
    if (container && messageEl) {
        messageEl.textContent = message || "Error loading data";
        messageEl.style.display = 'block';
        container.classList.add('no-data');
    }
}

// Clear error message for a specific chart
function clearChartError(metricId) {
    const container = document.getElementById(`${metricId}-chart-container`);
    const messageEl = document.getElementById(`${metricId}-chart-message`);
    
    if (container && messageEl) {
        messageEl.style.display = 'none';
        container.classList.remove('no-data');
    }
}

// Initialize a chart for a specific metric
function initializeChart(metric) {
    // Get canvas element
    const canvasId = metric === 'pH' ? 'ph-chart' : `${metric.toLowerCase()}-chart`;
    const canvas = document.getElementById(canvasId);
    
    if (!canvas) {
        console.error(`Canvas for ${metric} not found`);
        return;
    }
    
    // Get chart configuration
    const config = chartConfig[metric];
    if (!config) {
        console.error(`Configuration for ${metric} not found`);
        return;
    }
    
    // Initialize Chart.js instance with empty data
    const ctx = canvas.getContext('2d');
    
    // Destroy existing chart if it exists
    if (state.charts[metric]) {
        state.charts[metric].destroy();
        state.charts[metric] = null;
    }
    
    // Create new chart
    state.charts[metric] = new Chart(ctx, {
        type: 'line',
        data: {
            labels: [],
            datasets: [{
                label: config.label,
                data: [],
                borderColor: config.color,
                backgroundColor: config.background,
                tension: 0.4,
                borderWidth: 2,
                fill: true,
                pointRadius: 2,
                pointHoverRadius: 5
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'top',
                    labels: {
                        font: {
                            size: 12
                        }
                    }
                },
                tooltip: {
                    callbacks: {
                        label: function(context) {
                            let label = context.dataset.label || '';
                            if (label) {
                                label += ': ';
                            }
                            if (context.parsed.y !== null) {
                                label += context.parsed.y.toFixed(2);
                            }
                            return label;
                        }
                    }
                }
            },
            scales: {
                y: {
                    beginAtZero: metric === 'pH' || metric === 'distance' ? true : false,
                    grid: {
                        color: 'rgba(0, 0, 0, 0.05)'
                    },
                    min: config.min,
                    max: config.max,
                    ticks: {
                        maxTicksLimit: 6
                    }
                },
                x: {
                    grid: {
                        display: false
                    },
                    ticks: {
                        maxTicksLimit: 8
                    }
                }
            },
            animation: {
                duration: 150 // Faster animations for better performance
            }
        }
    });
    
    return state.charts[metric];
}

// Initialize all charts
function initializeAllCharts() {
    Object.keys(chartConfig).forEach(metric => {
        initializeChart(metric);
    });
    
    // Load initial data
    loadAllChartData();
}

// Load data for all charts
function loadAllChartData() {
    // Get current device
    const deviceElement = document.getElementById('device-id');
    const deviceId = deviceElement ? deviceElement.textContent.trim() : 'plt-404cca470da0';
    state.currentDevice = deviceId;
    
    // Set loading state
    setLoading(true);
    
    // Fetch data for all metrics
    const metrics = Object.keys(chartConfig).join(',');
    const url = `/api/trends?metrics=${metrics}&device=${deviceId}&minutes=${state.timeRange}`;
    
    // Fetch with timeout
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 15000); // 15 second timeout
    
    fetch(url, { signal: controller.signal })
        .then(response => {
            clearTimeout(timeoutId);
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(result => {
            if (result.status === 'success' && result.data) {
                // Process each metric
                let hasAnyData = false;
                
                Object.entries(result.data).forEach(([metric, data]) => {
                    if (updateChart(metric, data)) {
                        hasAnyData = true;
                    }
                });
                
                if (!hasAnyData) {
                    console.warn('No data available for any metrics');
                }
            } else {
                console.error('Invalid API response format:', result);
                throw new Error('Invalid API response format');
            }
        })
        .catch(error => {
            console.error('Error fetching chart data:', error);
            
            // Show error on all charts
            Object.keys(chartConfig).forEach(metric => {
                showChartError(metric, 'Error loading data: ' + (error.message || 'Unknown error'));
            });
        })
        .finally(() => {
            setLoading(false);
        });
}

// Update a specific chart with new data
function updateChart(metric, data) {
    // Get chart
    const chart = state.charts[metric];
    if (!chart) {
        console.error(`Chart for ${metric} not initialized`);
        return;
    }
    
    // Extract timestamps and values
    const labels = [];
    const values = [];
    let hasData = false;
    
    if (Array.isArray(data)) {
        // Process data points
        data.forEach(point => {
            if (Array.isArray(point) && point.length === 2) {
                const [timestamp, value] = point;
                
                // Format timestamp
                labels.push(formatTimestamp(timestamp));
                
                // Handle null values
                values.push(value !== null && value !== undefined ? value : null);
                
                // Check if we have any valid data
                if (value !== null && value !== undefined) {
                    hasData = true;
                }
            }
        });
    }
    
    // Update chart data
    chart.data.labels = labels;
    chart.data.datasets[0].data = values;
    
    // Show or hide error message based on data availability
    if (!hasData) {
        showChartError(metric, "No data available for the selected time range");
    } else {
        clearChartError(metric);
        
        // Dynamically adjust Y axis if needed
        const config = chartConfig[metric];
        if (config) {
            const validValues = values.filter(v => v !== null && v !== undefined);
            if (validValues.length > 0) {
                const minValue = Math.min(...validValues);
                const maxValue = Math.max(...validValues);
                
                // Determine if we need to adjust the scale
                if (minValue < config.min || maxValue > config.max) {
                    // Calculate new min/max with 10% padding
                    const padding = (maxValue - minValue) * 0.1;
                    const newMin = Math.max(0, Math.floor(minValue - padding));
                    const newMax = Math.ceil(maxValue + padding);
                    
                    // Update chart scale
                    chart.options.scales.y.min = newMin;
                    chart.options.scales.y.max = newMax;
                } else {
                    // Reset to defaults
                    chart.options.scales.y.min = config.min;
                    chart.options.scales.y.max = config.max;
                }
            }
        }
    }
    
    // Update the chart
    chart.update();
    
    return hasData;
}