// OVBuddy Terminal Interface - JavaScript

// Global state
let selectedNetwork = null;
let selectedNetworkElement = null;
let MODULES = null;
let _CONFIG_INIT = false;
let _WEBAUTH_INIT = false;
let _SERVICES_INIT = false;
let _WIFI_INIT = false;

function getDefaultModules() {
    return {
        web_auth_basic: true,
        config_json: true,
        systemctl_status: true,
        iwconfig: true,
        shutdown: true
    };
}

function moduleEnabled(key) {
    const mods = MODULES || getDefaultModules();
    return mods[key] !== false;
}

async function loadModules() {
    try {
        const r = await fetch('/api/modules');
        const data = await r.json();
        MODULES = (data && data.modules) ? data.modules : getDefaultModules();
    } catch (e) {
        console.warn('Failed to load module settings, falling back to defaults:', e);
        MODULES = getDefaultModules();
    }
    return MODULES;
}

async function setModuleEnabled(key, enabled) {
    const payload = {};
    payload[key] = !!enabled;
    const r = await fetch('/api/modules', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ modules: payload })
    });
    const data = await r.json();
    if (!data || !data.success) {
        throw new Error(data?.error || 'Failed to save module setting');
    }
    MODULES = data.modules || MODULES || getDefaultModules();
    return MODULES;
}

function applyModuleVisibility() {
    const windows = document.querySelectorAll('.terminal-window[data-module]');
    windows.forEach(win => {
        const key = win.getAttribute('data-module');
        const enabled = moduleEnabled(key);
        if (!enabled) {
            win.classList.add('collapsed', 'module-disabled');
        } else {
            win.classList.remove('collapsed', 'module-disabled');
        }
    });

    // Show/hide DISABLED badges
    document.querySelectorAll('[data-module-badge]').forEach(badge => {
        const key = badge.getAttribute('data-module-badge');
        const enabled = moduleEnabled(key);
        badge.style.display = enabled ? 'none' : 'inline-block';
    });
}

function syncHeaderToggles() {
    document.querySelectorAll('input[data-module-toggle]').forEach((el) => {
        const key = el.getAttribute('data-module-toggle');
        el.checked = moduleEnabled(key);
    });
}

function initModulesFromToggles() {
    document.querySelectorAll('input[data-module-toggle]').forEach((el) => {
        el.addEventListener('change', async () => {
            const key = el.getAttribute('data-module-toggle');
            const target = !!el.checked;
            el.disabled = true;
            try {
                await setModuleEnabled(key, target);
                applyModuleVisibility();
                syncHeaderToggles();

                // When enabling web auth, do NOT reload immediately.
                // User should set credentials first, then reload explicitly.
                if (key === 'web_auth_basic' && target) {
                    // Ensure the panel is visible so they can set credentials
                    maybeInitEnabledModules();
                    loadWebAuthStatus();
                    showMessage('Web auth enabled. Set a username/password, then click "Update Web Login" and "Reload & Login".', 'info');
                    return;
                }

                // Bring newly-enabled modules online without requiring a full reload.
                maybeInitEnabledModules();
                showMessage('Module setting saved [OK]', 'success');
            } catch (e) {
                console.error('Error saving module toggle:', e);
                // Revert toggle UI
                el.checked = !target;
                showMessage('Error: ' + (e?.message || 'Failed to save module setting'), 'error');
            } finally {
                el.disabled = false;
            }
        });
    });
}

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
            // Orientation (new)
            const orientationSelect = document.getElementById('display_orientation');
            if (orientationSelect) {
                orientationSelect.value = data.display_orientation || (data.flip_display ? 'top' : 'bottom');
            }
            // Departure layout
            const departureLayoutSelect = document.getElementById('departure_layout');
            if (departureLayoutSelect) {
                departureLayoutSelect.value = data.departure_layout || '1row';
            }
            document.getElementById('destination_scroll').checked = data.destination_scroll || false;
            document.getElementById('lcd_refresh_rate').value = data.lcd_refresh_rate || 30;
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

// Web Authentication Management (Basic Auth)
function reloadForWebAuth() {
    window.location.reload();
}

function setWebAuthReloadButtonVisible(visible) {
    const btn = document.getElementById('webAuthReloadButton');
    if (!btn) return;
    btn.style.display = visible ? 'inline-block' : 'none';
}

function loadWebAuthStatus() {
    fetch('/api/web-auth')
        .then(r => r.json())
        .then(data => {
            const statusEl = document.getElementById('webAuthStatusText');
            const userEl = document.getElementById('webAuthUsername');
            if (statusEl) {
                const source = data.source ? data.source.toUpperCase() : 'UNKNOWN';
                const enabled = data.enabled ? 'ENABLED [OK]' : 'DISABLED [WARN]';
                const configured = (data.configured === undefined) ? !!data.exists : !!data.configured;
                const path = data.path ? ` | FILE: ${data.path}` : '';
                const cfgText = data.enabled ? (configured ? ' | CONFIGURED [OK]' : ' | NOT CONFIGURED [WARN]') : '';
                statusEl.textContent = `${enabled}${cfgText} | SOURCE: ${source}${path}`;
                // Only show Reload button after credentials are configured
                setWebAuthReloadButtonVisible(!!data.enabled && configured);
            }
            if (userEl) {
                userEl.value = data.username || '';
            }
        })
        .catch(err => {
            console.error('Error loading web auth status:', err);
            const statusEl = document.getElementById('webAuthStatusText');
            if (statusEl) statusEl.textContent = 'Error loading status [FAIL]';
            setWebAuthReloadButtonVisible(false);
        });
}

function saveWebAuth(event) {
    event.preventDefault();
    const username = (document.getElementById('webAuthUsername')?.value || '').trim();
    const pw = document.getElementById('webAuthPassword')?.value || '';
    const pw2 = document.getElementById('webAuthPasswordConfirm')?.value || '';

    if (!username) {
        showMessage('Web auth username is required', 'error');
        return;
    }
    if (!pw) {
        showMessage('Password is required (stored in SD card auth file)', 'error');
        return;
    }
    if (pw.length < 8) {
        showMessage('Password must be at least 8 characters', 'error');
        return;
    }
    if (pw !== pw2) {
        showMessage('Password confirmation does not match', 'error');
        return;
    }

    fetch('/api/web-auth', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password: pw })
    })
    .then(r => r.json())
    .then(data => {
        if (data.success) {
            showMessage(data.message || 'Web auth updated [OK]', 'success');
            // Clear password fields after update
            const p1 = document.getElementById('webAuthPassword');
            const p2 = document.getElementById('webAuthPasswordConfirm');
            if (p1) p1.value = '';
            if (p2) p2.value = '';
            loadWebAuthStatus();
            // Do not auto-reload; user explicitly clicks "Reload & Login"
        } else {
            showMessage('Error: ' + (data.error || 'Failed to update web auth'), 'error');
        }
    })
    .catch(err => {
        console.error('Error updating web auth:', err);
        showMessage('Error updating web auth', 'error');
    });
}

function rotateWebAuth() {
    if (!confirm('Rotate web login (generate a new random password)? You will need to re-login.')) return;

    const username = (document.getElementById('webAuthUsername')?.value || '').trim();

    fetch('/api/web-auth', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(username ? { reset: true, username } : { reset: true })
    })
    .then(r => r.json())
    .then(data => {
        if (data.success) {
            const u = data.username || username || 'admin';
            const pw = data.generated_password || '';
            if (pw) {
                showMessage(`Rotated web login. New credentials: ${u} / ${pw}`, 'success');
            } else {
                showMessage(data.message || 'Rotated web login [OK]', 'success');
            }
            loadWebAuthStatus();
        } else {
            showMessage('Error: ' + (data.error || 'Failed to rotate'), 'error');
        }
    })
    .catch(err => {
        console.error('Error rotating web auth:', err);
        showMessage('Error rotating web auth', 'error');
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
        display_orientation: (document.getElementById('display_orientation')?.value || 'bottom'),
        departure_layout: (document.getElementById('departure_layout')?.value || '1row'),
        destination_scroll: document.getElementById('destination_scroll').checked,
        lcd_refresh_rate: parseInt(document.getElementById('lcd_refresh_rate').value) || 30,
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
            showMessage('Configuration saved successfully! Reloading...', 'success');
            // Trigger config reload in main service
            return fetch('/api/reload-config', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                }
            });
        } else {
            showMessage('Error: ' + (data.error || 'Failed to save configuration'), 'error');
            return Promise.reject(new Error('Config save failed'));
        }
    })
    .then(response => {
        if (response) {
            return response.json();
        }
    })
    .then(data => {
        if (data && data.success) {
            showMessage('Configuration saved and reloaded! Changes are now active.', 'success');
        } else if (data) {
            // Reload might have failed, but config was saved
            showMessage('Configuration saved! Changes will be applied on next refresh.', 'success');
        }
    })
    .catch(error => {
        console.error('Error:', error);
        // Config might have been saved even if reload failed
        if (!error.message || !error.message.includes('Config save failed')) {
            showMessage('Configuration saved, but reload may have failed. Changes will be applied shortly.', 'success');
        } else {
            showMessage('Error saving configuration', 'error');
        }
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

function connectManually() {
    console.log('Manual WiFi connection initiated...');
    
    const ssidInput = document.getElementById('manualSsid');
    const passwordInput = document.getElementById('manualPassword');
    const connectButton = document.getElementById('manualConnectButton');
    
    const ssid = ssidInput.value.trim();
    const password = passwordInput.value;
    
    if (!ssid) {
        showMessage('Please enter a WiFi network name (SSID)', 'error');
        ssidInput.focus();
        return;
    }
    
    // Disable button and show loading state
    connectButton.disabled = true;
    connectButton.textContent = 'Connecting...';
    
    console.log('Attempting to connect to:', ssid);
    showMessage('Connecting to ' + ssid + '... This may take up to 15 seconds.', 'info');
    
    fetch('/api/wifi/connect', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            ssid: ssid,
            password: password || ''
        })
    })
    .then(response => {
        console.log('Response status:', response.status);
        return response.json();
    })
    .then(data => {
        console.log('Response data:', data);
        connectButton.disabled = false;
        connectButton.textContent = 'Connect to Network';
        
        if (data.success) {
            showMessage(data.message || 'Successfully connected to ' + ssid, 'success');
            // Clear the form
            ssidInput.value = '';
            passwordInput.value = '';
            // Refresh status after a longer delay to allow for AP mode exit and connection
            setTimeout(() => {
                refreshWifiStatus();
            }, 8000);
        } else {
            showMessage('Error: ' + (data.error || 'Failed to connect to ' + ssid), 'error');
        }
    })
    .catch(error => {
        console.error('Error connecting:', error);
        connectButton.disabled = false;
        connectButton.textContent = 'Connect to Network';
        showMessage('Error connecting to network', 'error');
    });
}

// Add Enter key support for manual WiFi connection
document.addEventListener('DOMContentLoaded', function() {
    const manualSsid = document.getElementById('manualSsid');
    const manualPassword = document.getElementById('manualPassword');
    
    if (manualSsid) {
        manualSsid.addEventListener('keydown', function(e) {
            if (e.key === 'Enter') {
                e.preventDefault();
                manualPassword.focus();
            }
        });
    }
    
    if (manualPassword) {
        manualPassword.addEventListener('keydown', function(e) {
            if (e.key === 'Enter') {
                e.preventDefault();
                connectManually();
            }
        });
    }
});

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
function updateSshBootToggleFromStatus(statusMap) {
    const cb = document.getElementById('sshEnableOnBoot');
    if (!cb) return;
    if (!moduleEnabled('systemctl_status')) {
        cb.disabled = true;
        return;
    }
    const ssh = statusMap ? statusMap['ssh'] : null;
    if (!ssh) {
        cb.disabled = true;
        cb.checked = false;
        return;
    }
    cb.disabled = false;
    cb.checked = !!ssh.enabled;
}

function onSshBootToggleChanged() {
    const cb = document.getElementById('sshEnableOnBoot');
    if (!cb) return;
    if (!moduleEnabled('systemctl_status')) {
        showMessage('systemctl status module is disabled', 'error');
        cb.checked = false;
        cb.disabled = true;
        return;
    }
    const action = cb.checked ? 'enable' : 'disable';
    // Use the same confirmation + refresh behavior as other service actions.
    controlService('ssh', action);
}

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
                const isEnabled = !!status.enabled;
                
                html += `
                    <div class="service-status">
                        <span class="status-indicator ${statusClass}"></span>
                        <div class="service-info">
                            <div class="service-name">${serviceName}</div>
                            <div class="service-details">
                                Status: ${statusText}
                                ${isEnabled ? ' | Enabled on boot' : ' | Disabled'}
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
                            ${isEnabled ?
                                `<button onclick="controlService('${serviceName}', 'disable')" class="secondary">Disable</button>` :
                                `<button onclick="controlService('${serviceName}', 'enable')" class="secondary">Enable</button>`
                            }
                        </div>
                    </div>
                `;
            }
            
            statusDiv.innerHTML = html;
            updateSshBootToggleFromStatus(data);
        })
        .catch(error => {
            console.error('Error loading service status:', error);
            statusDiv.innerHTML = '<p style="color: var(--error-color); text-align: center;">Error loading service status</p>';
            updateSshBootToggleFromStatus(null);
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
    if (!moduleEnabled('systemctl_status')) {
        showMessage('systemctl status module is disabled; cannot restart service from UI', 'error');
        return;
    }
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
            
            // Always provide a manual "Check for updates" button (forces a fresh GitHub check)
            let checkButton = document.getElementById('checkUpdatesButton');
            if (!checkButton) {
                checkButton = document.createElement('button');
                checkButton.id = 'checkUpdatesButton';
                checkButton.className = 'secondary';
                checkButton.style.marginTop = '10px';
                checkButton.style.width = '100%';
                checkButton.textContent = 'Check for updates';
                checkButton.onclick = checkUpdatesNow;
                versionInfo.appendChild(checkButton);
            }
            checkButton.disabled = false;
            checkButton.textContent = 'Check for updates';

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

function checkUpdatesNow() {
    const checkButton = document.getElementById('checkUpdatesButton');
    if (!checkButton) return;

    checkButton.disabled = true;
    checkButton.textContent = 'Checking...';

    fetch('/api/check-updates', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    })
    .then(response => response.json())
    .then(data => {
        // Refresh version info to reflect latest check result
        loadVersionInfo();

        if (data.update_check_error) {
            showMessage('Update check failed: ' + data.update_check_error, 'error');
        } else if (data.update_available) {
            showMessage('Update available: v' + (data.latest_version || '?'), 'success');
        } else {
            showMessage('No update available', 'success');
        }
    })
    .catch(error => {
        console.error('Error checking updates:', error);
        showMessage('Error checking updates', 'error');
    })
    .finally(() => {
        // Button label/state will be reset by loadVersionInfo(); just re-enable as fallback.
        checkButton.disabled = false;
        checkButton.textContent = 'Check for updates';
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
            // Refresh service status after a delay (if enabled)
            if (moduleEnabled('systemctl_status')) {
                setTimeout(() => {
                    refreshServicesStatus();
                }, 2000);
            }
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

function clearKnownNetworks() {
    const btn = document.getElementById('clearKnownNetworksButton');
    if (!confirm('Clear ALL known WiFi networks? This only clears saved credentials on OVBuddy; it does not change your router.')) {
        return;
    }
    if (btn) {
        btn.disabled = true;
        btn.textContent = 'Clearing...';
    }

    fetch('/api/wifi/known/clear', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    })
    .then(r => r.json())
    .then(data => {
        if (data.success) {
            showMessage(data.message || 'Known networks cleared. [OK]', 'success');
            refreshWifiStatus();
        } else {
            showMessage('Error: ' + (data.error || 'Failed to clear known networks'), 'error');
        }
    })
    .catch(err => {
        console.error('Error clearing known networks:', err);
        showMessage('Error clearing known networks', 'error');
    })
    .finally(() => {
        if (btn) {
            btn.disabled = false;
            btn.textContent = 'Clear Known Networks';
        }
    });
}

function rebootPi() {
    const btn = document.getElementById('rebootButton');
    if (!confirm('Reboot the Pi now? You will lose connection for ~1 minute.')) {
        return;
    }
    if (btn) {
        btn.disabled = true;
        btn.textContent = 'Rebooting...';
    }
    fetch('/api/reboot', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    })
    .then(r => r.json())
    .then(data => {
        if (data.success) {
            showMessage('Reboot triggered. Please wait ~60 seconds. [OK]', 'success');
        } else {
            showMessage('Error: ' + (data.error || 'Failed to reboot'), 'error');
            if (btn) {
                btn.disabled = false;
                btn.textContent = 'Reboot Pi';
            }
        }
    })
    .catch(err => {
        console.error('Error rebooting:', err);
        showMessage('Error rebooting (device may already be rebooting)', 'info');
    });
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', function() {
    console.log('OVBuddy Terminal Interface initialized');
    
    // Load saved theme
    loadTheme();

    // Load module settings first, then initialize enabled modules
    (async () => {
        await loadModules();
        applyModuleVisibility();
        syncHeaderToggles();
        initModulesFromToggles();

        maybeInitEnabledModules();

        // Always-on
        loadVersionInfo();
        setInterval(loadVersionInfo, 30000);
    })();
    
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

function maybeInitEnabledModules() {
    // config.json
    if (moduleEnabled('config_json') && !_CONFIG_INIT) {
        _CONFIG_INIT = true;
        loadConfiguration();
        const configForm = document.getElementById('configForm');
        if (configForm) {
            configForm.addEventListener('submit', saveConfiguration);
        }
    }

    // web auth
    if (moduleEnabled('web_auth_basic') && !_WEBAUTH_INIT) {
        _WEBAUTH_INIT = true;
        loadWebAuthStatus();
        const webAuthForm = document.getElementById('webAuthForm');
        if (webAuthForm) {
            webAuthForm.addEventListener('submit', saveWebAuth);
        }
    }

    // wifi
    if (moduleEnabled('iwconfig') && !_WIFI_INIT) {
        _WIFI_INIT = true;
        refreshWifiStatus();
    }

    // services
    if (moduleEnabled('systemctl_status') && !_SERVICES_INIT) {
        _SERVICES_INIT = true;
        refreshServicesStatus();
        const sshCb = document.getElementById('sshEnableOnBoot');
        if (sshCb) {
            sshCb.addEventListener('change', onSshBootToggleChanged);
        }
    }
}
