#!/bin/sh
# Health check script for RTVE proxy

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Identify which replica this is
HOSTNAME=$(hostname)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$HOSTNAME] $1"
}

error() {
    echo "${RED}[ERROR]${NC} [$HOSTNAME] $1"
}

success() {
    echo "${GREEN}[OK]${NC} [$HOSTNAME] $1"
}

warning() {
    echo "${YELLOW}[WARN]${NC} [$HOSTNAME] $1"
}

FAILED=0

# 1. Check VPN is connected to Spain
log "Checking VPN connection to Spain..."
VPN_COUNTRY=$(docker exec rtve-vpn wget -qO- --timeout=10 https://ipapi.co/country 2>/dev/null)

if [ "$VPN_COUNTRY" = "ES" ]; then
    success "VPN connected to Spain"
else
    error "VPN not in Spain (detected: $VPN_COUNTRY)"
    FAILED=1
fi

# 2. Check nginx is responding
log "Checking nginx health..."
NGINX_STATUS=$(docker exec rtve-vpn wget --spider -S --timeout=5 http://localhost:80 2>&1 | grep "HTTP/" | head -1 | awk '{print $2}')

if [ "$NGINX_STATUS" = "200" ] || [ "$NGINX_STATUS" = "404" ] || [ "$NGINX_STATUS" = "302" ]; then
    success "Nginx is responding (HTTP $NGINX_STATUS)"
else
    error "Nginx not responding properly (HTTP $NGINX_STATUS)"
    FAILED=1
fi

# 3. Check cloudflared tunnel is connected
log "Checking Cloudflare tunnel..."
TUNNEL_CONNECTIONS=$(docker logs rtve-cloudflared 2>&1 | grep "Registered tunnel connection" | tail -1)

if [ -n "$TUNNEL_CONNECTIONS" ]; then
    success "Cloudflare tunnel connected"
else
    error "Cloudflare tunnel not connected"
    FAILED=1
fi

# 4. Test LOCAL proxy endpoint with real stream through VPN
log "Testing LOCAL proxy endpoint (not external domain)..."
# Test the local nginx instance directly via the VPN container
LOCAL_TEST=$(docker exec rtve-vpn wget -qO- --timeout=10 "http://localhost:80/eventual/gofast/playm9_main.m3u8" 2>/dev/null | head -1)

if echo "$LOCAL_TEST" | grep -q "#EXTM3U"; then
    success "LOCAL proxy endpoint working (returns valid HLS playlist)"
else
    error "LOCAL proxy endpoint failed (invalid response)"
    FAILED=1
fi

# 4b. Verify URL rewriting is working locally
log "Checking URL rewriting..."
REWRITE_CHECK=$(docker exec rtve-vpn wget -qO- --timeout=10 "http://localhost:80/eventual/gofast/playm9_main.m3u8" 2>/dev/null | grep -c "https://${DOMAIN}/" || echo "0")

if [ "$REWRITE_CHECK" -gt 0 ]; then
    success "URL rewriting working ($REWRITE_CHECK URLs rewritten)"
else
    warning "URL rewriting may not be working (check sub_filter)"
fi

# 5. Check cache is working
log "Checking nginx cache..."
if docker exec rtve-nginx test -d /var/cache/nginx 2>/dev/null; then
    success "Nginx cache directory exists"
else
    warning "Nginx cache directory missing"
fi

# 6. Test direct RTVE connectivity through VPN
log "Testing direct RTVE connectivity..."
RTVE_TEST=$(docker exec rtve-vpn wget --spider -S --timeout=10 "https://rtvelivestream.rtve.es/eventual/gofast/playm9_main.m3u8" 2>&1 | grep "HTTP/" | head -1 | awk '{print $2}')

if [ "$RTVE_TEST" = "200" ]; then
    success "RTVE servers reachable (HTTP $RTVE_TEST)"
else
    error "Cannot reach RTVE servers (HTTP $RTVE_TEST)"
    FAILED=1
fi

# 7. Informational: Check external domain (may hit other replica)
log "Checking external domain (informational only)..."
EXTERNAL_TEST=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://${DOMAIN}/eventual/gofast/playm9_main.m3u8" 2>/dev/null)

if [ "$EXTERNAL_TEST" = "200" ]; then
    log "External domain responding (HTTP $EXTERNAL_TEST) - may be this or other replica"
else
    log "External domain issue (HTTP $EXTERNAL_TEST) - NOT failing this replica"
fi

# Restart if failures detected
if [ $FAILED -eq 1 ]; then
    error "Health check failed! Restarting LOCAL containers..."
    docker restart rtve-vpn rtve-nginx rtve-cloudflared
    exit 1
else
    success "All LOCAL health checks passed!"
    exit 0
fi
