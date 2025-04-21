// Dashboard.js - Optimized JavaScript for the dashboard page
// Enhanced for better performance and reliable chart rendering

// Chart state management
let mainChart = null;  // Global reference to main chart
let isChartInitializing = false;  // Flag to prevent concurrent chart operations

// Initialize metric selectors
document.addEventListener('DOMContentLoaded', function() {
    // Set up metric selector buttons
    setupMetricButtons();
    
    // Set up time range dropdown
    setupTimeButtons();
    
    // Mobile sidebar toggle
    setupMobileToggle();
    
    // Initialize SSE connection for live data
    setupSSE();
    
    // Load device list
    fetchDevices();
    
    // Initial service status check
    updateServiceStatus();
    
    // Setup tank settings panel
    setupTankSettings();
});

// Setup metric selector buttons
function setupMetricButtons() {
    document.querySelectorAll('.metric-btn').forEach(button => {
        button.addEventListener('click', function() {
            // Set interaction active
            window.isChartInteractionActive = true;
            
            // Remove active class from all buttons
            document.querySelectorAll('.metric-btn').forEach(btn => {
                btn.classList.remove('active');
            });
            
            // Add active class to clicked button
            this.classList.add('active');
            
            // Update chart with new metric
            updateMainChart();
            
            // Reset interaction after a short delay
            setTimeout(() => {
                window.isChartInteractionActive = false;
            }, 5000);
        });
    });
}

// Setup time range dropdown
function setupTimeButtons() {
    const timeRangeDropdown = document.getElementById('time-range-dropdown');
    if (timeRangeDropdown) {
        timeRangeDropdown.addEventListener('change', function() {
            // Set interaction active
            window.isChartInteractionActive = true;
            
            // Update chart with new time range
            updateMainChart();
            
            // Reset interaction after a short delay
            setTimeout(() => {
                window.isChartInteractionActive = false;
            }, 5000);
        });
    }
}

// Setup mobile toggle button
function setupMobileToggle() {
    const mobileToggle = document.getElementById('mobile-toggle');
    if (mobileToggle) {
        mobileToggle.addEventListener('click', function() {
            document.querySelector('.sidebar').classList.toggle('active');
        });
    }
}

// Setup tank settings panel
function setupTankSettings() {
    // Tank settings modal controls
    const tankSettingsBtn = document.getElementById('tank-settings-btn');
    const tankSettingsPanel = document.getElementById('tank-settings-panel');
    const settingsBackdrop = document.getElementById('settings-backdrop');
    const tankSettingsClose = document.getElementById('tank-settings-close');
    const saveTankSettings = document.getElementById('save-tank-settings');
    
    if (tankSettingsBtn && tankSettingsPanel && settingsBackdrop) {
        // Open tank settings modal
        tankSettingsBtn.addEventListener('click', function() {
            tankSettingsPanel.classList.add('active');
            settingsBackdrop.classList.add('active');
            settingsBackdrop.style.display = 'block';
            tankSettingsPanel.style.display = 'block';
        });
        
        // Close on backdrop click
        settingsBackdrop.addEventListener('click', function() {
            tankSettingsPanel.classList.remove('active');
            settingsBackdrop.classList.remove('active');
            setTimeout(() => {
                settingsBackdrop.style.display = 'none';
                tankSettingsPanel.style.display = 'none';
            }, 300);
        });
        
        // Close on X button click
        if (tankSettingsClose) {
            tankSettingsClose.addEventListener('click', function() {
                tankSettingsPanel.classList.remove('active');
                settingsBackdrop.classList.remove('active');
                setTimeout(() => {
                    settingsBackdrop.style.display = 'none';
                    tankSettingsPanel.style.display = 'none';
                }, 300);
            });
        }
        
        // Save settings button
        if (saveTankSettings) {
            saveTankSettings.addEventListener('click', function() {
                const minLevel = parseFloat(document.getElementById('min-level').value) || 0;
                const maxLevel = parseFloat(document.getElementById('max-level').value) || 10;
                
                if (minLevel >= maxLevel) {
                    alert('Minimum level must be less than maximum level');
                    return;
                }
                
                // Save settings via API
                fetch('/api/tank-settings', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        minDistance: minLevel,
                        maxDistance: maxLevel
                    })
                })
                .then(response => response.json())
                .then(data => {
                    if (data.status === 'success') {
                        // Close modal
                        tankSettingsPanel.classList.remove('active');
                        settingsBackdrop.classList.remove('active');
                        settingsBackdrop.style.display = 'none';
                        tankSettingsPanel.style.display = 'none';
                        
                        // Refresh display
                        updateWaterLevel();
                    } else {
                        alert('Error saving settings: ' + (data.message || 'Unknown error'));
                    }
                })
                .catch(error => {
                    console.error('Error saving tank settings:', error);
                    alert('Error saving settings: ' + error.message);
                });
            });
        }
    }
}

// Function to update water level display with latest data
function updateWaterLevel() {
    // Fetch latest data to refresh the display
    fetch('/api/latest')
        .then(response => response.json())
        .then(data => {
            if (data && data.waterLevel !== undefined) {
                const tankEl = document.getElementById('tank-water-level');
                const levelEl = document.getElementById('water-level-percent');
                const valueEl = document.getElementById('water-level-value');
                
                if (tankEl) tankEl.style.height = `${data.waterLevel}%`;
                if (levelEl) levelEl.textContent = Math.round(data.waterLevel);
                if (valueEl && data.distance) valueEl.textContent = Number(data.distance).toFixed(1);
            }
        })
        .catch(error => {
            console.error('Error updating water level:', error);
        });
}

// Fetch list of available devices
function fetchDevices() {
    fetch('/api/devices')
        .then(response => response.json())
        .then(data => {
            if (data.status === "success" && data.devices && data.devices.length > 0) {
                const availableDevices = data.devices;
                
                // Set current device to first available device if not already set
                const currentDevice = window.currentDevice || availableDevices[0];
                window.currentDevice = currentDevice;
                
                // Update deviceID display
                const deviceElement = document.getElementById('device-id');
                if (deviceElement) {
                    deviceElement.textContent = currentDevice;
                }
                
                // Get the device dropdown
                const deviceDropdown = document.getElementById('device-dropdown');
                
                // If we have multiple devices, populate and show the dropdown
                if (availableDevices.length > 1 && deviceDropdown) {
                    // Clear existing options
                    deviceDropdown.innerHTML = '';
                    
                    // Add options for each device
                    availableDevices.forEach(device => {
                        const option = document.createElement('option');
                        option.value = device;
                        option.text = device;
                        
                        // Set the current device as selected
                        if (device === currentDevice) {
                            option.selected = true;
                        }
                        
                        deviceDropdown.appendChild(option);
                    });
                    
                    // Show the dropdown
                    deviceDropdown.style.display = 'inline-block';
                    
                    // Add change event handler
                    deviceDropdown.addEventListener('change', function() {
                        // Set the new current device
                        window.currentDevice = this.value;
                        
                        // Update deviceID display
                        if (deviceElement) {
                            deviceElement.textContent = this.value;
                        }
                        
                        // Reload charts with the new device
                        updateMainChart();
                    });
                }
                
                // Load initial data for the selected device
                updateMainChart();
            }
        })
        .catch(error => {
            console.error('Error fetching devices:', error);
        });
}

// Function to safely destroy the chart and reset the canvas
function resetChart() {
    // Don't try to destroy if already being reset
    if (isChartInitializing) return;
    
    try {
        // Mark as being created to prevent concurrent operations
        isChartInitializing = true;
        
        // Destroy the existing chart if it exists
        if (mainChart) {
            mainChart.destroy();
            mainChart = null;
        }
        
        // Get the container and replace the canvas with a fresh one
        const container = document.querySelector('.trends-container');
        const oldCanvas = document.getElementById('main-chart');
        
        if (container && oldCanvas) {
            // Create a new canvas with the same ID
            const newCanvas = document.createElement('canvas');
            newCanvas.id = 'main-chart';
            newCanvas.className = 'trends-chart';
            
            // Replace the old canvas with the new one
            container.removeChild(oldCanvas);
            container.appendChild(newCanvas);
        }
    } catch (e) {
        console.error("Error resetting chart:", e);
    } finally {
        // Reset the flag after a short delay to allow DOM to update
        setTimeout(() => {
            isChartInitializing = false;
        }, 50);
    }
}

// Handle chart data loading
function updateMainChart() {
    // Get current device
    const deviceId = document.getElementById('device-id')?.textContent || 'plt-404cca470da0';
    
    // Get selected metric and time range
    const selectedMetric = document.querySelector('.metric-btn.active')?.dataset.metric || 'combined';
    const timeDropdown = document.getElementById('time-range-dropdown');
    const timeMinutes = parseInt(timeDropdown?.value || 5); // Default to 5 minutes if not found
    const stepSize = timeDropdown?.options[timeDropdown.selectedIndex]?.dataset.step || '30s';
    
    console.log(`Loading chart: ${selectedMetric}, device: ${deviceId}, minutes: ${timeMinutes}, step: ${stepSize}`);
    
    // Get chart container and prepare canvas
    const container = document.querySelector('.trends-container');
    if (!container) {
        console.error('Chart container not found');
        return;
    }
    
    // Create new canvas element to avoid any issues with re-rendering
    container.innerHTML = '';
    const canvas = document.createElement('canvas');
    canvas.id = 'main-chart';
    canvas.className = 'trends-chart';
    container.appendChild(canvas);
    
    // Show loading message
    const loadingDiv = document.createElement('div');
    loadingDiv.className = 'loading-message';
    loadingDiv.textContent = 'Loading chart data...';
    container.appendChild(loadingDiv);
    
    // Handle combined chart separately
    if (selectedMetric === 'combined') {
        fetch(`/api/trends?metrics=temperature,pH,EC&device=${deviceId}&minutes=${timeMinutes}&step=${stepSize}`)
            .then(response => {
                if (!response.ok) {
                    throw new Error(`HTTP error ${response.status}`);
                }
                return response.json();
            })
            .then(data => {
                // Remove loading message
                container.removeChild(loadingDiv);
                
                if (!data.status || data.status !== 'success' || !data.data) {
                    throw new Error('Invalid API response format');
                }
                
                // Process data
                const allTimestamps = new Set();
                const tempMap = {};
                const phMap = {};
                const ecMap = {};
                
                // Collect timestamps and values
                ['temperature', 'pH', 'EC'].forEach(metric => {
                    if (Array.isArray(data.data[metric])) {
                        data.data[metric].forEach(point => {
                            if (Array.isArray(point) && point.length === 2) {
                                const [timestamp, value] = point;
                                allTimestamps.add(timestamp);
                                
                                if (metric === 'temperature') tempMap[timestamp] = value;
                                else if (metric === 'pH') phMap[timestamp] = value;
                                else if (metric === 'EC') ecMap[timestamp] = value;
                            }
                        });
                    }
                });
                
                // Convert timestamps to array and sort
                const sortedTimestamps = Array.from(allTimestamps).sort((a, b) => a - b);
                
                // Format for display
                const labels = sortedTimestamps.map(ts => {
                    const date = new Date(ts * 1000);
                    return date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
                });
                
                // Create datasets
                const tempValues = sortedTimestamps.map(ts => tempMap[ts]);
                const phValues = sortedTimestamps.map(ts => phMap[ts]);
                const ecValues = sortedTimestamps.map(ts => ecMap[ts]);
                
                // Create the chart
                const ctx = canvas.getContext('2d');
                new Chart(ctx, {
                    type: 'line',
                    data: {
                        labels: labels,
                        datasets: [
                            {
                                label: 'Temperature (°C)',
                                data: tempValues,
                                borderColor: '#4e73df',
                                backgroundColor: 'rgba(78, 115, 223, 0.1)',
                                tension: 0.4,
                                borderWidth: 2,
                                fill: false,
                                yAxisID: 'y-temperature',
                                spanGaps: true
                            },
                            {
                                label: 'pH',
                                data: phValues,
                                borderColor: '#e74a3b',
                                backgroundColor: 'rgba(231, 74, 59, 0.1)',
                                tension: 0.4,
                                borderWidth: 2,
                                fill: false,
                                yAxisID: 'y-ph',
                                spanGaps: true
                            },
                            {
                                label: 'EC (μS/cm)',
                                data: ecValues,
                                borderColor: '#36b9cc',
                                backgroundColor: 'rgba(54, 185, 204, 0.1)',
                                tension: 0.4,
                                borderWidth: 2,
                                fill: false,
                                yAxisID: 'y-ec',
                                spanGaps: true
                            }
                        ]
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
                            'y-temperature': {
                                type: 'linear',
                                display: true,
                                position: 'left',
                                title: {
                                    display: true,
                                    text: 'Temperature (°C)'
                                },
                                grid: {
                                    color: 'rgba(0, 0, 0, 0.05)'
                                }
                            },
                            'y-ph': {
                                type: 'linear',
                                display: true,
                                position: 'right',
                                title: {
                                    display: true,
                                    text: 'pH'
                                },
                                grid: {
                                    drawOnChartArea: false
                                }
                            },
                            'y-ec': {
                                type: 'linear',
                                display: true,
                                position: 'right',
                                title: {
                                    display: true,
                                    text: 'EC (μS/cm)'
                                },
                                grid: {
                                    drawOnChartArea: false
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
            })
            .catch(error => {
                console.error('Error loading combined chart:', error);
                container.innerHTML = `<div class="error-message">Error loading chart: ${error.message}</div>`;
            });
    } else {
        // For single metrics - use the trends API which has proven to work better
        fetch(`/api/trends?metrics=${selectedMetric}&device=${deviceId}&minutes=${timeMinutes}&step=${stepSize}`)
            .then(response => {
                if (!response.ok) {
                    throw new Error(`HTTP error ${response.status}`);
                }
                return response.json();
            })
            .then(data => {
                // Remove loading message
                container.removeChild(loadingDiv);
                
                if (!data.status || data.status !== 'success' || !data.data || !data.data[selectedMetric]) {
                    throw new Error('No data available for the selected metric');
                }
                
                // Process data
                const chartData = data.data[selectedMetric];
                const labels = [];
                const values = [];
                
                // Format data for Chart.js
                chartData.forEach(point => {
                    if (Array.isArray(point) && point.length === 2) {
                        const [timestamp, value] = point;
                        const date = new Date(timestamp * 1000);
                        labels.push(date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}));
                        values.push(value);
                    }
                });
                
                // Get chart color based on metric
                let borderColor, backgroundColor;
                let unit = '';
                switch (selectedMetric) {
                    case 'temperature':
                        borderColor = '#4e73df';
                        backgroundColor = 'rgba(78, 115, 223, 0.1)';
                        unit = '°C';
                        break;
                    case 'pH':
                        borderColor = '#e74a3b';
                        backgroundColor = 'rgba(231, 74, 59, 0.1)';
                        unit = '';
                        break;
                    case 'TDS':
                        borderColor = '#1cc88a';
                        backgroundColor = 'rgba(28, 200, 138, 0.1)';
                        unit = 'ppm';
                        break;
                    case 'EC':
                        borderColor = '#36b9cc';
                        backgroundColor = 'rgba(54, 185, 204, 0.1)';
                        unit = 'μS/cm';
                        break;
                    case 'distance':
                        borderColor = '#f6c23e';
                        backgroundColor = 'rgba(246, 194, 62, 0.1)';
                        unit = 'm';
                        break;
                    case 'ORP':
                        borderColor = '#6f42c1';
                        backgroundColor = 'rgba(111, 66, 193, 0.1)';
                        unit = 'mV';
                        break;
                    default:
                        borderColor = '#858796';
                        backgroundColor = 'rgba(133, 135, 150, 0.1)';
                }
                
                // Create the chart with error handling
                try {
                    mainChart = new Chart(canvas.getContext('2d'), {
                        type: 'line',
                        data: {
                            labels: labels,
                            datasets: [
                                {
                                    label: `${selectedMetric} ${unit}`,
                                    data: values,
                                    borderColor: borderColor,
                                    backgroundColor: backgroundColor,
                                    tension: 0.4,
                                    borderWidth: 2,
                                    fill: true
                                }
                            ]
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
                                    beginAtZero: false,
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
                    console.error("Error creating single metric chart:", e);
                    container.innerHTML = `<div class="error-message">Error creating chart: ${e.message}</div>`;
                }
            })
            .catch(error => {
                console.error('Error fetching chart data:', error);
                container.innerHTML = `<div class="error-message">Error loading chart: ${error.message}</div>`;
            });
    }
}