#!/bin/sh
# Health check script for RTVE proxy

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "${RED}[ERROR]${NC} $1"
}

success() {
    echo "${GREEN}[OK]${NC} $1"
}

warning() {
    echo "${YELLOW}[WARN]${NC} $1"
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

# 4. Test actual proxy endpoint with real stream
log "Testing proxy endpoint..."
TEST_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://${DOMAIN}/eventual/gofast/playm9_main.m3u8" 2>/dev/null)

if [ "$TEST_RESPONSE" = "200" ]; then
    success "Proxy endpoint working (HTTP $TEST_RESPONSE)"
else
    error "Proxy endpoint failed (HTTP $TEST_RESPONSE)"
    FAILED=1
fi

# 5. Check cache is working
log "Checking nginx cache..."
if docker exec rtve-nginx test -d /var/cache/nginx 2>/dev/null; then
    success "Nginx cache directory exists"
else
    warning "Nginx cache directory missing"
fi

# Restart if failures detected
if [ $FAILED -eq 1 ]; then
    error "Health check failed! Restarting containers..."
    docker restart rtve-vpn rtve-nginx rtve-cloudflared
    exit 1
else
    success "All health checks passed!"
    exit 0
fi
