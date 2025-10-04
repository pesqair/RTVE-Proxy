#!/bin/bash

# Setup script for initial SSL certificate generation
# Run this once on the Raspberry Pi before starting the full stack

set -e

# Load environment variables from .env
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "Error: .env file not found. Please create one from .env.example"
    exit 1
fi

echo "Setting up SSL certificate for $DOMAIN..."

# Start only the VPN
docker-compose up -d vpn

echo "Waiting for VPN to connect..."
sleep 10

# Create temporary nginx config for HTTP-only (for initial cert generation)
cat > /tmp/nginx-temp.conf << EOF
events {
    worker_connections 1024;
}

http {
    server {
        listen 80;
        server_name $DOMAIN;

        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
    }
}
EOF

# Start temporary nginx
docker run -d --name nginx-temp \
  --network "container:rtve-vpn" \
  -v /tmp/nginx-temp.conf:/etc/nginx/nginx.conf:ro \
  -v rtve-proxy_certbot-www:/var/www/certbot:ro \
  nginx:alpine

echo "Requesting certificate for $DOMAIN..."
docker-compose run --rm certbot certonly --webroot \
  -w /var/www/certbot \
  -d "$DOMAIN" \
  --email "$SSL_EMAIL" \
  --agree-tos \
  --no-eff-email

# Clean up temporary nginx
docker stop nginx-temp
docker rm nginx-temp
rm /tmp/nginx-temp.conf

echo "Certificate obtained! Starting full stack..."
docker-compose down
docker-compose up -d

echo "Done! Your proxy should now be running with SSL at https://$DOMAIN"
echo "Check logs with: docker-compose logs -f"
