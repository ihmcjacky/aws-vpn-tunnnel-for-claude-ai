function FindProxyForURL(url, host) {
    // =================================================================
    // CONFIGURATION SECTION - Easy to maintain URL list
    // =================================================================

    // List of domains that should be routed through the proxy
    // Add or remove domains here as needed - supports wildcards with *
    var proxyDomains = [
        "*.ip.me",
        "*.claude.ai",
        "*.anthropic.com",
        "*.openai.com",
        "*.chatgpt.com"
    ];

    // Proxy server configuration
    var proxyServer = "SOCKS 127.0.0.1:1080";
    var directConnection = "DIRECT";

    // Debug mode - set to true to enable logging (check browser console)
    var debugMode = false;

    // =================================================================
    // LOGIC SECTION - Enhanced matching with debugging
    // =================================================================

    // Clean the host parameter - remove port numbers if present
    var cleanHost = host.split(':')[0].toLowerCase();

    if (debugMode) {
        console.log("PAC Debug - Original host: " + host);
        console.log("PAC Debug - Clean host: " + cleanHost);
        console.log("PAC Debug - URL: " + url);
    }

    // Check if the current host matches any domain in our proxy list
    for (var i = 0; i < proxyDomains.length; i++) {
        var domain = proxyDomains[i].toLowerCase();

        if (debugMode) {
            console.log("PAC Debug - Checking domain: " + domain);
        }

        // Multiple matching strategies for robustness
        var isMatch = false;

        // Strategy 1: Standard shExpMatch (works for most cases)
        if (shExpMatch(cleanHost, domain)) {
            isMatch = true;
            if (debugMode) console.log("PAC Debug - Match found via shExpMatch");
        }

        // Strategy 2: Manual wildcard matching (fallback)
        if (!isMatch && domain.indexOf('*') === 0) {
            var domainSuffix = domain.substring(1); // Remove the *
            if (cleanHost.indexOf(domainSuffix) === cleanHost.length - domainSuffix.length) {
                isMatch = true;
                if (debugMode) console.log("PAC Debug - Match found via manual wildcard");
            }
        }

        // Strategy 3: Exact match (for non-wildcard domains)
        if (!isMatch && domain.indexOf('*') === -1) {
            if (cleanHost === domain) {
                isMatch = true;
                if (debugMode) console.log("PAC Debug - Match found via exact match");
            }
        }

        if (isMatch) {
            if (debugMode) console.log("PAC Debug - Routing through proxy: " + proxyServer);
            return proxyServer;
        }
    }

    // For all other domains, connect directly (no proxy)
    if (debugMode) console.log("PAC Debug - Using direct connection");
    return directConnection;
}