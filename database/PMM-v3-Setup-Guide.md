# PMM Server v3 Setup Guide

## Overview

This guide provides step-by-step instructions for setting up Percona Monitoring and Management (PMM) Server version 3 using Docker, following best practices for production environments.

## Prerequisites

Before starting, ensure you have the following installed:

- **Docker**: Version 20.10 or later
- **Operating System**: macOS, Linux, or Windows with Docker support
- **Hardware Requirements**:
  - Minimum: 2 GB RAM, 2 CPU cores, 20 GB disk space
  - Recommended: 4 GB RAM, 4 CPU cores, 100 GB disk space
- **Network Access**: Internet connection for downloading Docker images

### Verify Docker Installation

```bash
docker --version
```

Expected output:
```
Docker version 27.5.1, build 9f9e405
```

## Setup Steps

### Step 1: Check for Existing PMM Containers

Before installing, check if you have any existing PMM containers:

```bash
docker ps -a --filter name=pmm-server
```

If you find existing containers, stop and remove them:

```bash
docker stop pmm-server
docker rm pmm-server
```

### Step 2: Clean Up Existing Volumes (Optional)

If you want a fresh installation, remove any existing PMM data volumes:

```bash
# List PMM volumes
docker volume ls | grep pmm

# Remove existing volume (CAUTION: This will delete all PMM data)
docker volume rm pmm-data
```

**⚠️ Warning**: This will permanently delete all PMM historical data.

### Step 3: Run PMM Server v3 Container

Run the PMM Server v3 container with proper port mapping:

```bash
docker run \
  --detach \
  --restart always \
  --publish 9090:8080 \
  --publish 9443:8443 \
  --volume pmm-data:/srv \
  --name pmm-server \
  percona/pmm-server:3
```

**Command Explanation**:
- `--detach`: Run container in background
- `--restart always`: Auto-restart container on system reboot
- `--publish 9090:8080`: Map external port 9090 to internal HTTP port 8080
- `--publish 9443:8443`: Map external port 9443 to internal HTTPS port 8443
- `--volume pmm-data:/srv`: Create persistent volume for PMM data
- `--name pmm-server`: Set container name for easy management

### Step 4: Verify Container Status

Check if the container is running and healthy:

```bash
docker ps --filter name=pmm-server
```

Expected output:
```
CONTAINER ID   IMAGE                  COMMAND                CREATED          STATUS                    PORTS                                                             NAMES
98b1ea3acb2d   percona/pmm-server:3   "/opt/entrypoint.sh"   2 minutes ago    Up 2 minutes (healthy)   0.0.0.0:9090->8080/tcp, 0.0.0.0:9443->8443/tcp   pmm-server
```

### Step 5: Wait for Initialization

PMM Server needs time to initialize all services. Wait 20-30 seconds, then test connectivity:

```bash
curl -I http://localhost:9090
```

Expected response:
```
HTTP/1.1 302 Moved Temporarily
Server: nginx
Date: Sat, 23 Aug 2025 04:22:56 GMT
Location: http://localhost:9090/graph/
```

## Access PMM Server

### Web Interface Access

- **HTTP**: http://localhost:9090
- **HTTPS**: https://localhost:9443 (recommended for production)

### Default Credentials

- **Username**: `admin`
- **Password**: `admin`

**⚠️ Important**: Change the default password immediately after first login for security.

## Post-Installation Configuration

### 1. First Login and Password Change

1. Open your web browser and navigate to http://localhost:9090
2. Log in with `admin/admin`
3. You'll be prompted to change the default password
4. Set a strong password following your organization's password policy

### 2. SSL/TLS Configuration (Production)

For production environments, configure proper SSL certificates:

```bash
# Stop the container
docker stop pmm-server

# Run with SSL certificate volumes
docker run \
  --detach \
  --restart always \
  --publish 443:8443 \
  --volume pmm-data:/srv \
  --volume /path/to/ssl/certs:/srv/nginx \
  --name pmm-server \
  percona/pmm-server:3
```

### 3. Resource Limits (Production)

Set resource limits for production deployments:

```bash
docker run \
  --detach \
  --restart always \
  --publish 9090:8080 \
  --publish 9443:8443 \
  --volume pmm-data:/srv \
  --memory=4g \
  --cpus=2 \
  --name pmm-server \
  percona/pmm-server:3
```

## Management Commands

### Container Management

```bash
# Start PMM Server
docker start pmm-server

# Stop PMM Server
docker stop pmm-server

# Restart PMM Server
docker restart pmm-server

# View container logs
docker logs pmm-server

# View real-time logs
docker logs -f pmm-server
```

### Health Checks

```bash
# Check container status
docker ps --filter name=pmm-server

# Check service status inside container
docker exec pmm-server supervisorctl status

# Test HTTP connectivity
curl -I http://localhost:9090

# Check listening ports inside container
docker exec pmm-server ss -tlnp
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Container Keeps Restarting

**Check logs**:
```bash
docker logs pmm-server
```

**Common causes**:
- Volume permission issues
- Port conflicts
- Insufficient resources

#### 2. Cannot Access Web Interface

**Verify container is running**:
```bash
docker ps --filter name=pmm-server
```

**Check port mapping**:
```bash
docker port pmm-server
```

**Test connectivity**:
```bash
curl -v http://localhost:9090
```

#### 3. Port Already in Use

**Find process using the port**:
```bash
lsof -i :9090
```

**Use different ports**:
```bash
docker run \
  --detach \
  --restart always \
  --publish 8080:8080 \
  --publish 8443:8443 \
  --volume pmm-data:/srv \
  --name pmm-server \
  percona/pmm-server:3
```

### Service Status Commands

```bash
# Check all PMM services status
docker exec pmm-server supervisorctl status

# Restart specific service
docker exec pmm-server supervisorctl restart nginx

# Check nginx configuration
docker exec pmm-server nginx -t
```

## Security Best Practices

### 1. Network Security

- Use HTTPS in production environments
- Configure firewall rules to restrict access
- Use reverse proxy with proper SSL termination
- Enable network segmentation

### 2. Access Control

- Change default passwords immediately
- Implement strong password policies
- Use LDAP/Active Directory integration if available
- Regular password rotation

### 3. Data Protection

- Regular backup of PMM data volume
- Encrypt data at rest
- Monitor access logs
- Implement data retention policies

### 4. Container Security

- Use specific version tags instead of `latest`
- Regular security updates
- Resource limits and constraints
- Non-root user execution (when possible)

## Backup and Recovery

### Backup PMM Data

```bash
# Create backup of PMM data volume
docker run --rm -v pmm-data:/data -v $(pwd):/backup alpine tar czf /backup/pmm-backup-$(date +%Y%m%d).tar.gz -C /data .
```

### Restore PMM Data

```bash
# Stop PMM Server
docker stop pmm-server

# Restore from backup
docker run --rm -v pmm-data:/data -v $(pwd):/backup alpine tar xzf /backup/pmm-backup-YYYYMMDD.tar.gz -C /data

# Start PMM Server
docker start pmm-server
```

## Monitoring and Maintenance

### Regular Maintenance Tasks

1. **Monitor disk usage**:
   ```bash
   docker exec pmm-server df -h
   ```

2. **Check container resource usage**:
   ```bash
   docker stats pmm-server
   ```

3. **Update PMM Server**:
   ```bash
   docker pull percona/pmm-server:3
   docker stop pmm-server
   docker rm pmm-server
   # Run with new image (same command as initial setup)
   ```

4. **Log rotation**:
   ```bash
   docker logs pmm-server 2>/dev/null | wc -l
   ```

## Version Information

- **PMM Server Version**: 3.x
- **Docker Image**: percona/pmm-server:3
- **Internal Ports**: 8080 (HTTP), 8443 (HTTPS)
- **Default Credentials**: admin/admin

## Additional Resources

- [PMM Documentation](https://docs.percona.com/percona-monitoring-and-management/)
- [PMM Docker Hub](https://hub.docker.com/r/percona/pmm-server)
- [Percona Community](https://forums.percona.com/)
- [PMM GitHub Repository](https://github.com/percona/pmm)

## Support

For issues and questions:
- Check the troubleshooting section in this document
- Review PMM official documentation
- Search Percona community forums
- Create GitHub issues for bugs
- Contact Percona support (for commercial customers)

---

**Document Version**: 1.0  
**Last Updated**: August 23, 2025  
**Author**: Database Administration Team
