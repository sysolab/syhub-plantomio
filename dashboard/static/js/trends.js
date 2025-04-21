// Simplified trends.js - For reliable chart rendering
document.addEventListener('DOMContentLoaded', function() {
    // Get device ID
    const deviceId = document.getElementById('device-id')?.textContent || 'plt-404cca470da0';
    
    // Initialize charts with default time range (24 hours)
    loadAllCharts(1440, deviceId);
    
    // Set up time range buttons
    document.querySelectorAll('.time-btn').forEach(button => {
        button.addEventListener('click', function() {
            // Update active button
            document.querySelectorAll('.time-btn').forEach(btn => {
                btn.classList.remove('active');
            });
            this.classList.add('active');
            
            // Get time range
            let minutes = 1440;
            if (this.textContent === '24 Hours') minutes = 1440;
            else if (this.textContent === 'Week') minutes = 10080;
            else if (this.textContent === 'Month') minutes = 43200;
            else if (this.textContent === 'Custom') {
                // Show date picker
                document.querySelector('.date-range-selector').style.display = 'flex';
                return;
            }
            
            // Hide date picker if not custom
            document.querySelector('.date-range-selector').style.display = 'none';
            
            // Load charts with new time range
            loadAllCharts(minutes, deviceId);
        });
    });
    
    // Custom date range button
    const applyBtn = document.querySelector('.btn-apply');
    if (applyBtn) {
        applyBtn.addEventListener('click', function() {
            const startDate = new Date(document.getElementById('start-date').value);
            const endDate = new Date(document.getElementById('end-date').value);
            
            if (!startDate || !endDate) {
                alert('Please select valid dates');
                return;
            }
            
            const diffMinutes = Math.round((endDate - startDate) / 60000);
            if (diffMinutes <= 0) {
                alert('End date must be after start date');
                return;
            }
            
            // Load charts with custom time range
            loadAllCharts(diffMinutes, deviceId);
        });
    }
    
    // Export buttons
    document.querySelectorAll('.btn-export').forEach(button => {
        button.addEventListener('click', function() {
            // Find the chart container
            const panel = this.closest('.chart-panel');
            if (!panel) return;
            
            const heading = panel.querySelector('h2');
            if (!heading) return;
            
            // Get metric from heading
            const headingText = heading.textContent.trim().toLowerCase();
            let metric = '';
            
            if (headingText.includes('temperature')) metric = 'temperature';
            else if (headingText.includes('ph')) metric = 'pH';
            else if (headingText.includes('tds')) metric = 'TDS';
            else if (headingText.includes('ec')) metric = 'EC';
            else if (headingText.includes('distance')) metric = 'distance';
            else if (headingText.includes('orp')) metric = 'ORP';
            
            if (!metric) {
                alert('Cannot identify chart metric');
                return;
            }
            
            // Get time range
            let minutes = 1440;
            const activeBtn = document.querySelector('.time-btn.active');
            if (activeBtn) {
                if (activeBtn.textContent === 'Week') minutes = 10080;
                else if (activeBtn.textContent === 'Month') minutes = 43200;
            }
            
            // Get the time range from the dropdown if available
            const timeDropdown = document.getElementById('time-range-dropdown');
            if (timeDropdown) {
                minutes = parseInt(timeDropdown.value) || 1440;
            }
            
            // Get chart data and export (using full resolution export endpoint)
            fetch(`/api/export?metric=${metric}&device=${deviceId}&minutes=${minutes}`)
                .then(response => response.json())
                .then(data => {
                    if (!data.status || data.status !== 'success' || !data.data || data.data.length === 0) {
                        throw new Error('No data available');
                    }
                    
                    // Create CSV content
                    let csv = 'Timestamp,' + getMetricLabel(metric) + '\n';
                    data.data.forEach(point => {
                        csv += point.datetime + ',' + (point.value !== null ? point.value : '') + '\n';
                    });
                    
                    // Create download
                    const blob = new Blob([csv], { type: 'text/csv' });
                    const url = URL.createObjectURL(blob);
                    const a = document.createElement('a');
                    a.href = url;
                    a.download = `${metric}_data.csv`;
                    document.body.appendChild(a);
                    a.click();
                    document.body.removeChild(a);
                    URL.revokeObjectURL(url);
                })
                .catch(error => {
                    alert('Error exporting data: ' + error.message);
                });
        });
    });
    
    // Mobile sidebar toggle
    document.getElementById('mobile-toggle').addEventListener('click', function() {
        document.querySelector('.sidebar').classList.toggle('active');
    });
});

// Load all charts
function loadAllCharts(minutes, deviceId) {
    // Get list of metrics to load
    const metrics = ['temperature', 'pH', 'TDS', 'EC', 'distance', 'ORP'];
    
    // Set loading state for all charts
    metrics.forEach(metric => {
        const container = document.getElementById(`${metric}-chart-container`);
        const messageEl = document.getElementById(`${metric}-chart-message`);
        
        if (container && messageEl) {
            messageEl.textContent = 'Loading data...';
            messageEl.style.display = 'block';
            
            // Adjust canvas opacity
            const canvas = container.querySelector('canvas');
            if (canvas) {
                canvas.style.opacity = '0.5';
            }
        }
    });
    
    // Fetch data for all metrics at once to reduce API calls
    fetch(`/api/trends?metrics=${metrics.join(',')}&device=${deviceId}&minutes=${minutes}`)
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error: ${response.status}`);
            }
            return response.json();
        })
        .then(result => {
            if (result.status !== 'success' || !result.data) {
                throw new Error('Invalid API response');
            }
            
            // Process each metric
            metrics.forEach(metric => {
                updateChart(metric, result.data[metric] || [], deviceId);
            });
        })
        .catch(error => {
            console.error('Error loading charts:', error);
            
            // Show error for all charts
            metrics.forEach(metric => {
                const container = document.getElementById(`${metric}-chart-container`);
                const messageEl = document.getElementById(`${metric}-chart-message`);
                
                if (container && messageEl) {
                    messageEl.textContent = 'Error loading data: ' + error.message;
                    messageEl.style.display = 'block';
                    
                    // Reset canvas opacity
                    const canvas = container.querySelector('canvas');
                    if (canvas) {
                        canvas.style.opacity = '1';
                    }
                }
            });
        });
}

// Update a specific chart
function updateChart(metric, data, deviceId) {
    // Get chart elements
    const canvasId = metric === 'pH' ? 'ph-chart' : `${metric.toLowerCase()}-chart`;
    const canvas = document.getElementById(canvasId);
    
    const containerId = `${metric}-chart-container`;
    const container = document.getElementById(containerId);
    
    const messageId = `${metric}-chart-message`;
    const messageEl = document.getElementById(messageId);
    
    if (!canvas || !container || !messageEl) {
        console.error(`Elements not found for ${metric}`);
        return;
    }
    
    // Reset canvas opacity
    canvas.style.opacity = '1';
    
    // Check if we have data
    if (!Array.isArray(data) || data.length === 0) {
        messageEl.textContent = 'No data available for the selected time range';
        messageEl.style.display = 'block';
        
        // Clear canvas
        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        
        // Destroy existing chart
        if (window.chartInstances && window.chartInstances[metric]) {
            window.chartInstances[metric].destroy();
            window.chartInstances[metric] = null;
        }
        return;
    }
    
    // Hide error message
    messageEl.style.display = 'none';
    
    // Process data for chart
    const labels = [];
    const values = [];
    
    data.forEach(point => {
        if (Array.isArray(point) && point.length === 2) {
            const [timestamp, value] = point;
            
            // Format timestamp
            const date = new Date(timestamp * 1000);
            labels.push(date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}));
            
            // Add value (null if missing)
            values.push(value);
        }
    });
    
    // Get chart configuration
    const config = getChartConfig(metric);
    
    // Destroy existing chart
    if (window.chartInstances && window.chartInstances[metric]) {
        window.chartInstances[metric].destroy();
        window.chartInstances[metric] = null;
    }
    
    // Create chart
    const ctx = canvas.getContext('2d');
    
    try {
        // Initialize chart instances object if it doesn't exist
        window.chartInstances = window.chartInstances || {};
        
        // Create chart
        window.chartInstances[metric] = new Chart(ctx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: [{
                    label: config.label,
                    data: values,
                    borderColor: config.color,
                    backgroundColor: config.bgColor,
                    tension: 0.4,
                    borderWidth: 2,
                    fill: true,
                    spanGaps: true
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'top',
                    },
                    title: {
                        display: true,
                        text: `Device: ${deviceId}`
                    }
                },
                scales: {
                    y: {
                        beginAtZero: metric === 'pH' || metric === 'distance',
                        grid: {
                            color: 'rgba(0, 0, 0, 0.05)'
                        }
                    },
                    x: {
                        grid: {
                            display: false
                        }
                    }
                }
            }
        });
    } catch (e) {
        console.error(`Error creating ${metric} chart:`, e);
        messageEl.textContent = "Error creating chart";
        messageEl.style.display = 'block';
        
        // Clear the canvas to avoid contamination
        ctx.clearRect(0, 0, canvas.width, canvas.height);
    }
}

// Get chart configuration
function getChartConfig(metric) {
    switch (metric) {
        case 'temperature':
            return {
                label: 'Temperature (°C)',
                color: '#4e73df',
                bgColor: 'rgba(78, 115, 223, 0.1)'
            };
        case 'pH':
            return {
                label: 'pH Level',
                color: '#e74a3b',
                bgColor: 'rgba(231, 74, 59, 0.1)'
            };
        case 'TDS':
            return {
                label: 'TDS (ppm)',
                color: '#1cc88a',
                bgColor: 'rgba(28, 200, 138, 0.1)'
            };
        case 'EC':
            return {
                label: 'EC (μS/cm)',
                color: '#36b9cc',
                bgColor: 'rgba(54, 185, 204, 0.1)'
            };
        case 'distance':
            return {
                label: 'Distance (m)',
                color: '#f6c23e',
                bgColor: 'rgba(246, 194, 62, 0.1)'
            };
        case 'ORP':
            return {
                label: 'ORP (mV)',
                color: '#6f42c1',
                bgColor: 'rgba(111, 66, 193, 0.1)'
            };
        default:
            return {
                label: metric,
                color: '#858796',
                bgColor: 'rgba(133, 135, 150, 0.1)'
            };
    }
}

// Get metric label
function getMetricLabel(metric) {
    switch (metric) {
        case 'temperature': return 'Temperature (°C)';
        case 'pH': return 'pH Level';
        case 'TDS': return 'TDS (ppm)';
        case 'EC': return 'EC (μS/cm)';
        case 'distance': return 'Distance (m)';
        case 'ORP': return 'ORP (mV)';
        default: return metric;
    }
}

// Update service status if the function exists
if (typeof updateServiceStatus === 'function') {
    // Initial update
    updateServiceStatus();
    
    // Update every 60 seconds
    setInterval(updateServiceStatus, 60000);
}