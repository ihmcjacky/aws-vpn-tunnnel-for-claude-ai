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

    // =================================================================
    // LOGIC SECTION - No need to modify below this line
    // =================================================================

    // Convert host to lowercase for case-insensitive matching
    var lowerHost = host.toLowerCase();

    // Check if the current host matches any domain in our proxy list
    for (var i = 0; i < proxyDomains.length; i++) {
        var domain = proxyDomains[i].toLowerCase();

        // Use shExpMatch for wildcard pattern matching
        if (shExpMatch(lowerHost, domain)) {
            // Route through our proxy server
            return proxyServer;
        }
    }

    // For all other domains, connect directly (no proxy)
    return directConnection;
}