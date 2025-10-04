# RTVE Proxy

Docker Compose setup for proxying RTVE streaming through a Spanish VPN exit point with Cloudflare Tunnel.

## Features

- 🔒 **Cloudflare Tunnel** - Secure inbound access without port forwarding (default)
- 🌍 **VPN Exit** - All traffic routes through ProtonVPN Spain servers
- ⚡ **HLS Caching** - Nginx caches video segments (500MB, 10min) to reduce bandwidth
- 🏥 **Health Monitoring** - Automatic health checks with container restart on failure
- 🔄 **Auto-recovery** - Monitors VPN connection, tunnel status, and endpoint health

## Quick Start (Cloudflare Tunnel - Recommended)

### 1. Get ProtonVPN Credentials

1. Log into your ProtonVPN account
2. Go to: https://account.protonvpn.com/account#openvpn
3. Copy your OpenVPN/IKEv2 username and password (not your regular account credentials)

### 2. Configure Environment

```bash
cp .env.example .env
# Edit .env with:
#   - PROTONVPN_USER and PROTONVPN_PASSWORD
#   - DOMAIN (your domain name - must use Cloudflare for DNS)
#   - CLOUDFLARE_API_TOKEN (from https://dash.cloudflare.com/profile/api-tokens)
#     Required permissions: Zone.Zone (Read), Zone.DNS (Edit), Account.Cloudflare Tunnel (Edit)
#   - CLOUDFLARE_TUNNEL_NAME (e.g., "rtve-proxy")
```

### 3. Setup Cloudflare Tunnel

```bash
./setup-cloudflare.sh
```

This will:
- Create a Cloudflare Tunnel
- Generate tunnel credentials
- Create DNS record automatically
- Start all services with health monitoring

### 4. Start Services (After Initial Setup)

```bash
docker-compose up -d
```

That's it! Your proxy is now running at `https://your-domain.com`

## Health Monitoring

The system includes automatic health checks every 5 minutes:

- ✅ VPN connection to Spain
- ✅ Nginx responsiveness
- ✅ Cloudflare tunnel connectivity
- ✅ Proxy endpoint availability
- ✅ Cache functionality

If any check fails, containers are automatically restarted.

View health check logs:
```bash
docker logs rtve-healthcheck
```

## Alternative: Let's Encrypt SSL (Without Cloudflare)

**Use this if you don't use Cloudflare for DNS**

### Requirements
- Domain with A record pointing to your server's public IP
- Ports 80 and 443 forwarded to your server

### Setup

1. Configure `.env` with:
   - `PROTONVPN_USER` and `PROTONVPN_PASSWORD`
   - `DOMAIN` - your domain name
   - `SSL_EMAIL` - email for Let's Encrypt notifications

2. Run the setup script:
```bash
./setup-ssl.sh
```

3. Start services:
```bash
docker-compose -f docker-compose.yml -f docker-compose.letsencrypt.yml up -d
```

## Monitoring

**Cloudflare mode:**
```bash
# View all logs
docker-compose logs -f

# Check VPN location (should show Spain)
docker exec rtve-vpn wget -qO- ipapi.co/country

# Check tunnel status
docker logs rtve-cloudflared

# Check health status
docker logs rtve-healthcheck
```

**Let's Encrypt mode:**
```bash
# View all logs
docker-compose -f docker-compose.yml -f docker-compose.letsencrypt.yml logs -f

# Check VPN location
docker exec rtve-vpn wget -qO- ipapi.co/country

# Check SSL renewal
docker logs rtve-certbot
```

## Caching Performance

The proxy caches HLS video segments to improve performance:

- **Cache size**: 500MB maximum
- **Retention**: 10 minutes per segment
- **Benefit**: Multiple viewers share cached segments, reducing VPN bandwidth

Check cache status with the `X-Cache-Status` response header:
- `HIT` - Served from cache
- `MISS` - Fetched from origin
- `UPDATING` - Being refreshed

## Troubleshooting

**General:**
- **VPN not connecting**: Check credentials in `.env` and verify ProtonVPN account is active
- **No Spain servers**: Make sure `FREE_ONLY=off` if you have a paid account
- **Nginx errors**: Check `docker logs rtve-nginx`
- **Health check failures**: Check `docker logs rtve-healthcheck` for specific issues

**Cloudflare Tunnel specific:**
- **Tunnel not connecting**: Check `docker logs rtve-cloudflared` for errors
- **DNS not resolving**: Verify your domain uses Cloudflare nameservers
- **API token errors**: Ensure token has correct permissions (see setup instructions)

**Let's Encrypt specific:**
- **Certificate errors**: Ensure ports 80/443 are forwarded and DNS is correct
- **Renewal failures**: Check `docker logs rtve-certbot`

## File Structure

**Main files:**
- `docker-compose.yml` - Main compose file (Cloudflare Tunnel mode)
- `docker-compose.letsencrypt.yml` - Let's Encrypt override
- `nginx-cloudflare.conf` - Nginx config for Cloudflare mode (with caching)
- `nginx.conf` - Nginx config for Let's Encrypt mode (with caching)
- `setup-cloudflare.sh` - Cloudflare Tunnel setup script
- `setup-ssl.sh` - Let's Encrypt setup script
- `healthcheck.sh` - Health monitoring script
- `.env.example` - Environment variables template

**Auto-generated (gitignored):**
- `.env` - Your credentials
- `gluetun/` - VPN state
- `cloudflared/` - Tunnel credentials (Cloudflare mode)
- Docker volumes: `certbot-data`, `certbot-www` (Let's Encrypt mode)

## Architecture

```
Internet
  ↓ (Cloudflare Tunnel - encrypted, no port forwarding)
cloudflared container (in VPN namespace)
  ↓ (localhost:80)
nginx container (in VPN namespace, with HLS cache)
  ↓ (outbound through VPN)
VPN container (ProtonVPN Spain exit)
  ↓
rtvelivestream.rtve.es
```

Health monitoring runs every 5 minutes and restarts containers if issues detected.
