// Trends.js - JavaScript for the trends page
// Optimized for low resource systems like Raspberry Pi 3B

// Cache DOM elements
const timeButtons = document.querySelectorAll('.time-btn');
const currentYear = document.getElementById('current-year');

// Set current year in footer
currentYear.textContent = new Date().getFullYear();

// State management
const state = {
    timeRange: '1h',
    charts: {},
    metrics: [
        { id: 'temperature', name: 'plantomio_temperature', label: 'Temperature', unit: '°C', color: '#2c7be5' },
        { id: 'ph', name: 'plantomio_pH', label: 'pH', unit: '', color: '#e63757' },
        { id: 'ec', name: 'plantomio_EC', label: 'EC', unit: 'mS/cm', color: '#00b074' },
        { id: 'orp', name: 'plantomio_ORP', label: 'ORP', unit: 'mV', color: '#f6c343' },
        { id: 'tds', name: 'plantomio_TDS', label: 'TDS', unit: 'ppm', color: '#39afd1' },
        { id: 'water-level', name: 'plantomio_waterLevel', label: 'Water Level', unit: '%', color: '#12263f' }
    ]
};

// Calculate time range values based on selected range
function getTimeRange(range) {
    const end = Math.floor(Date.now() / 1000); // Current time in seconds
    let start, step;
    
    switch (range) {
        case '1h':
            start = end - 3600; // 1 hour
            step = '10s';
            break;
        case '6h':
            start = end - 21600; // 6 hours
            step = '1m';
            break;
        case '24h':
            start = end - 86400; // 24 hours
            step = '5m';
            break;
        case '7d':
            start = end - 604800; // 7 days
            step = '1h';
            break;
        default:
            start = end - 3600; // Default to 1 hour
            step = '10s';
    }
    
    return { start, end, step };
}

// Format timestamp for display
function formatTimestamp(timestamp, timeRange) {
    const date = new Date(timestamp * 1000);
    
    if (timeRange === '7d') {
        return date.toLocaleDateString([], { month: 'short', day: 'numeric' }) + 
               ' ' + date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    } else if (timeRange === '24h') {
        return date.toLocaleDateString([], { weekday: 'short' }) + 
               ' ' + date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    } else {
        return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }
}

// Fetch historical data for a metric
async function fetchHistoricalData(metric, timeRange) {
    const { start, end, step } = getTimeRange(timeRange);
    const url = `/api/query?metric=${metric}&start=${start}&end=${end}&step=${step}`;
    
    try {
        const response = await fetch(url);
        const data = await response.json();
        
        if (data && data.data && data.data.result && data.data.result.length > 0) {
            const series = data.data.result[0];
            const values = series.values || [];
            
            // Extract timestamps and values
            const timestamps = values.map(v => formatTimestamp(v[0], timeRange));
            const dataPoints = values.map(v => parseFloat(v[1]));
            
            return { timestamps, dataPoints };
        }
        
        return { timestamps: [], dataPoints: [] };
    } catch (error) {
        console.error(`Error fetching data for ${metric}:`, error);
        return { timestamps: [], dataPoints: [] };
    }
}

// Initialize all charts
async function initializeCharts() {
    // Load all metrics in parallel
    const promises = state.metrics.map(metric => fetchHistoricalData(metric.name, state.timeRange));
    const results = await Promise.all(promises);
    
    // Create a chart for each metric
    state.metrics.forEach((metric, index) => {
        const { timestamps, dataPoints } = results[index];
        createOrUpdateChart(metric, timestamps, dataPoints);
    });
}

// Create or update a chart
function createOrUpdateChart(metric, labels, data) {
    const chartId = `${metric.id}-chart`;
    const canvas = document.getElementById(chartId);
    
    if (!canvas) return;
    
    // If chart already exists, update it
    if (state.charts[chartId]) {
        const chart = state.charts[chartId];
        chart.data.labels = labels;
        chart.data.datasets[0].data = data;
        chart.update();
        return;
    }
    
    // Create new chart
    const ctx = canvas.getContext('2d');
    state.charts[chartId] = new Chart(ctx, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                label: `${metric.label} ${metric.unit ? `(${metric.unit})` : ''}`,
                data: data,
                borderColor: metric.color,
                backgroundColor: hexToRgba(metric.color, 0.1),
                tension: 0.4,
                borderWidth: 2,
                pointRadius: 0, // Hide points for performance
                pointHoverRadius: 4
            }]
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
                    beginAtZero: metric.id !== 'ph',
                    title: {
                        display: true,
                        text: metric.unit ? metric.unit : undefined
                    }
                },
                x: {
                    title: {
                        display: false
                    }
                }
            },
            plugins: {
                legend: {
                    display: false
                },
                tooltip: {
                    enabled: true
                }
            },
            animation: false // Disable animations to save resources
        }
    });
}

// Convert hex color to rgba for transparency
function hexToRgba(hex, alpha) {
    const r = parseInt(hex.slice(1, 3), 16);
    const g = parseInt(hex.slice(3, 5), 16);
    const b = parseInt(hex.slice(5, 7), 16);
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

// Update all charts when time range changes
async function updateAllCharts() {
    // Load all metrics in parallel
    const promises = state.metrics.map(metric => fetchHistoricalData(metric.name, state.timeRange));
    const results = await Promise.all(promises);
    
    // Update each chart
    state.metrics.forEach((metric, index) => {
        const { timestamps, dataPoints } = results[index];
        createOrUpdateChart(metric, timestamps, dataPoints);
    });
}

// Event listeners for time range buttons
timeButtons.forEach(button => {
    button.addEventListener('click', async function() {
        // Update active button
        timeButtons.forEach(btn => btn.classList.remove('active'));
        this.classList.add('active');
        
        // Update time range
        state.timeRange = this.getAttribute('data-range');
        
        // Update charts
        await updateAllCharts();
    });
});

// Initialize the trends page
async function initTrends() {
    // Initialize charts
    await initializeCharts();
    
    // Update year in footer
    currentYear.textContent = new Date().getFullYear();
}

// Start the trends page when DOM is loaded
document.addEventListener('DOMContentLoaded', initTrends); 