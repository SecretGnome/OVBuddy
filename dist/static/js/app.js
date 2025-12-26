// OVBuddy Terminal Interface - JavaScript

// Global state
let selectedNetwork = null;
let selectedNetworkElement = null;

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
            document.getElementById('auto_update').checked = data.auto_update !== undefined ? data.auto_update : true;
            document.getElementById('ap_fallback_enabled').checked = data.ap_fallback_enabled !== undefined ? data.ap_fallback_enabled : true;
            document.getElementById('ap_ssid').value = data.ap_ssid || 'OVBuddy';
            document.getElementById('ap_password').value = data.ap_password || '';
            document.getElementById('display_ap_password').checked = data.display_ap_password || false;
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
        use_partial_refresh: document.getElementById('use_partial_refresh').checked,
        auto_update: document.getElementById('auto_update').checked,
        ap_fallback_enabled: document.getElementById('ap_fallback_enabled').checked,
        ap_ssid: document.getElementById('ap_ssid').value,
        ap_password: document.getElementById('ap_password').value,
        display_ap_password: document.getElementById('display_ap_password').checked
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
            // Show restart snackbar
            showRestartSnackbar();
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
                    
                    const main = document.createElement('div');
                    main.className = 'network-main';

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

                    main.appendChild(ssid);
                    main.appendChild(info);
                    networkItem.appendChild(main);
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
    selectedNetworkElement = element || null;
    
    // Update UI
    document.querySelectorAll('.network-item').forEach(item => {
        item.classList.remove('selected');
    });
    if (element) {
        element.classList.add('selected');
    }

    // Ensure only one inline auth row exists, and place it inside the selected item
    document.querySelectorAll('.network-auth').forEach(row => row.remove());
    if (element) {
        element.appendChild(buildInlineAuthRow(network));
        // Try to focus password immediately for encrypted networks
        const pw = element.querySelector('input[type="password"]');
        if (pw) {
            pw.focus();
        }
    }
}

function buildInlineAuthRow(network) {
    const auth = document.createElement('div');
    auth.className = 'network-auth';

    if (network.encrypted) {
        const password = document.createElement('input');
        password.type = 'password';
        password.placeholder = 'WiFi password';
        password.autocomplete = 'current-password';
        password.className = 'network-password';
        password.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                e.preventDefault();
                connectToNetwork();
            }
        });
        auth.appendChild(password);
    } else {
        const hint = document.createElement('div');
        hint.className = 'network-open-hint';
        hint.textContent = 'Open network';
        auth.appendChild(hint);
    }

    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'network-connect';
    btn.textContent = 'Connect';
    btn.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        connectToNetwork();
    });
    auth.appendChild(btn);

    return auth;
}

function connectToNetwork() {
    console.log('Connecting to network...');
    
    if (!selectedNetwork || !selectedNetworkElement) {
        console.log('No network selected');
        showMessage('Please select a network first', 'error');
        return;
    }

    const connectButton = selectedNetworkElement.querySelector('.network-connect');
    const passwordInput = selectedNetworkElement.querySelector('.network-password');
    const password = selectedNetwork.encrypted ? (passwordInput?.value || '') : '';
    
    if (selectedNetwork.encrypted && !password) {
        console.log('Password required but not provided');
        showMessage('Password required for encrypted network', 'error');
        return;
    }

    if (connectButton) {
        connectButton.disabled = true;
        connectButton.textContent = 'Connecting...';
    }
    
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
        if (connectButton) {
            connectButton.disabled = false;
            connectButton.textContent = 'Connect';
        }
        
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
        if (connectButton) {
            connectButton.disabled = false;
            connectButton.textContent = 'Connect';
        }
        showMessage('Error connecting to network', 'error');
    });
}

function forceApMode() {
    console.log('Forcing AP mode...');
    
    // Confirm action
    if (!confirm('Force Access Point mode?\n\nThis will:\n1. Clear all WiFi configurations\n2. Reboot the device\n3. Enter AP mode after reboot\n\nYou will lose connection and need to connect to the AP.\n\nContinue?')) {
        return;
    }
    
    const forceApButton = document.getElementById('forceApButton');
    forceApButton.disabled = true;
    forceApButton.textContent = 'Rebooting...';
    
    console.log('Sending force AP request...');
    
    fetch('/api/wifi/force-ap', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        }
    })
    .then(response => response.json())
    .then(data => {
        console.log('Force AP response:', data);
        
        if (data.success) {
            showMessage('Device is rebooting. Connect to "' + data.ap_ssid + '" in about 60 seconds.', 'success');
            
            // Show reboot info
            alert(
                'Device is Rebooting!\n\n' +
                'WiFi configuration has been cleared.\n' +
                'The device will reboot and enter Access Point mode.\n\n' +
                'Wait about 60 seconds, then:\n\n' +
                '1. Look for WiFi network: ' + data.ap_ssid + '\n' +
                '2. Connect to it\n' +
                '3. Open: http://' + data.ap_ip + '\n' +
                '4. Configure WiFi settings\n\n' +
                'This page will no longer be accessible until you reconnect.'
            );
            
            // Keep button disabled - page will be unreachable soon
            forceApButton.textContent = 'Device Rebooting...';
        } else {
            showMessage('Error: ' + (data.error || 'Failed to force AP mode'), 'error');
            forceApButton.disabled = false;
            forceApButton.textContent = 'Force AP Mode';
        }
    })
    .catch(error => {
        console.error('Error forcing AP mode:', error);
        // This might be expected if device reboots quickly
        showMessage('Device is rebooting. Connect to AP in about 60 seconds.', 'info');
        forceApButton.textContent = 'Device Rebooting...';
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
            // Hide restart snackbar if restarting ovbuddy service
            if (serviceName === 'ovbuddy' && action === 'restart') {
                hideRestartSnackbar();
            }
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

// Restart Snackbar Functions
function showRestartSnackbar() {
    const snackbar = document.getElementById('restartSnackbar');
    if (snackbar) {
        snackbar.style.display = 'flex';
    }
}

function hideRestartSnackbar() {
    const snackbar = document.getElementById('restartSnackbar');
    if (snackbar) {
        snackbar.style.display = 'none';
    }
}

function restartServiceFromSnackbar() {
    console.log('Restarting ovbuddy service from snackbar...');
    hideRestartSnackbar();
    controlService('ovbuddy', 'restart');
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

// Version Management
function loadVersionInfo() {
    console.log('Loading version information...');
    
    const versionText = document.getElementById('versionText');
    const versionInfo = document.getElementById('versionInfo');
    if (!versionText || !versionInfo) return;
    
    fetch('/api/version')
        .then(response => response.json())
        .then(data => {
            console.log('Version data loaded:', data);
            
            let versionHtml = '';
            const runningVersion = data.running_version || 'unknown';
            const fileVersion = data.file_version || 'unknown';
            const latestVersion = data.latest_version || 'unknown';
            const versionMismatch = data.version_mismatch || false;
            const updateInProgress = data.update_status?.update_in_progress || false;
            const needsRestart = data.needs_restart || false;
            const updateAvailable = data.update_available || false;
            
            // Main version display
            versionHtml = `<strong>Version:</strong> v${runningVersion}`;
            
            // Show file version if different
            if (versionMismatch && fileVersion !== 'unknown') {
                versionHtml += ` <span style="color: var(--warning-color);">(file: v${fileVersion})</span>`;
            }
            
            // Show latest version if available
            if (latestVersion !== 'unknown' && latestVersion !== runningVersion) {
                versionHtml += ` | <span style="color: var(--primary-color);">Latest: v${latestVersion}</span>`;
            }
            
            // Show update status
            if (updateInProgress) {
                versionHtml += ` | <span style="color: var(--warning-color);">🔄 Update in progress...</span>`;
            } else if (needsRestart) {
                versionHtml += ` | <span style="color: var(--warning-color);">⚠ Restart required</span>`;
                // Show restart snackbar if restart is needed
                showRestartSnackbar();
            } else if (updateAvailable) {
                versionHtml += ` | <span style="color: var(--primary-color);">📦 Update available</span>`;
            }
            
            versionText.innerHTML = versionHtml;
            
            // Add or update Force Update button
            let updateButton = document.getElementById('forceUpdateButton');
            if (updateAvailable && !updateInProgress && !needsRestart) {
                if (!updateButton) {
                    updateButton = document.createElement('button');
                    updateButton.id = 'forceUpdateButton';
                    updateButton.className = 'secondary';
                    updateButton.style.marginTop = '10px';
                    updateButton.style.width = '100%';
                    updateButton.textContent = 'Force Update';
                    updateButton.onclick = triggerUpdate;
                    versionInfo.appendChild(updateButton);
                }
                updateButton.disabled = false;
                updateButton.textContent = `Force Update to v${latestVersion}`;
            } else {
                if (updateButton) {
                    updateButton.remove();
                }
            }
        })
        .catch(error => {
            console.error('Error loading version:', error);
            versionText.textContent = 'Version: Unable to load';
        });
}

function triggerUpdate() {
    const updateButton = document.getElementById('forceUpdateButton');
    if (!updateButton) return;
    
    if (!confirm('Are you sure you want to update the system? The device will restart after the update completes.')) {
        return;
    }
    
    updateButton.disabled = true;
    updateButton.textContent = 'Updating...';
    // Hide restart snackbar since update will restart the service
    hideRestartSnackbar();
    
    fetch('/api/update', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({})
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            showMessage(data.message || 'Update triggered successfully! The system will update and restart shortly. [OK]', 'success');
            // Refresh version info to show update in progress
            setTimeout(() => {
                loadVersionInfo();
            }, 1000);
            // Keep checking version status
            const checkInterval = setInterval(() => {
                loadVersionInfo();
                fetch('/api/version')
                    .then(response => response.json())
                    .then(versionData => {
                        const updateInProgress = versionData.update_status?.update_in_progress || false;
                        if (!updateInProgress) {
                            clearInterval(checkInterval);
                            loadVersionInfo();
                        }
                    });
            }, 2000);
        } else {
            showMessage('Error: ' + (data.error || 'Failed to trigger update'), 'error');
            updateButton.disabled = false;
            updateButton.textContent = 'Force Update';
        }
    })
    .catch(error => {
        console.error('Error triggering update:', error);
        showMessage('Error triggering update', 'error');
        updateButton.disabled = false;
        updateButton.textContent = 'Force Update';
    });
}

// Shutdown Management
function shutdownDisplay() {
    const shutdownButton = document.getElementById('shutdownButton');
    const imageInput = document.getElementById('shutdownImage');
    
    if (!confirm('Are you sure you want to shutdown? This will stop the ovbuddy service and clear the display.')) {
        return;
    }
    
    shutdownButton.disabled = true;
    shutdownButton.textContent = 'Shutting down...';
    
    // Create form data for file upload
    const formData = new FormData();
    if (imageInput.files && imageInput.files[0]) {
        formData.append('image', imageInput.files[0]);
    }
    
    fetch('/api/shutdown', {
        method: 'POST',
        body: formData
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            showMessage(data.message || 'Shutdown successful! Display cleared. [OK]', 'success');
            // Refresh service status after a delay
            setTimeout(() => {
                refreshServicesStatus();
            }, 2000);
            // Clear file input
            if (imageInput) {
                imageInput.value = '';
            }
        } else {
            showMessage('Error: ' + (data.error || 'Failed to shutdown'), 'error');
            shutdownButton.disabled = false;
            shutdownButton.textContent = 'Shutdown & Clear Display';
        }
    })
    .catch(error => {
        console.error('Error shutting down:', error);
        showMessage('Error shutting down', 'error');
        shutdownButton.disabled = false;
        shutdownButton.textContent = 'Shutdown & Clear Display';
    });
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
    loadVersionInfo();
    
    // Refresh version info periodically (every 30 seconds)
    setInterval(loadVersionInfo, 30000);
    
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

