// OVBuddy Terminal Interface - JavaScript

// Global state
let selectedNetwork = null;

// Utility Functions
function showMessage(text, type = 'info') {
    const messageDiv = document.getElementById('message');
    messageDiv.textContent = text;
    messageDiv.className = 'message ' + type;
    messageDiv.style.display = 'block';
    
    setTimeout(() => {
        messageDiv.style.display = 'none';
    }, 5000);
}

function setLoading(elementId, isLoading) {
    const element = document.getElementById(elementId);
    if (element) {
        if (isLoading) {
            element.classList.add('loading');
        } else {
            element.classList.remove('loading');
        }
    }
}

// Configuration Management
function loadConfiguration() {
    console.log('Loading configuration...');
    
    fetch('/api/config')
        .then(response => response.json())
        .then(data => {
            console.log('Configuration loaded:', data);
            
            // Populate form fields
            document.getElementById('stations').value = Array.isArray(data.stations) 
                ? data.stations.join('\n') 
                : (data.stations || '');
            
            document.getElementById('lines').value = Array.isArray(data.lines) 
                ? data.lines.join(', ') 
                : (data.lines || '');
            
            document.getElementById('refresh_interval').value = data.refresh_interval || 60;
            document.getElementById('qr_code_display_duration').value = data.qr_code_display_duration || 10;
            
            document.getElementById('destination_prefixes_to_remove').value = Array.isArray(data.destination_prefixes_to_remove) 
                ? data.destination_prefixes_to_remove.join('\n') 
                : '';
            
            document.getElementById('destination_exceptions').value = Array.isArray(data.destination_exceptions) 
                ? data.destination_exceptions.join(', ') 
                : (data.destination_exceptions || '');
            
            document.getElementById('max_departures').value = data.max_departures || 10;
            document.getElementById('inverted').checked = data.inverted || false;
            document.getElementById('flip_display').checked = data.flip_display || false;
            document.getElementById('use_partial_refresh').checked = data.use_partial_refresh || false;
        })
        .catch(error => {
            console.error('Error loading config:', error);
            showMessage('Error loading configuration', 'error');
        });
}

function saveConfiguration(event) {
    event.preventDefault();
    console.log('Saving configuration...');
    
    // Parse form data
    const config = {
        stations: document.getElementById('stations').value
            .split('\n')
            .map(s => s.trim())
            .filter(s => s),
        lines: document.getElementById('lines').value
            .split(',')
            .map(s => s.trim())
            .filter(s => s),
        refresh_interval: parseInt(document.getElementById('refresh_interval').value),
        qr_code_display_duration: parseInt(document.getElementById('qr_code_display_duration').value),
        destination_prefixes_to_remove: document.getElementById('destination_prefixes_to_remove').value
            .split('\n')
            .filter(s => s.trim()),
        destination_exceptions: document.getElementById('destination_exceptions').value
            .split(',')
            .map(s => s.trim())
            .filter(s => s),
        max_departures: parseInt(document.getElementById('max_departures').value),
        inverted: document.getElementById('inverted').checked,
        flip_display: document.getElementById('flip_display').checked,
        use_partial_refresh: document.getElementById('use_partial_refresh').checked
    };
    
    console.log('Sending config:', config);
    
    // Send to server
    fetch('/api/config', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify(config)
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            showMessage('Configuration saved successfully! [OK]', 'success');
        } else {
            showMessage('Error: ' + (data.error || 'Failed to save configuration'), 'error');
        }
    })
    .catch(error => {
        console.error('Error:', error);
        showMessage('Error saving configuration', 'error');
    });
}

// WiFi Management
function refreshWifiStatus() {
    console.log('Refreshing WiFi status...');
    
    fetch('/api/wifi/status')
        .then(response => response.json())
        .then(data => {
            const statusDiv = document.getElementById('wifiStatus');
            const statusText = document.getElementById('wifiStatusText');
            const detailsText = document.getElementById('wifiDetails');
            
            if (data.connected) {
                statusDiv.className = 'wifi-status';
                statusText.textContent = 'Connected [OK]';
                let details = `SSID: ${data.ssid || 'Unknown'}`;
                if (data.ip) details += ` | IP: ${data.ip}`;
                if (data.signal) details += ` | Signal: ${data.signal}`;
                detailsText.textContent = details;
            } else {
                statusDiv.className = 'wifi-status disconnected';
                statusText.textContent = 'Not Connected [FAIL]';
                detailsText.textContent = data.error || 'No active WiFi connection';
            }
        })
        .catch(error => {
            console.error('Error loading WiFi status:', error);
            showMessage('Error loading WiFi status', 'error');
        });
}

function scanNetworks() {
    console.log('Scanning for networks...');
    
    const scanButton = document.getElementById('scanButton');
    const networkListContainer = document.getElementById('networkListContainer');
    const networkList = document.getElementById('networkList');
    
    scanButton.disabled = true;
    scanButton.textContent = 'Scanning...';
    networkList.innerHTML = '<div style="text-align: center; padding: 20px;">Scanning for networks...</div>';
    networkListContainer.style.display = 'block';
    
    fetch('/api/wifi/scan')
        .then(response => {
            console.log('Scan response status:', response.status);
            return response.json();
        })
        .then(data => {
            console.log('Scan data received:', data);
            scanButton.disabled = false;
            scanButton.textContent = 'Scan for Networks';
            
            if (data.error) {
                console.log('Scan error:', data.error);
                networkList.innerHTML = `<div style="color: var(--error-color); text-align: center; padding: 20px;">Error: ${data.error}</div>`;
                showMessage('Error scanning networks: ' + data.error, 'error');
                return;
            }
            
            if (Array.isArray(data) && data.length > 0) {
                console.log('Found', data.length, 'networks');
                networkList.innerHTML = '';
                data.forEach(network => {
                    console.log('Adding network:', network.ssid);
                    const networkItem = document.createElement('div');
                    networkItem.className = 'network-item';
                    networkItem.onclick = () => selectNetwork(network, networkItem);
                    
                    const ssid = document.createElement('div');
                    ssid.className = 'network-ssid';
                    ssid.textContent = '> ' + (network.ssid || 'Unknown');
                    
                    const info = document.createElement('div');
                    info.className = 'network-info';
                    let infoText = network.encrypted ? '[ENCRYPTED]' : '[OPEN]';
                    if (network.signal !== undefined) {
                        infoText += ` | Signal: ${network.signal}%`;
                    }
                    info.textContent = infoText;
                    
                    networkItem.appendChild(ssid);
                    networkItem.appendChild(info);
                    networkList.appendChild(networkItem);
                });
            } else {
                console.log('No networks found');
                networkList.innerHTML = '<div style="text-align: center; padding: 20px;">No networks found</div>';
            }
        })
        .catch(error => {
            console.error('Error scanning networks:', error);
            scanButton.disabled = false;
            scanButton.textContent = 'Scan for Networks';
            networkList.innerHTML = '<div style="color: var(--error-color); text-align: center; padding: 20px;">Error scanning networks</div>';
            showMessage('Error scanning networks', 'error');
        });
}

function selectNetwork(network, element) {
    console.log('Network selected:', network);
    selectedNetwork = network;
    
    // Update UI
    document.querySelectorAll('.network-item').forEach(item => {
        item.classList.remove('selected');
    });
    if (element) {
        element.classList.add('selected');
    }
    
    // Show password input if encrypted
    const passwordGroup = document.getElementById('passwordGroup');
    const passwordInput = document.getElementById('wifiPassword');
    if (network.encrypted) {
        console.log('Network is encrypted, showing password input');
        passwordGroup.style.display = 'block';
        passwordInput.required = true;
    } else {
        console.log('Network is open, hiding password input');
        passwordGroup.style.display = 'none';
        passwordInput.required = false;
        passwordInput.value = '';
    }
    
    // Enable connect button
    const connectButton = document.getElementById('connectButton');
    connectButton.disabled = false;
    console.log('Connect button enabled');
}

function connectToNetwork() {
    console.log('Connecting to network...');
    
    if (!selectedNetwork) {
        console.log('No network selected');
        showMessage('Please select a network first', 'error');
        return;
    }
    
    const passwordInput = document.getElementById('wifiPassword');
    const password = selectedNetwork.encrypted ? passwordInput.value : '';
    
    if (selectedNetwork.encrypted && !password) {
        console.log('Password required but not provided');
        showMessage('Password required for encrypted network', 'error');
        return;
    }
    
    const connectButton = document.getElementById('connectButton');
    connectButton.disabled = true;
    connectButton.textContent = 'Connecting...';
    
    console.log('Sending connect request...');
    
    fetch('/api/wifi/connect', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            ssid: selectedNetwork.ssid,
            password: password
        })
    })
    .then(response => {
        console.log('Response status:', response.status);
        return response.json();
    })
    .then(data => {
        console.log('Response data:', data);
        connectButton.disabled = false;
        connectButton.textContent = 'Connect';
        
        if (data.success) {
            showMessage(data.message || 'Connecting to network... [OK]', 'success');
            // Refresh status after a delay
            setTimeout(() => {
                refreshWifiStatus();
            }, 3000);
        } else {
            showMessage('Error: ' + (data.error || 'Failed to connect'), 'error');
        }
    })
    .catch(error => {
        console.error('Error connecting:', error);
        connectButton.disabled = false;
        connectButton.textContent = 'Connect';
        showMessage('Error connecting to network', 'error');
    });
}

// Service Management
function refreshServicesStatus() {
    console.log('Refreshing services status...');
    
    const statusDiv = document.getElementById('servicesStatus');
    statusDiv.innerHTML = '<p style="text-align: center;">Loading service status...</p>';
    
    fetch('/api/services/status')
        .then(response => response.json())
        .then(data => {
            let html = '';
            
            for (const [serviceName, status] of Object.entries(data)) {
                const isRunning = status.active;
                const statusClass = isRunning ? 'running' : 'stopped';
                const statusText = status.status || 'unknown';
                
                html += `
                    <div class="service-status">
                        <span class="status-indicator ${statusClass}"></span>
                        <div class="service-info">
                            <div class="service-name">${serviceName}</div>
                            <div class="service-details">
                                Status: ${statusText}
                                ${status.enabled ? ' | Enabled on boot' : ' | Disabled'}
                                ${status.uptime ? ' | Since: ' + status.uptime : ''}
                                ${status.cpu ? ' | CPU: ' + status.cpu : ''}
                                ${status.memory ? ' | Memory: ' + status.memory : ''}
                            </div>
                        </div>
                        <div class="service-actions">
                            ${isRunning ? 
                                `<button onclick="controlService('${serviceName}', 'restart')" class="warning">Restart</button>
                                 <button onclick="controlService('${serviceName}', 'stop')" class="danger">Stop</button>` :
                                `<button onclick="controlService('${serviceName}', 'start')">Start</button>`
                            }
                        </div>
                    </div>
                `;
            }
            
            statusDiv.innerHTML = html;
        })
        .catch(error => {
            console.error('Error loading service status:', error);
            statusDiv.innerHTML = '<p style="color: var(--error-color); text-align: center;">Error loading service status</p>';
        });
}

function controlService(serviceName, action) {
    if (!confirm(`Are you sure you want to ${action} ${serviceName}?`)) {
        return;
    }
    
    console.log(`Controlling service: ${serviceName} - ${action}`);
    
    const statusDiv = document.getElementById('servicesStatus');
    const originalHtml = statusDiv.innerHTML;
    statusDiv.innerHTML = `<p style="text-align: center;">Executing ${action} on ${serviceName}...</p>`;
    
    fetch(`/api/services/${serviceName}/${action}`, {
        method: 'POST'
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            showMessage(data.message || `Service ${action}ed successfully [OK]`, 'success');
            // Refresh status after a short delay
            setTimeout(() => {
                refreshServicesStatus();
            }, 1000);
        } else {
            showMessage('Error: ' + (data.error || `Failed to ${action} service`), 'error');
            statusDiv.innerHTML = originalHtml;
        }
    })
    .catch(error => {
        console.error('Error controlling service:', error);
        showMessage(`Error controlling service: ${error}`, 'error');
        statusDiv.innerHTML = originalHtml;
    });
}

// Theme Management
function toggleTheme() {
    const currentTheme = localStorage.getItem('ovbuddy-theme') || 'terminal';
    const newTheme = currentTheme === 'terminal' ? 'bright' : 'terminal';
    
    setTheme(newTheme);
}

function setTheme(theme) {
    const stylesheet = document.getElementById('themeStylesheet');
    const themeIcon = document.getElementById('themeIcon');
    const themeText = document.getElementById('themeText');
    
    if (theme === 'bright') {
        stylesheet.href = '/static/css/bright.css';
        themeIcon.textContent = '🌙';
        themeText.textContent = 'Dark Theme';
    } else {
        stylesheet.href = '/static/css/terminal.css';
        themeIcon.textContent = '☀️';
        themeText.textContent = 'Bright Theme';
    }
    
    localStorage.setItem('ovbuddy-theme', theme);
    console.log('Theme switched to:', theme);
}

function loadTheme() {
    const savedTheme = localStorage.getItem('ovbuddy-theme') || 'terminal';
    setTheme(savedTheme);
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', function() {
    console.log('OVBuddy Terminal Interface initialized');
    
    // Load saved theme
    loadTheme();
    
    // Load initial data
    loadConfiguration();
    refreshWifiStatus();
    refreshServicesStatus();
    
    // Setup form handler
    const configForm = document.getElementById('configForm');
    if (configForm) {
        configForm.addEventListener('submit', saveConfiguration);
    }
    
    // Add terminal typing effect to title (only for terminal theme)
    const savedTheme = localStorage.getItem('ovbuddy-theme') || 'terminal';
    if (savedTheme === 'terminal') {
        const title = document.querySelector('.terminal-title');
        if (title) {
            const text = title.textContent;
            title.textContent = '';
            let i = 0;
            const typeWriter = () => {
                if (i < text.length) {
                    title.textContent += text.charAt(i);
                    i++;
                    setTimeout(typeWriter, 100);
                }
            };
            typeWriter();
        }
    }
});

