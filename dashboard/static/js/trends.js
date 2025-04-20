// trends.js - JavaScript for the trends page
// Handles chart rendering and data loading

// State management
const state = {
    timeRange: '1h', // Default time range
    charts: {},
    chartOptions: {
        temperature: {
            label: 'Temperature (°C)',
            color: '#F6C343',
            min: 15,
            max: 35,
            decimals: 1
        },
        pH: {
            label: 'pH',
            color: '#4e73df',
            min: 0,
            max: 14,
            decimals: 1
        },
        EC: {
            label: 'EC (mS/cm)',
            color: '#1cc88a',
            min: 0,
            max: 3,
            decimals: 2
        },
        TDS: {
            label: 'TDS (ppm)',
            color: '#36b9cc',
            min: 0,
            max: 1000,
            decimals: 0
        },
        waterLevel: {
            label: 'Water Level (%)',
            color: '#4e73df',
            min: 0,
            max: 100,
            decimals: 1
        }
    }
};

// Converts timestamp to formatted date/time string
function formatTimestamp(timestamp) {
    const date = new Date(timestamp * 1000); // Convert to milliseconds
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

// Initialize all charts on the page
function initializeCharts() {
    // Find chart canvases
    const chartElements = {
        temperature: document.getElementById('temperature-chart'),
        pH: document.getElementById('ph-chart'),
        EC: document.getElementById('ec-chart'),
        TDS: document.getElementById('tds-chart'),
        waterLevel: document.getElementById('water-level-chart')
    };
    
    // Initialize each chart
    for (const [metric, element] of Object.entries(chartElements)) {
        if (element && state.chartOptions[metric]) {
            const options = state.chartOptions[metric];
            initChart(metric, element, options);
        }
    }
    
    // Load initial data
    loadTrendsData(state.timeRange);
}

// Initialize a single chart
function initChart(metric, element, options) {
    if (!element) return;
    
    const ctx = element.getContext('2d');
    state.charts[metric] = new Chart(ctx, {
        type: 'line',
        data: {
            labels: [],
            datasets: [{
                label: options.label,
                data: [],
                borderColor: options.color,
                backgroundColor: `${options.color}20`, // 20 is hex for 12% opacity
                borderWidth: 2,
                tension: 0.4,
                pointRadius: 2,
                pointBackgroundColor: options.color,
                fill: true
            }]
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
                y: {
                    title: {
                        display: true,
                        text: options.label,
                        color: options.color
                    },
                    min: options.min,
                    max: options.max,
                    ticks: {
                        color: options.color
                    }
                }
            },
            animation: {
                duration: 300
            }
        }
    });
}

// Load data from API based on selected time range
function loadTrendsData(timeRange) {
    // Convert time range to minutes
    let minutes = 10; // Default 10 minutes
    switch (timeRange) {
        case '1h': minutes = 60; break;
        case '6h': minutes = 360; break;
        case '24h': minutes = 1440; break;
        case '7d': minutes = 10080; break;
        default: minutes = 60;
    }
    
    // Show loading indicators
    document.querySelectorAll('.chart-container').forEach(container => {
        container.classList.add('loading');
    });
    
    // Fetch data from API
    fetch(`/api/trends?minutes=${minutes}`)
        .then(response => response.json())
        .then(data => {
            if (data && data.status === 'success' && data.data) {
                updateCharts(data.data);
            } else {
                console.error('Invalid data format received from API');
            }
        })
        .catch(error => {
            console.error('Error fetching trends data:', error);
        })
        .finally(() => {
            // Hide loading indicators
            document.querySelectorAll('.chart-container').forEach(container => {
                container.classList.remove('loading');
            });
        });
}

// Update all charts with new data
function updateCharts(data) {
    // Process each metric
    for (const [metric, values] of Object.entries(data)) {
        if (state.charts[metric] && values && values.length > 0) {
            // Format timestamps and prepare data points
            const labels = [];
            const dataPoints = [];
            
            // Get chart options for formatting
            const options = state.chartOptions[metric] || { decimals: 1 };
            
            // Sort values by timestamp (ascending)
            values.sort((a, b) => a[0] - b[0]);
            
            // Extract data points
            values.forEach(point => {
                const [timestamp, value] = point;
                labels.push(formatTimestamp(timestamp));
                dataPoints.push(parseFloat(value).toFixed(options.decimals));
            });
            
            // Update chart data
            state.charts[metric].data.labels = labels;
            state.charts[metric].data.datasets[0].data = dataPoints;
            
            // Update y-axis scale if needed
            updateChartScale(state.charts[metric], dataPoints, options);
            
            // Refresh chart
            state.charts[metric].update();
        }
    }
}

// Update chart scale based on data range
function updateChartScale(chart, dataPoints, options) {
    if (!dataPoints || dataPoints.length === 0) return;
    
    // Convert string values to numbers
    const numericData = dataPoints.map(p => parseFloat(p)).filter(p => !isNaN(p));
    
    if (numericData.length === 0) return;
    
    // Calculate min and max with padding
    const minValue = Math.min(...numericData);
    const maxValue = Math.max(...numericData);
    
    // Only adjust if data is outside current range
    const yScale = chart.options.scales.y;
    const padding = (maxValue - minValue) * 0.1; // 10% padding
    
    if (minValue < yScale.min) {
        yScale.min = Math.max(options.min, Math.floor(minValue - padding));
    }
    
    if (maxValue > yScale.max) {
        yScale.max = Math.min(options.max, Math.ceil(maxValue + padding));
    }
}

// Event listener for time range buttons
function setupTimeRangeButtons() {
    const buttons = document.querySelectorAll('.time-range-selector .btn');
    buttons.forEach(button => {
        button.addEventListener('click', function() {
            // Update active button
            buttons.forEach(btn => btn.classList.remove('active'));
            this.classList.add('active');
            
            // Get time range and update charts
            const range = this.getAttribute('data-range');
            if (range && range !== state.timeRange) {
                state.timeRange = range;
                loadTrendsData(range);
            }
        });
    });
}

// Export functionality
function setupExportButtons() {
    const exportDataBtn = document.getElementById('export-data');
    const exportGraphBtn = document.getElementById('export-graph');
    
    if (exportDataBtn) {
        exportDataBtn.addEventListener('click', function() {
            const sensor = document.getElementById('export-sensor').value;
            const range = document.getElementById('export-range').value;
            
            // Create CSV from chart data
            if (state.charts[sensor] && state.charts[sensor].data.labels.length > 0) {
                const labels = state.charts[sensor].data.labels;
                const data = state.charts[sensor].data.datasets[0].data;
                
                let csv = 'Time,' + state.chartOptions[sensor].label + '\n';
                for (let i = 0; i < labels.length; i++) {
                    csv += labels[i] + ',' + data[i] + '\n';
                }
                
                // Create download
                const blob = new Blob([csv], { type: 'text/csv' });
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.setAttribute('href', url);
                a.setAttribute('download', `${sensor}_data_${range}.csv`);
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
            } else {
                alert('No data available for this sensor');
            }
        });
    }
    
    if (exportGraphBtn) {
        exportGraphBtn.addEventListener('click', function() {
            const sensor = document.getElementById('export-sensor').value;
            const range = document.getElementById('export-range').value;
            
            // Export chart as image
            if (state.charts[sensor]) {
                const url = state.charts[sensor].toBase64Image();
                const a = document.createElement('a');
                a.setAttribute('href', url);
                a.setAttribute('download', `${sensor}_chart_${range}.png`);
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
            } else {
                alert('Chart not available');
            }
        });
    }
}

// Initialize everything when DOM is ready
document.addEventListener('DOMContentLoaded', function() {
    setupTimeRangeButtons();
    setupExportButtons();
    initializeCharts();
}); 