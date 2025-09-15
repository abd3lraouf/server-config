# Coolify WebSocket Terminal - Complete Configuration Guide

## Overview

This guide explains the complete WebSocket configuration for Coolify's terminal feature, especially when using Cloudflare Tunnel and/or Tailscale VPN.

## Architecture Diagram

```
Internet Users                    VPN Users
      |                               |
      v                               v
[Cloudflare Tunnel]              [Tailscale]
      |                               |
      | (HTTPS/WSS:443)               | (HTTP/WS:6001-6002)
      |                               |
      +---------------+---------------+
                      |
                      v
                [UFW Firewall]
                      |
                      v
              [Traefik Proxy]
                      |
                      v
            [Nginx (in Coolify)]
                      |
         +------------+------------+
         |                         |
         v                         v
    [Port 6001]               [Port 6002]
    Pusher/App                Terminal/WS
         |                         |
         +------------+------------+
                      |
                      v
              [Coolify Realtime]
                      |
                      v
                   [SSH]
                      |
                      v
              [Target Container]
```

## Component Details

### 1. Cloudflare Tunnel
- **Purpose**: Secure HTTPS access from internet
- **Configuration**: Routes `/terminal/ws` and `/app` paths
- **Protocol**: HTTPS/WSS on port 443
- **Auto-handles**: WebSocket upgrade headers

### 2. Tailscale VPN
- **Purpose**: Direct secure access for VPN users
- **Network**: 100.64.0.0/10 (Tailscale's CGNAT range)
- **Protocol**: HTTP/WS on ports 6001-6002
- **Detection**: Automatic via `tailscale0` interface

### 3. UFW Firewall
- **Dynamic Rules**:
  ```bash
  # Automatically added by script
  ufw allow from 100.64.0.0/10 to any port 6001 proto tcp  # Pusher
  ufw allow from 100.64.0.0/10 to any port 6002 proto tcp  # Terminal
  ```

### 4. Traefik Proxy
- **Config Location**: `/data/coolify/proxy/dynamic/coolify-websocket.yaml`
- **Entrypoint**: `https` (not `websecure`)
- **Routes**: Based on hostname and path matching

### 5. Nginx (Inside Coolify Container)
- **Config File**: `/etc/nginx/site-opts.d/http.conf`
- **WebSocket Proxy**:
  - `/terminal/ws` → `coolify-realtime:6002`
  - `/app` → `coolify-realtime:6001`
- **Important**: Config appended to `http.conf` (not separate file)

### 6. Coolify Realtime Container
- **Image**: `ghcr.io/coollabsio/coolify-realtime`
- **Ports**:
  - 6001: Pusher/Laravel Echo (app notifications)
  - 6002: Terminal WebSocket connections
- **Protocol**: Soketi (Pusher-compatible WebSocket server)

## Dynamic Configuration

The script automatically detects and configures based on your environment:

### Tailscale Detection
```bash
# Automatic detection
tailscale_ip=$(ip -4 addr show tailscale0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
```

### PUSHER Configuration Logic
```bash
if [domain_access]; then
    PUSHER_HOST=your.domain.com
    PUSHER_PORT=443
    PUSHER_SCHEME=https
elif [tailscale_access]; then
    PUSHER_HOST=$tailscale_ip
    PUSHER_PORT=6001
    PUSHER_SCHEME=http
fi
```

## Persistence Mechanism

### Systemd Service
- **File**: `/etc/systemd/system/coolify-websocket.service`
- **Script**: `/data/coolify/nginx-config/apply-websocket.sh`
- **Triggers**: After Docker service starts
- **Function**: Reapplies WebSocket config to Coolify container

### Auto-Recovery Process
1. System boots / Docker restarts
2. Systemd waits 10 seconds for containers
3. Script checks if config exists in container
4. If missing, appends WebSocket config to `http.conf`
5. Reloads nginx inside container

## Troubleshooting

### Common Issues

#### 1. "Terminal websocket connection lost"
- **Check Cloudflare path order** (specific before wildcard)
- **Verify services**: `docker ps | grep coolify`
- **Check logs**: `docker logs coolify-realtime`

#### 2. WebSocket not connecting through Cloudflare
- Ensure paths are ordered correctly in Cloudflare dashboard
- No special WebSocket settings needed (auto-handled)

#### 3. Tailscale users can't connect
- Verify Tailscale IP: `tailscale status`
- Check firewall: `sudo ufw status numbered | grep 600`
- Ensure PUSHER_HOST matches access method

### Debug Commands

```bash
# Check WebSocket ports
nc -zv localhost 6001
nc -zv localhost 6002

# Test WebSocket upgrade
curl -I http://localhost:8000/terminal/ws \
  -H "Upgrade: websocket" \
  -H "Connection: Upgrade"

# Check nginx config in container
docker exec coolify cat /etc/nginx/site-opts.d/http.conf | grep -A10 terminal

# View realtime logs
docker logs coolify-realtime --tail 50

# Check PUSHER config
docker exec coolify cat /var/www/html/.env | grep PUSHER
```

## Manual Recovery

If automatic configuration fails:

```bash
# Reapply WebSocket configuration
sudo systemctl restart coolify-websocket

# Or manually run the script
sudo /data/coolify/nginx-config/apply-websocket.sh

# Verify configuration
docker exec coolify nginx -t
docker exec coolify nginx -s reload
```

## Security Considerations

1. **Firewall Rules**: Only allow WebSocket ports from trusted networks
2. **Tailscale Access**: Restricted to VPN users only
3. **Cloudflare Access**: Can add additional authentication layer
4. **Container Isolation**: WebSocket proxy runs inside containers

## Related Files

- **Main Module**: `/src/containers/coolify.sh`
- **Persistence Script**: `/data/coolify/nginx-config/apply-websocket.sh`
- **Systemd Service**: `/etc/systemd/system/coolify-websocket.service`
- **Traefik Config**: `/data/coolify/proxy/dynamic/coolify-websocket.yaml`

## Version Compatibility

- **Coolify**: 4.0.0-beta.426+
- **Traefik**: 3.1+
- **Ubuntu**: 20.04, 22.04, 24.04
- **Docker**: 20.10+
- **Tailscale**: Any version with `tailscale0` interface