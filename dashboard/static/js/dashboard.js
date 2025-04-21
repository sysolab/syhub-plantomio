// Dashboard.js - Optimized JavaScript for the dashboard page
// Enhanced for better performance and reliable chart rendering

// Chart state management
let mainChart = null;  // Global reference to main chart
let isChartInitializing = false;  // Flag to prevent concurrent chart operations
let currentMetric = 'combined'; // Track the current metric globally

// Initialize metric selectors
document.addEventListener('DOMContentLoaded', function() {
    // Set combined as default - make sure the correct button is active
    document.querySelectorAll('.metric-btn').forEach(btn => {
        btn.classList.remove('active');
        if (btn.dataset.metric === 'combined') {
            btn.classList.add('active');
        }
    });
    
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
        // Ensure combined is the default metric
        currentMetric = 'combined';
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
            
            // Update current metric
            currentMetric = this.dataset.metric;
            
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
    
    // Use our tracked metric variable rather than reading from DOM
    // This ensures we always have a valid metric even if DOM elements aren't ready
    const selectedMetric = currentMetric || 'combined';
    
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
    console.log(`Handling individual chart for metric: ${metric} - Dynamic scale version`);
    
    if (!data.data[metric] || !Array.isArray(data.data[metric]) || data.data[metric].length === 0) {
        console.error(`No data available for ${metric}.`);
        throw new Error(`No data available for ${metric}`);
    }
    
    const chartData = data.data[metric];
    const labels = [];
    const values = [];
    
    // Process each data point
    chartData.forEach(point => {
        if (Array.isArray(point) && point.length === 2) {
            const [timestamp, value] = point;
            if (value !== null && !isNaN(value)) {
                const date = new Date(timestamp * 1000);
                labels.push(date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}));
                values.push(parseFloat(value));
            } else {
                labels.push('');
                values.push(null);
            }
        }
    });
    
    // Get chart colors and labels for the metric
    const chartConfig = getChartConfig(metric);
    
    // Dynamic scale calculation with 30% padding
    let yMin, yMax;
    
    // Filter out null values
    const validValues = values.filter(v => v !== null && !isNaN(v));
    if (validValues.length > 0) {
        const minValue = Math.min(...validValues);
        const maxValue = Math.max(...validValues);
        
        // Calculate padding (30% of the range)
        const range = maxValue - minValue;
        const padding = range * 1.3;
        
        // Apply padding to min and max
        yMin = minValue - padding;
        yMax = maxValue + padding;
        
        // Ensure min is never negative for metrics that can't be negative
        if (['EC', 'TDS', 'temperature', 'distance', 'ORP'].includes(metric) && yMin < 0) {
            yMin = 0;
        }
        
        // For sparse data or single point, ensure a reasonable range
        if (range === 0 || isNaN(range)) {
            yMin = Math.max(0, minValue * 1.7);
            yMax = maxValue * 1.3;
            
            // For zero or near-zero values, use reasonable defaults
            if (maxValue < 0.1) {
                if (metric === 'pH') {
                    yMin = 0;
                    yMax = 14;
                } else {
                    yMin = 0;
                    yMax = 1;
                }
            }
        }
    } else {
        // Fallback defaults if there are no valid values
        if (metric === 'pH') {
            yMin = 0;
            yMax = 14;
        } else if (metric === 'temperature') {
            yMin = 0;
            yMax = 100;
        } else if (metric === 'EC') {
            yMin = 0;
            yMax = 5.0;
        } else if (metric === 'TDS') {
            yMin = 0;
            yMax = 2000;
        } else if (metric === 'ORP') {
            yMin = 0;
            yMax = 1000;
        } else if (metric === 'distance') {
            yMin = 0;
            yMax = 10;
        } else {
            yMin = 0;
            yMax = 100;
        }
    }
    
    try {
        if (!canvas.getContext) {
            throw new Error('Canvas context not available');
        }
        
        // Calculate the number of steps and step size
        const numSteps = 10;
        const stepSize = (yMax - yMin) / numSteps;
        
        const ctx = canvas.getContext('2d');
        
        // Destroy any existing chart
        if (window.mainChart) {
            window.mainChart.destroy();
        }
        
        window.mainChart = new Chart(ctx, {
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
                animation: false, // Disable animation for faster rendering
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
                                    label += context.parsed.y.toFixed(1);
                                }
                                return label;
                            }
                        }
                    }
                },
                scales: {
                    y: {
                        min: yMin,
                        max: yMax,
                        ticks: {
                            callback: function(value) {
                                return parseFloat(value).toFixed(1);
                            },
                            color: chartConfig.color,
                            // Force specific ticks with 1 decimal place
                            stepSize: stepSize,
                            precision: 1
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
    } catch (e) {
        console.error(`Error creating ${metric} chart:`, e);
        throw new Error(`Error creating chart: ${e.message}`);
    }
}

// Function to handle combined metric charts 
function handleCombinedChart(data, canvas, deviceId) {
    console.log(`Handling combined chart - Dynamic scale version`);
    
    // Process data for combined chart
    const metricMaps = {
        temperature: new Map(),
        pH: new Map(),
        EC: new Map()
    };
    
    // Calculate dynamic ranges with 30% padding
    const metricValues = {
        temperature: [],
        pH: [],
        EC: []
    };
    
    // Collect all timestamps from all metrics
    const allTimestamps = new Set();
    
    // Process all metrics and gather their timestamps and values
    Object.entries(data.data).forEach(([metric, values]) => {
        if (!values || !values.length) return;
        
        values.forEach(point => {
            if (Array.isArray(point) && point.length === 2) {
                const [timestamp, value] = point;
                allTimestamps.add(timestamp);
                
                if (value !== null && value !== "NaN" && value !== "nan") {
                    const numValue = parseFloat(value);
                    metricMaps[metric].set(timestamp, numValue);
                    metricValues[metric].push(numValue);
                }
            }
        });
    });
    
    // Calculate dynamic ranges with 30% padding
    const ranges = {};
    Object.entries(metricValues).forEach(([metric, values]) => {
        if (values.length > 0) {
            const minValue = Math.min(...values);
            const maxValue = Math.max(...values);
            const range = maxValue - minValue;
            const padding = range * 1.3;
            
            // Set min and max with padding
            let min = minValue - padding;
            let max = maxValue + padding;
            
            // Ensure min is never negative for metrics that can't be negative
            if (['EC', 'temperature'].includes(metric) && min < 0) {
                min = 0;
            }
            
            // For sparse data or single point, ensure a reasonable range
            if (range === 0 || isNaN(range)) {
                min = Math.max(0, minValue * 1.7);
                max = maxValue * 1.3;
                
                // For zero or near-zero values, use reasonable defaults
                if (maxValue < 0.1) {
                    if (metric === 'pH') {
                        min = 0;
                        max = 14;
                    } else {
                        min = 0;
                        max = 1;
                    }
                }
            }
            
            ranges[metric] = { min, max };
        } else {
            // Fallback defaults if there are no values
            if (metric === 'pH') {
                ranges[metric] = { min: 0, max: 14 };
            } else if (metric === 'temperature') {
                ranges[metric] = { min: 0, max: 100 };
            } else if (metric === 'EC') {
                ranges[metric] = { min: 0, max: 5.0 };
            }
        }
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
        // Calculate step sizes for each metric
        const tempStepSize = (ranges.temperature.max - ranges.temperature.min) / 10;
        const phStepSize = (ranges.pH.max - ranges.pH.min) / 10;
        const ecStepSize = (ranges.EC.max - ranges.EC.min) / 10;
        
        // Clear canvas before drawing
        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        
        // Destroy any existing chart
        if (window.mainChart) {
            window.mainChart.destroy();
        }
        
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
                animation: false, // Disable animation for faster rendering
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
                                    label += context.parsed.y.toFixed(1);
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
                                return parseFloat(value).toFixed(1);
                            },
                            color: '#4e73df',
                            stepSize: tempStepSize,
                            precision: 1
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
                                return parseFloat(value).toFixed(1);
                            },
                            color: '#e74a3b',
                            stepSize: phStepSize,
                            precision: 1
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
                                return parseFloat(value).toFixed(1);
                            },
                            color: '#36b9cc',
                            stepSize: ecStepSize,
                            precision: 1
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

// Function to load the combined chart
function loadCombinedChart(timeMinutes, stepSize) {
    console.log(`Loading combined chart for ${timeMinutes} minutes with step size ${stepSize}`);
    
    // Update current metric
    currentMetric = 'combined';
    
    // Get current device
    const deviceId = document.getElementById('device-id')?.textContent || 'plt-404cca470da0';
    
    // Get chart container and canvas
    const canvas = document.getElementById('main-chart');
    if (!canvas) {
        console.error('Chart canvas not found');
        return;
    }
    
    // Show loading indicator
    canvas.style.opacity = '0.6';
    
    // Fetch data for combined chart
    fetch(`/api/trends?metrics=temperature,pH,EC&device=${deviceId}&minutes=${timeMinutes}&step=${stepSize}`)
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            // Remove loading indicator
            canvas.style.opacity = '1';
            
            if (!data.status || data.status !== 'success' || !data.data) {
                throw new Error('No data available');
            }
            
            // Process the combined chart
            handleCombinedChart(data, canvas, deviceId);
        })
        .catch(error => {
            console.error('Error loading combined chart:', error);
            canvas.style.opacity = '1';
            
            // Display error message
            const container = canvas.parentElement;
            if (container) {
                container.innerHTML = `<div class="error-message">Error loading chart: ${error.message}</div>`;
            }
        });
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