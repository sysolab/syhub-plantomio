// Dashboard.js - Optimized JavaScript for the dashboard page
// Enhanced for better performance and reliable chart rendering

// Chart state management
let mainChart = null;  // Global reference to main chart
let isChartInitializing = false;  // Flag to prevent concurrent chart operations

// Initialize metric selectors
document.addEventListener('DOMContentLoaded', function() {
    // Set up metric selector buttons
    setupMetricButtons();
    
    // Set up time range buttons
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

// Setup time range buttons
function setupTimeButtons() {
    document.querySelectorAll('.time-btn').forEach(button => {
        button.addEventListener('click', function() {
            // Set interaction active
            window.isChartInteractionActive = true;
            
            // Remove active class from all buttons
            document.querySelectorAll('.time-btn').forEach(btn => {
                btn.classList.remove('active');
            });
            
            // Add active class to clicked button
            this.classList.add('active');
            
            // Update chart with new time range
            updateMainChart();
            
            // Reset interaction after a short delay
            setTimeout(() => {
                window.isChartInteractionActive = false;
            }, 5000);
        });
    });
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
    // Ensure we have a valid device before trying to fetch data
    if (!window.currentDevice) {
        console.log("No device selected, skipping chart update");
        return;
    }
    
    // If chart is being created, don't try to update
    if (isChartInitializing) {
        console.log("Chart is being created, skipping update");
        return;
    }
    
    // Reset chart and canvas first
    resetChart();
    
    // Wait a small amount of time for the canvas to be available
    setTimeout(() => {
        const chartCanvas = document.getElementById('main-chart');
        if (!chartCanvas) {
            console.error("Chart canvas not found");
            return;
        }
        
        const ctx = chartCanvas.getContext('2d');
        const timeMinutes = parseInt(document.querySelector('.time-btn.active')?.dataset.minutes || 1440);
        const selectedMetric = document.querySelector('.metric-btn.active')?.dataset.metric || 'combined';
        
        // Show loading indicator
        chartCanvas.style.opacity = '0.6';
        
        // Handle "combined" special case
        if (selectedMetric === 'combined') {
            loadCombinedChart(timeMinutes);
            return;
        }
        
        // Use the simpler method from trends.html - load single metric with full 24h history
        fetch(`/api/query?metric=${selectedMetric}&device=${window.currentDevice}&minutes=${timeMinutes}`)
            .then(response => {
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                return response.json();
            })
            .then(data => {
                // Remove loading indicator
                chartCanvas.style.opacity = '1';
                
                if (!data || !data.status || data.status !== 'success') {
                    throw new Error('Invalid API response format');
                }
                
                const timestamps = [];
                const values = [];
                
                // Simplified data processing using directly returned format
                if (data.data && data.data.result && data.data.result.length > 0) {
                    const result = data.data.result[0];
                    const seen = new Set(); // To deduplicate timestamps
                    
                    if (result.values && Array.isArray(result.values)) {
                        result.values.forEach(point => {
                            try {
                                if (Array.isArray(point) && point.length === 2) {
                                    const [timestamp, value] = point;
                                    
                                    // Skip already seen timestamps
                                    if (seen.has(timestamp)) return;
                                    seen.add(timestamp);
                                    
                                    // Format time
                                    const date = new Date(timestamp * 1000);
                                    const timeStr = date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
                                    timestamps.push(timeStr);
                                    
                                    // Handle null or NaN values
                                    if (value === null || value === 'NaN' || value === 'nan') {
                                        values.push(null);
                                    } else {
                                        values.push(parseFloat(value));
                                    }
                                }
                            } catch (e) {
                                console.error("Error processing data point:", e);
                            }
                        });
                    }
                }
                
                // Get chart color based on metric
                let borderColor, backgroundColor, unit;
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
                        unit = '';
                }
                
                                    // Create the chart with error handling
                try {
                    if (!timestamps.length) {
                        // Draw empty chart with message if no data
                        mainChart = new Chart(ctx, {
                            type: 'line',
                            data: {
                                labels: ['No data'],
                                datasets: [{
                                    label: `${selectedMetric} ${unit}`,
                                    data: [null],
                                    borderColor: borderColor,
                                    backgroundColor: backgroundColor
                                }]
                            },
                            options: {
                                responsive: true,
                                maintainAspectRatio: false,
                                plugins: {
                                    title: {
                                        display: true,
                                        text: 'No data available for selected time range'
                                    }
                                }
                            }
                        });
                    } else {
                        // Create chart with data
                        mainChart = new Chart(ctx, {
                            type: 'line',
                            data: {
                                labels: timestamps,
                                datasets: [
                                    {
                                        label: `${selectedMetric} ${unit}`,
                                        data: values,
                                        borderColor: borderColor,
                                        backgroundColor: backgroundColor,
                                        tension: 0.4,
                                        borderWidth: 2,
                                        fill: true,
                                        spanGaps: true // Connect lines over null values
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
                                        text: `Device: ${window.currentDevice}`
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
                                        beginAtZero: selectedMetric === 'pH' || selectedMetric === 'distance',
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
                    }
                    
                    // Reset the creation flag
                    isChartInitializing = false;
                } catch (e) {
                    console.error("Error creating chart:", e);
                    chartCanvas.style.opacity = '1';
                    isChartInitializing = false;
                }
            })
            .catch(error => {
                console.error('Error fetching chart data:', error);
                // Remove loading indicator
                chartCanvas.style.opacity = '1';
                isChartInitializing = false;
                
                // Show error message in chart
                try {
                    mainChart = new Chart(ctx, {
                        type: 'line',
                        data: {
                            labels: ['Error'],
                            datasets: [{
                                label: selectedMetric,
                                data: [null],
                                borderColor: '#e74a3b',
                                backgroundColor: 'rgba(231, 74, 59, 0.1)'
                            }]
                        },
                        options: {
                            responsive: true,
                            maintainAspectRatio: false,
                            plugins: {
                                title: {
                                    display: true,
                                    text: 'Error loading data: ' + (error.message || 'Unknown error')
                                }
                            }
                        }
                    });
                } catch (chartError) {
                    console.error("Error creating error chart:", chartError);
                }
            });
    }, 100); // Wait 100ms for DOM to fully update
}