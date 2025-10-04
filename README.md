# RTVE Proxy

Docker Compose setup for proxying RTVE streaming through a Spanish VPN exit point.

## Quick Start

### 1. Get ProtonVPN Credentials

1. Log into your ProtonVPN account
2. Go to: https://account.protonvpn.com/account#openvpn
3. Copy your OpenVPN/IKEv2 username and password (not your regular account credentials)

### 2. Configure Environment

```bash
cp .env.example .env
# Edit .env with at minimum:
#   - PROTONVPN_USER and PROTONVPN_PASSWORD
#   - DOMAIN (your domain name)
#
# Additional vars needed depending on deployment mode:
#   - For Cloudflare Tunnel: CLOUDFLARE_API_TOKEN, CLOUDFLARE_TUNNEL_NAME
#   - For Let's Encrypt: SSL_EMAIL
```

### 3. Testing Locally (Mac)

For testing without SSL on your Mac:

1. Edit `nginx.conf` - comment out the HTTPS server block and uncomment the HTTP testing block
2. In `.env`, set `DOMAIN=localhost`
3. Run:
```bash
docker-compose up -d
```

4. Check VPN is working:
```bash
# Check VPN container logs
docker logs rtve-vpn

# Verify exit IP is in Spain
docker exec rtve-vpn curl -s ifconfig.me
```

5. Test the proxy:
```bash
curl http://localhost/rtve/your-stream-path.m3u8
```

### 4. Production Deployment (Raspberry Pi)

You have two options for production deployment:

#### Option A: Cloudflare Tunnel (Recommended - Easiest)

**Advantages:**
- No port forwarding required
- No need to expose Raspberry Pi to internet
- Cloudflare handles SSL automatically
- Built-in DDoS protection
- Works behind carrier-grade NAT

**Setup:**

1. Configure `.env` file with:
   - `PROTONVPN_USER` and `PROTONVPN_PASSWORD`
   - `DOMAIN` - your domain name (must use Cloudflare for DNS)
   - `CLOUDFLARE_API_TOKEN` - create at https://dash.cloudflare.com/profile/api-tokens
     - Required permissions: `Zone.Zone (Read)`, `Zone.DNS (Edit)`, `Account.Cloudflare Tunnel (Edit)`
   - `CLOUDFLARE_TUNNEL_NAME` - name for your tunnel (e.g., "rtve-proxy")

2. Run the setup script:

```bash
./setup-cloudflare.sh
```

That's it! The script will automatically:
- Create a Cloudflare Tunnel
- Generate tunnel credentials and save to .env
- Create DNS record pointing to the tunnel
- Start the full stack with HTTPS enabled

**Subsequent starts:**

```bash
docker-compose -f docker-compose.yml -f docker-compose.cloudflare.yml up -d
```

#### Option B: Let's Encrypt with Port Forwarding

**Use this if you don't use Cloudflare for DNS**

1. Configure `.env` file with:
   - `PROTONVPN_USER` and `PROTONVPN_PASSWORD`
   - `DOMAIN` - your domain name
   - `SSL_EMAIL` - email for Let's Encrypt notifications

2. Point your domain's DNS A record to your Raspberry Pi's public IP

3. Forward ports 80 and 443 on your router to your Raspberry Pi

4. Run the setup script:

```bash
./setup-ssl.sh
```

**Subsequent starts:**

```bash
docker-compose up -d
```

## Monitoring

**For Let's Encrypt mode:**
```bash
# View logs
docker-compose logs -f

# Check VPN status (should show Spanish IP)
docker exec rtve-vpn curl -s ifconfig.me

# Restart
docker-compose restart
```

**For Cloudflare Tunnel mode:**
```bash
# View logs
docker-compose -f docker-compose.yml -f docker-compose.cloudflare.yml logs -f

# Check VPN status (should show Spanish IP)
docker exec rtve-vpn curl -s ifconfig.me

# Restart
docker-compose -f docker-compose.yml -f docker-compose.cloudflare.yml restart

# Check tunnel status
docker logs rtve-cloudflared
```

## Troubleshooting

**General:**
- **VPN not connecting**: Check credentials in `.env` and verify ProtonVPN account is active
- **No Spain servers**: Make sure `FREE_ONLY=off` if you have a paid account
- **Nginx errors**: Check `docker-compose logs nginx`

**Cloudflare Tunnel specific:**
- **Tunnel not connecting**: Check `docker logs rtve-cloudflared` for errors
- **DNS not resolving**: Verify your domain uses Cloudflare nameservers
- **API token errors**: Ensure token has correct permissions (see setup instructions)

## What Files Are Created

**Required (committed to repo):**
- `docker-compose.yml` - Main compose file
- `docker-compose.cloudflare.yml` - Cloudflare Tunnel override
- `nginx.conf` - Nginx config for Let's Encrypt mode
- `nginx-cloudflare.conf` - Nginx config for Cloudflare mode
- `setup-ssl.sh` - Setup script for Let's Encrypt
- `setup-cloudflare.sh` - Setup script for Cloudflare Tunnel
- `.env.example` - Example environment variables

**Created by you:**
- `.env` - Your credentials and configuration (gitignored)

**Auto-generated (gitignored):**
- `gluetun/` - VPN configuration and state
- `cloudflared/` - Cloudflare Tunnel credentials (Cloudflare mode only)
- Docker volumes: `certbot-data`, `certbot-www` (Let's Encrypt mode only)
