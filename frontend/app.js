// API Client Config
const API_BASE = "";

// Global App State
let appState = {
    sysInfo: null,
    scannedPlugins: [],
    selectedPlugin: null,
    activeResources: [],
    activeRegistryKeys: [],
    portableProfiles: []
};

// Log Message Helper
function log(message, type = "info") {
    const consoleEl = document.getElementById("logs-console");
    if (!consoleEl) return;

    const line = document.createElement("div");
    line.className = `log-line ${type}`;
    const timestamp = new Date().toLocaleTimeString();
    line.textContent = `[${timestamp}] ${message}`;
    consoleEl.appendChild(line);
    consoleEl.scrollTop = consoleEl.scrollHeight;
}

// Fetch helper with error handling
async function apiCall(endpoint, method = "GET", body = null) {
    const url = `${API_BASE}${endpoint}`;
    const options = {
        method,
        headers: { "Content-Type": "application/json" }
    };
    if (body) {
        options.body = JSON.stringify(body);
    }

    try {
        log(`API Request: ${method} ${endpoint}`, "info");
        const response = await fetch(url, options);
        if (!response.ok) {
            const errData = await response.json().catch(() => ({}));
            throw new Error(errData.error || `Server responded with status ${response.status}`);
        }
        const data = await response.json();
        return data;
    } catch (error) {
        log(`API Error: ${error.message}`, "error");
        alert(`Error: ${error.message}`);
        throw error;
    }
}

// Tab Switching
function switchTab(tabId) {
    document.querySelectorAll(".nav-item").forEach(btn => {
        if (btn.getAttribute("data-tab") === tabId) {
            btn.classList.add("active");
        } else {
            btn.classList.remove("active");
        }
    });

    document.querySelectorAll(".tab-content").forEach(content => {
        if (content.id === tabId) {
            content.classList.add("active");
        } else {
            content.classList.remove("active");
        }
    });
    log(`Switched to tab: ${tabId}`, "system");
}

// Initialize Application
window.addEventListener("DOMContentLoaded", async () => {
    // Setup Navigation event listeners
    document.querySelectorAll(".nav-item").forEach(btn => {
        btn.addEventListener("click", () => {
            const tabId = btn.getAttribute("data-tab");
            switchTab(tabId);
        });
    });

    // Clear logs listener
    document.getElementById("btn-clear-logs").addEventListener("click", () => {
        document.getElementById("logs-console").innerHTML = "";
        log("Activity logs cleared.", "system");
    });

    // Scan health action
    document.getElementById("btn-scan-health").addEventListener("click", runGlobalHealthCheck);
    document.getElementById("btn-quick-health").addEventListener("click", () => {
        switchTab("health");
        runGlobalHealthCheck();
    });

    // Rescan local plugins button
    document.getElementById("btn-rescan-plugins").addEventListener("click", scanLocalPlugins);

    // Add manual paths buttons
    document.getElementById("btn-add-manual-resource").addEventListener("click", addManualResourcePath);
    document.getElementById("btn-add-manual-reg").addEventListener("click", addManualRegKey);

    // Execute Pack button
    document.getElementById("btn-execute-pack").addEventListener("click", executePackagePlugin);

    // Single Deployer
    document.getElementById("btn-load-manifest").addEventListener("click", loadRestoreManifest);
    document.getElementById("btn-execute-deploy").addEventListener("click", executeDeploySingle);

    // Bulk Library Deployer
    document.getElementById("btn-scan-library").addEventListener("click", scanLibraryDirectory);

    // Load initial system stats
    await loadSystemStats();
});

// Load System Status from API
async function loadSystemStats() {
    try {
        const stats = await apiCall("/api/status");
        appState.sysInfo = stats;

        document.getElementById("sys-os").textContent = stats.os.toUpperCase();
        document.getElementById("sys-disk").textContent = `${stats.free_space_gb} GB Free`;
        document.getElementById("stat-prefixes").textContent = stats.wine_prefixes.length;

        // Render wine prefixes on Dashboard
        const listEl = document.getElementById("prefix-list");
        listEl.innerHTML = "";
        if (stats.wine_prefixes.length === 0) {
            listEl.innerHTML = `<li><i class="fa-solid fa-triangle-exclamation text-warning"></i> No Wine prefixes automatically found.</li>`;
        } else {
            stats.wine_prefixes.forEach(p => {
                const li = document.createElement("li");
                li.innerHTML = `<i class="fa-brands fa-windows"></i> <span>${p}</span>`;
                listEl.appendChild(li);
            });
        }
        log("System stats loaded successfully.", "success");
    } catch (err) {
        document.getElementById("backend-status").textContent = "Connection Failed";
        document.getElementById("backend-status").parentElement.querySelector(".status-dot").className = "status-dot offline";
    }
}

// Scan Local Plugins
async function scanLocalPlugins() {
    log("Scanning local plugin directories (Native & Wine)...", "info");
    const bodyEl = document.getElementById("scanned-plugins-body");
    bodyEl.innerHTML = `<tr><td colspan="5" class="placeholder-row"><i class="fa-solid fa-circle-notch fa-spin"></i><p>Scanning paths. This may take a moment...</p></td></tr>`;

    try {
        const data = await apiCall("/api/plugins");
        appState.scannedPlugins = [...data.native, ...data.wine];
        document.getElementById("stat-total-plugins").textContent = data.total;

        renderScannedPlugins();
        log(`Scanned ${data.total} plugins total.`, "success");
    } catch (err) {
        bodyEl.innerHTML = `<tr><td colspan="5" class="placeholder-row"><i class="fa-solid fa-triangle-exclamation"></i><p>Scanning failed. Check logs for details.</p></td></tr>`;
    }
}

// Render plugins in packaging table
function renderScannedPlugins() {
    const bodyEl = document.getElementById("scanned-plugins-body");
    bodyEl.innerHTML = "";

    const searchVal = document.getElementById("plugin-search").value.toLowerCase();
    const formatFilter = document.getElementById("format-filter").value;

    const filtered = appState.scannedPlugins.filter(p => {
        const matchesSearch = p.name.toLowerCase().includes(searchVal);
        const matchesFormat = formatFilter === "all" || p.format === formatFilter;
        return matchesSearch && matchesFormat;
    });

    if (filtered.length === 0) {
        bodyEl.innerHTML = `<tr><td colspan="5" class="placeholder-row"><i class="fa-solid fa-face-frown"></i><p>No plugins matching your filter criteria.</p></td></tr>`;
        return;
    }

    filtered.forEach(p => {
        const tr = document.createElement("tr");
        
        const pathTruncated = p.path.length > 50 ? "..." + p.path.slice(-47) : p.path;
        const sizeMb = (p.size / (1024 * 1024)).toFixed(1);
        const envBadge = p.type === "wine" ? `<span class="env-tag"><i class="fa-brands fa-windows"></i> Wine</span>` : `<span class="env-tag"><i class="fa-brands fa-linux"></i> Native</span>`;
        
        tr.innerHTML = `
            <td class="plugin-name-cell">${p.name}</td>
            <td><span class="plugin-badge" format="${p.format}">${p.format}</span></td>
            <td>${envBadge}</td>
            <td class="plugin-path-cell" title="${p.path}">${pathTruncated} (${sizeMb} MB)</td>
            <td>
                <button class="btn btn-secondary btn-sm" onclick="selectPluginForPackaging('${p.path}')">
                    Configure <i class="fa-solid fa-gear"></i>
                </button>
            </td>
        `;
        bodyEl.appendChild(tr);
    });

    // Add search and filter event listeners once
    if (!window.tableListenersAttached) {
        document.getElementById("plugin-search").addEventListener("input", renderScannedPlugins);
        document.getElementById("format-filter").addEventListener("change", renderScannedPlugins);
        window.tableListenersAttached = true;
    }
}

// Step Navigation in Wizard
function wizardGoTo(stepNum) {
    document.querySelectorAll(".step").forEach(s => {
        const num = parseInt(s.id.split("-")[2]);
        if (num === stepNum) {
            s.classList.add("active");
        } else if (num > stepNum) {
            s.classList.remove("active");
        }
    });

    document.querySelectorAll(".wizard-step-content").forEach(c => {
        const num = parseInt(c.id.split("-")[2]);
        if (num === stepNum) {
            c.classList.add("active");
        } else {
            c.classList.remove("active");
        }
    });
}

// Select a plugin to configure it
async function selectPluginForPackaging(path) {
    const plugin = appState.scannedPlugins.find(p => p.path === path);
    if (!plugin) return;

    appState.selectedPlugin = plugin;
    appState.activeResources = [];
    appState.activeRegistryKeys = [];

    log(`Configuring plugin for portability packaging: ${plugin.name}`, "info");

    // UI Updates
    document.getElementById("selected-plugin-format").textContent = plugin.format;
    document.getElementById("selected-plugin-format").setAttribute("format", plugin.format);
    document.getElementById("selected-plugin-name").textContent = plugin.name;
    document.getElementById("selected-plugin-path").textContent = plugin.path;

    // Show or hide Wine Registry options
    const regGroup = document.getElementById("wine-registry-group");
    if (plugin.type === "wine") {
        regGroup.style.display = "block";
        // Pre-fill a typical registry key matching the plugin name
        const typicalKey = `HKEY_CURRENT_USER\\Software\\${plugin.name}`;
        appState.activeRegistryKeys = [typicalKey];
    } else {
        regGroup.style.display = "none";
    }

    // Load resource suggestions
    const suggestionsEl = document.getElementById("resource-suggestions");
    suggestionsEl.innerHTML = `<div class="loading"><i class="fa-solid fa-spinner fa-spin"></i> Finding configurations and data directories...</div>`;

    wizardGoTo(2);

    try {
        const res = await apiCall("/api/resources", "POST", {
            name: plugin.name,
            type: plugin.type,
            prefix: plugin.prefix
        });

        renderResourceSuggestions(res.suggestions);
        renderRegistryKeys();
    } catch (err) {
        suggestionsEl.innerHTML = `<div class="text-error">Failed to search resource configurations.</div>`;
    }
}

// Render suggestions list
function renderResourceSuggestions(suggestions) {
    const listEl = document.getElementById("resource-suggestions");
    listEl.innerHTML = "";

    if (!suggestions || suggestions.length === 0) {
        listEl.innerHTML = `<p class="form-help text-warning"><i class="fa-solid fa-triangle-exclamation"></i> No associated configuration folders automatically found. Add them manually below.</p>`;
        return;
    }

    suggestions.forEach((s, idx) => {
        // Automatically check the item if it looks like a good match
        const isChecked = true;
        if (isChecked) {
            appState.activeResources.push(s.path);
        }

        const div = document.createElement("div");
        div.className = "suggestion-item";
        div.innerHTML = `
            <input type="checkbox" class="suggestion-checkbox" id="res-sugg-${idx}" ${isChecked ? "checked" : ""} onchange="toggleResource('${s.path}', this.checked)">
            <div class="suggestion-details">
                <span class="suggestion-path">${s.path}</span>
                <span class="suggestion-desc">${s.description}</span>
            </div>
        `;
        listEl.appendChild(div);
    });
}

function toggleResource(path, isChecked) {
    if (isChecked) {
        if (!appState.activeResources.includes(path)) {
            appState.activeResources.push(path);
        }
    } else {
        appState.activeResources = appState.activeResources.filter(p => p !== path);
    }
}

function addManualResourcePath() {
    const input = document.getElementById("manual-resource-path");
    const path = input.value.trim();
    if (!path) return;

    if (appState.activeResources.includes(path)) {
        alert("Path already added!");
        return;
    }

    appState.activeResources.push(path);
    input.value = "";
    
    // Add item visually to suggestions list
    const listEl = document.getElementById("resource-suggestions");
    
    // Clean placeholders
    if (listEl.querySelector("p")) {
        listEl.innerHTML = "";
    }

    const div = document.createElement("div");
    div.className = "suggestion-item";
    div.innerHTML = `
        <input type="checkbox" class="suggestion-checkbox" checked onchange="toggleResource('${path}', this.checked)">
        <div class="suggestion-details">
            <span class="suggestion-path">${path}</span>
            <span class="suggestion-desc">Manually configured path</span>
        </div>
    `;
    listEl.appendChild(div);
    log(`Manually added resource path: ${path}`, "success");
}

// Registry UI management
function renderRegistryKeys() {
    const listEl = document.getElementById("registry-keys-list");
    listEl.innerHTML = "";

    appState.activeRegistryKeys.forEach((key, idx) => {
        const div = document.createElement("div");
        div.className = "registry-item";
        div.innerHTML = `
            <span class="registry-key-name">${key}</span>
            <button class="btn-remove-item" onclick="removeRegistryKey(${idx})"><i class="fa-solid fa-xmark"></i></button>
        `;
        listEl.appendChild(div);
    });
}

function addManualRegKey() {
    const input = document.getElementById("manual-reg-key");
    const key = input.value.trim();
    if (!key) return;

    if (appState.activeRegistryKeys.includes(key)) {
        alert("Key already added!");
        return;
    }

    appState.activeRegistryKeys.push(key);
    input.value = "";
    renderRegistryKeys();
    log(`Added registry key: ${key}`, "info");
}

function removeRegistryKey(idx) {
    appState.activeRegistryKeys.splice(idx, 1);
    renderRegistryKeys();
}

// Execute Relocation and Packaging
async function executePackagePlugin() {
    const targetDirInput = document.getElementById("portable-target-dir");
    const targetDir = targetDirInput.value.trim();
    const strategy = document.getElementById("linking-strategy").value;

    if (!targetDir) {
        alert("Please set a target directory for the portable package!");
        return;
    }

    const plugin = appState.selectedPlugin;
    if (!plugin) return;

    log(`Starting relocation process for ${plugin.name}...`, "system");
    switchTab("logs");

    try {
        const payload = {
            name: plugin.name,
            format: plugin.format,
            type: plugin.type,
            path: plugin.path,
            resources: appState.activeResources,
            target_dir: targetDir,
            strategy: strategy,
            registry_keys: appState.activeRegistryKeys,
            prefix: plugin.prefix
        };

        const res = await apiCall("/api/profile/create", "POST", payload);
        log(`Successfully relocated and packaged: ${plugin.name}`, "success");
        log(`Manifest file saved in target directory.`, "success");
        
        // Refresh dashboard status
        await loadSystemStats();
        
        // Add to portable profiles list
        appState.portableProfiles.push({
            name: plugin.name,
            format: plugin.format,
            type: plugin.type,
            portable_dir: targetDir,
            health: { healthy: true }
        });
        
    } catch (err) {
        log(`Failed to complete relocation: ${err.message}`, "error");
    }
}

// Deploy RESTORE logic
async function loadRestoreManifest() {
    const dirInput = document.getElementById("restore-dir-input");
    const dirPath = dirInput.value.trim();
    if (!dirPath) {
        alert("Please specify a directory path!");
        return;
    }

    try {
        const data = await apiCall("/api/profile/health", "POST", { portable_dir: dirPath });
        
        if (data.status === "missing_manifest") {
            alert("No symlinkr.json manifest found in this directory!");
            return;
        }

        // Show metadata panel
        const panel = document.getElementById("manifest-info-panel");
        panel.classList.remove("hidden");

        document.getElementById("manifest-name").textContent = data.name;
        document.getElementById("manifest-format").textContent = data.format;
        document.getElementById("manifest-format").setAttribute("format", data.format);
        document.getElementById("manifest-type").textContent = data.type === "wine" ? "Wine Setup" : "Linux Native";

        // Paths list
        const pathsList = document.getElementById("manifest-paths-list");
        pathsList.innerHTML = "";
        data.links.forEach(l => {
            const li = document.createElement("li");
            li.innerHTML = `<i class="fa-solid fa-link"></i> ${l.src} &rarr; ${l.status}`;
            pathsList.appendChild(li);
        });

        // Registry list
        const regSection = document.getElementById("manifest-reg-section");
        const regList = document.getElementById("manifest-reg-list");
        regList.innerHTML = "";
        
        // Check if there are registry entries (backend checks this via symlinkr.json manifest loaded)
        // If manifest has registry, we will fetch it. Since /health might not export keys list, we fetch from a loaded local manifest
        // For simplicity, we fetch info from manifest directly if needed, or we just rely on health status links.
        // Let's hide regSection for now if it's empty or show a placeholder.
        regSection.style.display = data.type === "wine" ? "block" : "none";

        log(`Loaded profile for ${data.name} successfully. Health is currently: ${data.healthy ? "Healthy" : "Needs Re-linking"}`, "success");
    } catch (err) {
        log("Failed to load manifest file metadata.", "error");
    }
}

async function executeDeploySingle() {
    const dirInput = document.getElementById("restore-dir-input");
    const dirPath = dirInput.value.trim();
    const strategy = document.getElementById("deploy-strategy").value;

    if (!dirPath) return;

    log(`Deploying profile from ${dirPath}...`, "info");
    switchTab("logs");

    try {
        const payload = { portable_dir: dirPath };
        if (strategy) {
            payload.strategy = strategy;
        }

        const res = await apiCall("/api/profile/apply", "POST", payload);
        log(`Successfully deployed plugin symlinks for ${res.manifest.name}!`, "success");
        
        await loadSystemStats();
    } catch (err) {
        log("Deployment failed.", "error");
    }
}

// Bulk scan library
async function scanLibraryDirectory() {
    const dirInput = document.getElementById("library-dir-input");
    const path = dirInput.value.trim();
    if (!path) {
        alert("Please specify a search path!");
        return;
    }

    log(`Scanning ${path} for SymLinkr profiles...`, "info");
    const bodyEl = document.getElementById("library-plugins-body");
    bodyEl.innerHTML = `<tr><td colspan="4" class="placeholder-row"><i class="fa-solid fa-circle-notch fa-spin"></i><p>Scanning directory structure...</p></td></tr>`;

    try {
        const data = await apiCall("/api/profile/scan_portable", "POST", { root_dir: path });
        appState.portableProfiles = data.profiles;

        renderPortableLibrary();
        log(`Found ${data.profiles.length} portable profiles.`, "success");
    } catch (err) {
        bodyEl.innerHTML = `<tr><td colspan="4" class="placeholder-row"><i class="fa-solid fa-triangle-exclamation"></i><p>Failed to scan directory.</p></td></tr>`;
    }
}

function renderPortableLibrary() {
    const bodyEl = document.getElementById("library-plugins-body");
    bodyEl.innerHTML = "";

    if (appState.portableProfiles.length === 0) {
        bodyEl.innerHTML = `<tr><td colspan="4" class="placeholder-row"><i class="fa-solid fa-box-open"></i><p>No portable plugin packages found in this directory.</p></td></tr>`;
        return;
    }

    appState.portableProfiles.forEach((p, idx) => {
        const tr = document.createElement("tr");
        
        const healthText = p.health.healthy ? 
            `<span class="health-badge healthy"><i class="fa-solid fa-check"></i> Linked</span>` :
            `<span class="health-badge broken"><i class="fa-solid fa-circle-xmark"></i> Unlinked</span>`;

        tr.innerHTML = `
            <td class="plugin-name-cell">${p.name}</td>
            <td><span class="plugin-badge" format="${p.format}">${p.format}</span></td>
            <td>${healthText}</td>
            <td>
                <button class="btn btn-primary btn-sm" onclick="deployFromLibrary(${idx})">
                    Link <i class="fa-solid fa-link"></i>
                </button>
            </td>
        `;
        bodyEl.appendChild(tr);
    });
}

async function deployFromLibrary(idx) {
    const profile = appState.portableProfiles[idx];
    if (!profile) return;

    log(`Deploying profile ${profile.name}...`, "info");
    switchTab("logs");

    try {
        const res = await apiCall("/api/profile/apply", "POST", { portable_dir: profile.portable_dir });
        log(`Successfully linked ${profile.name}!`, "success");
        
        // Refresh local table status and general stats
        await loadSystemStats();
        
        // Re-calculate health status
        profile.health.healthy = true;
        switchTab("deployer");
        renderPortableLibrary();
    } catch (err) {
        log(`Deployment of ${profile.name} failed.`, "error");
    }
}

// Global Diagnostics and Health
async function runGlobalHealthCheck() {
    log("Running symbolic link health diagnostics...", "info");
    
    const bodyEl = document.getElementById("health-links-body");
    bodyEl.innerHTML = `<tr><td colspan="6" class="placeholder-row"><i class="fa-solid fa-heart-pulse fa-spin"></i><p>Auditing links...</p></td></tr>`;

    let brokenCount = 0;
    let totalChecked = 0;
    bodyEl.innerHTML = "";

    if (appState.portableProfiles.length === 0) {
        bodyEl.innerHTML = `<tr><td colspan="6" class="placeholder-row"><p>No portable directories scanned yet. Go to "Deploy & Link" and scan a library directory first to audit links.</p></td></tr>`;
        return;
    }

    for (let i = 0; i < appState.portableProfiles.length; i++) {
        const p = appState.portableProfiles[i];
        try {
            const health = await apiCall("/api/profile/health", "POST", { portable_dir: p.portable_dir });
            p.health = health;
            
            health.links.forEach(l => {
                totalChecked++;
                const tr = document.createElement("tr");
                
                let badgeClass = "healthy";
                let badgeText = "Healthy";
                let badgeIcon = "fa-check";

                if (l.status !== "healthy") {
                    badgeClass = "broken";
                    badgeText = l.status.toUpperCase().replace("_", " ");
                    badgeIcon = "fa-circle-exclamation";
                    brokenCount++;
                }

                const srcTrunc = l.src.length > 35 ? "..." + l.src.slice(-32) : l.src;
                const destTrunc = l.dest.length > 35 ? "..." + l.dest.slice(-32) : l.dest;

                tr.innerHTML = `
                    <td class="plugin-name-cell">${health.name}</td>
                    <td><span class="plugin-badge" format="${health.format}">${health.format}</span></td>
                    <td class="plugin-path-cell" title="${l.src}">${srcTrunc}</td>
                    <td class="plugin-path-cell" title="${l.dest}">${destTrunc}</td>
                    <td>
                        <span class="health-badge ${badgeClass}">
                            <i class="fa-solid ${badgeIcon}"></i> ${badgeText}
                        </span>
                    </td>
                    <td>
                        <button class="btn btn-secondary btn-sm" onclick="repairLink('${p.portable_dir}')">
                            Repair <i class="fa-solid fa-wrench"></i>
                        </button>
                        <button class="btn btn-secondary btn-sm" onclick="unlinkPlugin('${p.portable_dir}')" style="color: var(--error);">
                            Unlink <i class="fa-solid fa-unlink"></i>
                        </button>
                    </td>
                `;
                bodyEl.appendChild(tr);
            });
        } catch (err) {
            log(`Failed to inspect health for profile in ${p.portable_dir}`, "error");
        }
    }

    // Update global health metrics card
    const healthCard = document.getElementById("health-stat-card");
    const healthValue = document.getElementById("stat-health");
    const healthIcon = document.getElementById("health-stat-icon");
    const activeLinksEl = document.getElementById("stat-active-links");

    activeLinksEl.textContent = totalChecked - brokenCount;

    if (brokenCount > 0) {
        healthValue.textContent = `${brokenCount} Broken`;
        healthCard.querySelector(".stat-icon").className = "stat-icon warning";
        healthIcon.innerHTML = `<i class="fa-solid fa-triangle-exclamation"></i>`;
        log(`Audit complete: Found ${brokenCount} issues across ${totalChecked} symlinks.`, "warning");
    } else {
        healthValue.textContent = "Perfect";
        healthCard.querySelector(".stat-icon").className = "stat-icon green";
        healthIcon.innerHTML = `<i class="fa-solid fa-check-circle"></i>`;
        log(`Audit complete: All ${totalChecked} symlinks verified healthy!`, "success");
    }
}

async function repairLink(dir) {
    log(`Repairing links for profile: ${dir}...`, "info");
    try {
        await apiCall("/api/profile/apply", "POST", { portable_dir: dir });
        log("Repair completed successfully.", "success");
        await runGlobalHealthCheck();
    } catch (err) {
        log("Failed to repair link.", "error");
    }
}

async function unlinkPlugin(dir) {
    if (!confirm("Are you sure you want to remove symlinks for this plugin? The files on your portable drive will NOT be deleted, only the link shortcuts on this host system.")) {
        return;
    }

    log(`Unlinking profile: ${dir}...`, "info");
    try {
        const res = await apiCall("/api/profile/unlink", "POST", { portable_dir: dir });
        log(`Removed ${res.unlinked_count} symbolic links successfully.`, "success");
        await runGlobalHealthCheck();
    } catch (err) {
        log("Failed to unlink plugin.", "error");
    }
}
