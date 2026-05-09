# Caddy Reverse Proxy - Local HTTPS Development Setup

This document describes the Caddy reverse proxy configuration for local HTTPS development with Chatwoot.

## Overview

Caddy is configured as a reverse proxy to provide HTTPS for local development. It listens on `https://localhost:3000` and forwards all requests to the Rails container running on port 3000.

## Architecture

```
Browser → https://localhost:3000
         ↓ (HTTPS with self-signed cert)
    Caddy Container (port 3000)
         ↓ (HTTP proxy)
    Rails Container (port 3000)
```

### WebSocket Support

```
Browser → wss://localhost:3000/cable
         ↓ (WebSocket Upgrade with HTTPS)
    Caddy (automatic WebSocket detection)
         ↓ (WebSocket forwarding)
    Rails ActionCable (port 3000)
         ↓
    Redis (pub/sub backend)
```

## Configuration Files

### 1. `docker-compose.yaml`

The Caddy service is defined in `docker-compose.yaml`:

```yaml
caddy:
  image: caddy:2-alpine
  restart: always
  ports:
    - "3000:3000"  # HTTPS on port 3000
  volumes:
    - ./Caddyfile:/etc/caddy/Caddyfile
    - caddy_data:/data
    - caddy_config:/config
  depends_on:
    - rails
```

**Note:** The Rails container's port 3000 is NOT exposed to the host. Only Caddy exposes port 3000.

### 2. `Caddyfile`

The Caddy configuration file located in the project root:

```caddyfile
:3000 {
    tls internal  # Generate self-signed certificate automatically

    reverse_proxy rails:3000 {
        # Preserve original client information
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}

        # WebSocket support (automatic)
        # Caddy automatically handles Upgrade headers for WebSocket connections
    }
}
```

### 3. Environment Variables

**`.env` and `.env.example`:**

```bash
# For local development with HTTPS: Caddy reverse proxy handles TLS on port 3000
FRONTEND_URL=https://localhost:3000
```

## Features

### 1. Automatic HTTPS

- **Self-Signed Certificates**: Caddy automatically generates and manages self-signed TLS certificates
- **Certificate Storage**: Certificates are stored in the `caddy_data` Docker volume
- **No Manual Setup**: No need to run `mkcert` or manually install certificates
- **Automatic Renewal**: Caddy handles certificate lifecycle automatically

### 2. WebSocket Support

- **Automatic Detection**: Caddy automatically detects WebSocket upgrade requests
- **Header Forwarding**: All required headers (`Connection`, `Upgrade`) are automatically forwarded
- **ActionCable Compatible**: Works seamlessly with Rails ActionCable for real-time features
- **No Additional Config**: WebSocket support is built-in to `reverse_proxy` directive

### 3. Header Preservation

The following headers are forwarded to Rails:

| Header | Description |
|--------|-------------|
| `Host` | Original host header from client |
| `X-Real-IP` | Client's real IP address |
| `X-Forwarded-For` | Client's IP (for proxy chains) |
| `X-Forwarded-Proto` | Original protocol (https) |
| `X-Forwarded-Host` | Original host header |

These headers ensure Rails can correctly identify:
- The original client's IP address
- The protocol used (HTTPS)
- The host being accessed

## Usage

### Starting Caddy

```bash
# Start all services including Caddy
docker compose up -d

# Or start only Caddy
docker compose up -d caddy
```

### Accessing Chatwoot

Open your browser and navigate to:
```
https://localhost:3000
```

**First Time Access:**
- Your browser will show a security warning (self-signed certificate)
- Click "Advanced" → "Proceed to localhost (unsafe)"
- This warning is normal for self-signed certificates in development

### Stopping Caddy

```bash
# Stop Caddy
docker compose stop caddy

# Stop and remove Caddy container
docker compose down caddy
```

## Management Commands

### Reload Configuration

After modifying `Caddyfile`, reload without restarting:

```bash
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

### View Caddy Logs

```bash
# View all logs
docker compose logs caddy

# Follow logs in real-time
docker compose logs -f caddy

# View last 50 lines
docker compose logs caddy --tail=50
```

### Check Caddy Status

```bash
# Check if Caddy is running
docker compose ps caddy

# Check configuration syntax
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile
```

### Format Caddyfile

```bash
# Auto-format Caddyfile
docker compose exec caddy caddy fmt --overwrite /etc/caddy/Caddyfile
```

## Troubleshooting

### Issue: Browser Shows Certificate Error

**Solution:** This is normal for self-signed certificates. Options:

1. **Accept the warning** (easiest for development)
   - Click "Advanced" → "Proceed to localhost"

2. **Trust the certificate** (better experience)
   ```bash
   # Extract Caddy's root certificate
   docker compose exec caddy cat /data/caddy/pki/authorities/local/root.crt > /tmp/caddy-root.crt

   # Import into your system/browser trust store
   # Instructions vary by OS/browser
   ```

### Issue: WebSocket Connection Fails

**Check:**

1. Verify Caddy is running:
   ```bash
   docker compose ps caddy
   ```

2. Check Caddy logs for errors:
   ```bash
   docker compose logs caddy --tail=50
   ```

3. Verify WebSocket endpoint in browser DevTools:
   - Open DevTools → Network tab
   - Filter by "WS" (WebSocket)
   - Look for `/cable` connection with status "101 Switching Protocols"

### Issue: 502 Bad Gateway

**Cause:** Rails container is not running or not reachable.

**Solution:**

1. Check Rails container status:
   ```bash
   docker compose ps rails
   ```

2. Restart Rails if needed:
   ```bash
   docker compose restart rails
   ```

3. Check Docker network connectivity:
   ```bash
   docker compose exec caddy ping rails
   ```

### Issue: Port 3000 Already in Use

**Cause:** Another service is using port 3000.

**Solution:**

1. Find the process using port 3000:
   ```bash
   sudo lsof -i :3000
   # or
   sudo netstat -tulpn | grep :3000
   ```

2. Stop the conflicting service or change Caddy's port in `docker-compose.yaml`:
   ```yaml
   ports:
     - "3001:3000"  # Use port 3001 instead
   ```

## Security Notes

### Development vs Production

⚠️ **This configuration is for LOCAL DEVELOPMENT ONLY**

**Do NOT use this setup in production:**
- Self-signed certificates are not trusted by browsers
- No rate limiting or DDoS protection
- Simplified configuration for ease of development

### Production Recommendations

For production deployments:

1. **Use Real Certificates**: Let's Encrypt or commercial CA
2. **Update Caddyfile**: Configure proper domain and automatic HTTPS
3. **Add Security Headers**: HSTS, CSP, X-Frame-Options, etc.
4. **Enable Rate Limiting**: Protect against abuse
5. **Use Standard Ports**: 443 for HTTPS, 80 for HTTP redirects

Example production Caddyfile:

```caddyfile
yourdomain.com {
    # Let's Encrypt automatic HTTPS
    tls your-email@example.com

    # Security headers
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Frame-Options "SAMEORIGIN"
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
    }

    # Rate limiting
    rate_limit {
        zone dynamic {
            key {remote_host}
            events 100
            window 1m
        }
    }

    reverse_proxy rails:3000 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
    }
}
```

## OAuth/OpenID Configuration

When using OAuth providers (like Click2Run OpenID), ensure your redirect URIs use HTTPS:

### Development
```
https://localhost:3000/auth/click2run/callback
```

### Production
```
https://yourdomain.com/auth/click2run/callback
```

Configure these URLs in your OAuth provider's console (e.g., Click2Run Auth Console).

## Docker Volumes

Caddy uses two Docker volumes for persistent data:

- **`caddy_data`**: Stores certificates, ACME account info, and other data
- **`caddy_config`**: Stores configuration cache and autosaved configs

These volumes persist across container restarts, ensuring:
- Certificates are not regenerated on every restart
- Configuration is preserved
- Faster startup times

### Managing Volumes

```bash
# List volumes
docker volume ls | grep caddy

# Inspect volume
docker volume inspect chatwootgit_caddy_data

# Remove volumes (will regenerate certificates on next start)
docker compose down -v
```

## Additional Resources

- [Caddy Documentation](https://caddyserver.com/docs/)
- [Caddy Reverse Proxy Guide](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
- [Caddy TLS Documentation](https://caddyserver.com/docs/caddyfile/directives/tls)
- [Rails ActionCable Deployment](https://guides.rubyonrails.org/action_cable_overview.html#deployment)

## Support

For issues related to:
- **Caddy configuration**: See [Caddy Community Forum](https://caddy.community/)
- **Chatwoot setup**: See [Chatwoot Documentation](https://www.chatwoot.com/docs/)
- **This project**: Check project README or contact the development team
