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
    
    // Initial chart load (after a short delay to ensure everything is ready)
    setTimeout(() => {
        updateMainChart();
    }, 300);
    
    // Debug data retrieval after a short delay
    setTimeout(() => {
        debugDataRetrieval();
    }, 2000);
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
            
            // Update chart with new metric - add a small delay to ensure the class is applied
            setTimeout(() => {
                updateMainChart();
            }, 50);
            
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
    const timeMinutes = parseInt(timeDropdown?.value || 60); // Default to 1 hour if not found
    const stepSize = timeDropdown?.options[timeDropdown.selectedIndex]?.dataset.step || '1m';
    
    console.log(`Loading chart: ${selectedMetric}, device: ${deviceId}, minutes: ${timeMinutes}, step: ${stepSize}`);
    
    // Get chart container and prepare canvas
    const container = document.querySelector('.trends-container');
    if (!container) {
        console.error('Chart container not found');
        return;
    }
    
    // Destroy any existing chart to prevent memory leaks
    if (window.mainChart) {
        window.mainChart.destroy();
        window.mainChart = null;
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
    
    // For both combined and individual metrics, use the trends API
    let metricsToFetch = selectedMetric === 'combined' ? 'temperature,pH,EC' : selectedMetric;
    
    fetch(`/api/trends?metrics=${metricsToFetch}&device=${deviceId}&minutes=${timeMinutes}&step=${stepSize}`)
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            // Remove loading message
            if (container.contains(loadingDiv)) {
                container.removeChild(loadingDiv);
            }
            
            if (!data.status || data.status !== 'success' || !data.data) {
                throw new Error('No data available');
            }
            
            if (selectedMetric === 'combined') {
                // Handle combined chart
                handleCombinedChart(data, canvas, deviceId);
            } else {
                // Handle individual metric chart
                handleSingleMetricChart(selectedMetric, data, canvas, deviceId);
            }
        })
        .catch(error => {
            console.error(`Error loading ${selectedMetric} chart:`, error);
            container.innerHTML = `<div class="error-message">Error loading chart: ${error.message}</div>`;
        });
}

// Function to handle individual metric charts
function handleSingleMetricChart(metric, data, canvas, deviceId) {
    console.log(`Handling individual chart for metric: ${metric}`);
    console.log('Data received:', data);
    
    if (!data.data[metric] || !Array.isArray(data.data[metric]) || data.data[metric].length === 0) {
        console.error(`No data available for ${metric}. Data structure:`, data);
        throw new Error(`No data available for ${metric}`);
    }
    
    const chartData = data.data[metric];
    console.log(`Chart data for ${metric}:`, chartData);
    const labels = [];
    const values = [];
    
    // Track min and max for dynamic axis scaling
    let minValue = Number.MAX_VALUE;
    let maxValue = Number.MIN_VALUE;
    
    // Process each data point
    chartData.forEach(point => {
        if (Array.isArray(point) && point.length === 2) {
            const [timestamp, value] = point;
            if (value !== null && !isNaN(value)) {
                const numValue = parseFloat(value);
                minValue = Math.min(minValue, numValue);
                maxValue = Math.max(maxValue, numValue);
                
                const date = new Date(timestamp * 1000);
                labels.push(date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}));
                values.push(numValue);
            } else {
                labels.push('');
                values.push(null);
            }
        }
    });
    
    console.log(`Processed ${values.length} data points with min: ${minValue}, max: ${maxValue}`);
    console.log('Labels:', labels);
    console.log('Values:', values);
    
    // Get chart colors and labels for the metric
    const chartConfig = getChartConfig(metric);
    
    // Set fixed scales based on metric
    let minY, maxY;
    if (metric === 'pH') {
        minY = 0;
        maxY = 14;
    } else if (metric === 'temperature') {
        minY = 0;
        maxY = 100;
    } else if (metric === 'EC') {
        minY = 0;
        maxY = 5.0;  // Updated based on actual data range
    } else {
        // Add 30% padding to min/max to determine axis range for other metrics
        const valuePadding = (maxValue - minValue) * 0.3;
        minY = minValue - valuePadding;
        maxY = maxValue + valuePadding;
        
        // Handle case where min and max are very close or equal
        if (minValue === maxValue || Math.abs(maxValue - minValue) < 0.1) {
            minY = minValue * 0.7;  // 30% below
            maxY = maxValue * 1.3;  // 30% above
        }
        
        // Ensure zero is included for metrics where it makes sense
        if (minY > 0 && ['temperature', 'distance', 'TDS', 'EC', 'ORP'].includes(metric)) {
            minY = 0;
        }
    }
    
    try {
        if (!canvas.getContext) {
            throw new Error('Canvas context not available');
        }
        
        const ctx = canvas.getContext('2d');
        mainChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: [
                    {
                        label: chartConfig.label,
                        data: values,
                        borderColor: chartConfig.color,
                        backgroundColor: chartConfig.bgColor,
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
                        align: 'end'
                    },
                    title: {
                        display: true,
                        text: `Device: ${deviceId}`,
                        position: 'top',
                        align: 'end'
                    },
                    tooltip: {
                        callbacks: {
                            label: function(context) {
                                let label = context.dataset.label || '';
                                if (label) {
                                    label += ': ';
                                }
                                if (context.parsed.y !== null) {
                                    label += context.parsed.y.toFixed(1);  // 1 decimal place in tooltip
                                }
                                return label;
                            }
                        }
                    }
                },
                scales: {
                    y: {
                        beginAtZero: minY <= 0,
                        min: minY,
                        max: maxY,
                        ticks: {
                            callback: function(value) {
                                return value.toFixed(1);  // 1 decimal place on y-axis
                            },
                            color: chartConfig.color
                        },
                        grid: {
                            color: 'rgba(0, 0, 0, 0.05)'
                        },
                        title: {
                            display: true,
                            text: chartConfig.label,
                            color: chartConfig.color
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
        
        // Store reference to chart to avoid memory leaks
        window.mainChart = mainChart;
    } catch (e) {
        console.error(`Error creating ${metric} chart:`, e);
        throw new Error(`Error creating chart: ${e.message}`);
    }
}

// Function to handle combined metric charts 
function handleCombinedChart(data, canvas, deviceId) {
    // Process data for combined chart
    const metricMaps = {
        temperature: new Map(),
        pH: new Map(),
        EC: new Map()
    };
    
    // Track min and max for each metric
    const ranges = {
        temperature: { min: 0, max: 100 },  // Fixed range for temperature
        pH: { min: 0, max: 14 },           // Fixed range for pH
        EC: { min: 0, max: 5.0 }          // Fixed range for EC - updated based on actual data
    };
    
    // Collect all timestamps from all metrics
    const allTimestamps = new Set();
    
    // Process all metrics and gather their timestamps
    Object.entries(data.data).forEach(([metric, values]) => {
        if (!values || !values.length) return;
        
        values.forEach(point => {
            if (Array.isArray(point) && point.length === 2) {
                const [timestamp, value] = point;
                allTimestamps.add(timestamp);
                
                if (value !== null && value !== "NaN" && value !== "nan") {
                    const numValue = parseFloat(value);
                    metricMaps[metric].set(timestamp, numValue);
                }
            }
        });
    });
    
    // Sort timestamps chronologically
    const sortedTimestamps = Array.from(allTimestamps).sort((a, b) => a - b);
    
    // Format timestamps for display
    const labels = sortedTimestamps.map(timestamp => {
        const date = new Date(timestamp * 1000);
        return date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
    });
    
    // Extract values for each metric based on sorted timestamps
    const temperatureData = sortedTimestamps.map(timestamp => metricMaps.temperature.get(timestamp) || null);
    const phData = sortedTimestamps.map(timestamp => metricMaps.pH.get(timestamp) || null);
    const ecData = sortedTimestamps.map(timestamp => metricMaps.EC.get(timestamp) || null);
    
    try {
        // Clear canvas before drawing
        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        
        window.mainChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: [
                    {
                        label: 'Temperature (°C)',
                        data: temperatureData,
                        borderColor: '#4e73df',
                        backgroundColor: 'rgba(78, 115, 223, 0.1)',
                        tension: 0.4,
                        borderWidth: 2,
                        fill: false,
                        yAxisID: 'y-temperature'
                    },
                    {
                        label: 'pH',
                        data: phData,
                        borderColor: '#e74a3b',
                        backgroundColor: 'rgba(231, 74, 59, 0.1)',
                        tension: 0.4,
                        borderWidth: 2,
                        fill: false,
                        yAxisID: 'y-ph'
                    },
                    {
                        label: 'EC (μS/cm)',
                        data: ecData,
                        borderColor: '#36b9cc',
                        backgroundColor: 'rgba(54, 185, 204, 0.1)',
                        tension: 0.4,
                        borderWidth: 2,
                        fill: false,
                        yAxisID: 'y-ec'
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'top',
                        align: 'end'
                    },
                    title: {
                        display: true,
                        text: `Device: ${deviceId}`,
                        position: 'top',
                        align: 'end'
                    },
                    tooltip: {
                        callbacks: {
                            label: function(context) {
                                let label = context.dataset.label || '';
                                if (label) {
                                    label += ': ';
                                }
                                if (context.parsed.y !== null) {
                                    label += context.parsed.y.toFixed(1);  // 1 decimal place in tooltip
                                }
                                return label;
                            }
                        }
                    }
                },
                scales: {
                    'y-temperature': {
                        type: 'linear',
                        display: true,
                        position: 'left',
                        title: {
                            display: true,
                            text: 'Temperature (°C)',
                            color: '#4e73df'
                        },
                        min: ranges.temperature.min,
                        max: ranges.temperature.max,
                        ticks: {
                            callback: function(value) {
                                return value.toFixed(1);  // 1 decimal place
                            },
                            color: '#4e73df'
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
                            text: 'pH',
                            color: '#e74a3b'
                        },
                        min: ranges.pH.min,
                        max: ranges.pH.max,
                        ticks: {
                            callback: function(value) {
                                return value.toFixed(1);  // 1 decimal place
                            },
                            color: '#e74a3b'
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
                            text: 'EC (μS/cm)',
                            color: '#36b9cc'
                        },
                        min: ranges.EC.min,
                        max: ranges.EC.max,
                        ticks: {
                            callback: function(value) {
                                return value.toFixed(1);  // 1 decimal place
                            },
                            color: '#36b9cc'
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
    } catch (e) {
        console.error("Error creating combined chart:", e);
        throw new Error(`Error creating chart: ${e.message}`);
    }
}

// Helper function to get chart config by metric
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
                label: 'pH',
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

// Add this function at the end of the file
function debugDataRetrieval() {
    // Get current device
    const deviceId = document.getElementById('device-id')?.textContent || 'plt-404cca470da0';
    const timeMinutes = 60; // 1 hour of data
    const metrics = ['temperature', 'pH', 'TDS', 'EC', 'distance', 'ORP'];
    
    console.log('====== DEBUG DATA RETRIEVAL ======');
    console.log(`Testing data retrieval for device: ${deviceId}`);
    
    metrics.forEach(metric => {
        console.log(`Testing metric: ${metric}`);
        fetch(`/api/trends?metrics=${metric}&device=${deviceId}&minutes=${timeMinutes}`)
            .then(response => response.json())
            .then(data => {
                console.log(`${metric} data:`, data);
                if (data.status === 'success' && data.data && data.data[metric]) {
                    console.log(`✅ ${metric}: Data found with ${data.data[metric].length} points`);
                } else {
                    console.log(`❌ ${metric}: No data found!`);
                }
            })
            .catch(error => {
                console.error(`Error testing ${metric}:`, error);
            });
    });
}