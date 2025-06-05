# Asterisk ARA Dynamic Call Router - Production System

A production-level dynamic call routing system with full Asterisk Realtime Architecture (ARA) integration.

## Features

- **Full ARA Integration**: All Asterisk configuration stored in MySQL
- **Dynamic Call Routing**: Real-time call flow management between multiple providers
- **DID Pool Management**: Dynamic DID allocation and release
- **Load Balancing**: Multiple algorithms (round-robin, weighted, priority, etc.)
- **Health Monitoring**: Real-time provider health checks
- **High Availability**: Redis caching, connection pooling, automatic failover
- **Security**: Call verification at each step
- **Observability**: Prometheus metrics, health endpoints, structured logging
- **CLI Management**: Comprehensive command-line interface

## Architecture

The system implements the call flow as specified:
1. Call arrives at S1 → Routes to S2 with ANI transformation
2. S2 allocates DID and forwards to S3
3. S3 returns call to S2
4. S2 routes to S4 with original ANI/DNIS
5. S4 completes the call

## Quick Start

### Using Docker Compose

```bash
# Clone the repository
git clone <repository>
cd ara-production-system

# Start all services
docker-compose up -d

# Initialize database
docker-compose exec ara-router ./router -init-db

# Add providers
docker-compose exec ara-router ./router provider add s1 --type inbound --host 192.168.1.10
docker-compose exec ara-router ./router provider add s3-1 --type intermediate --host 10.0.0.20
docker-compose exec ara-router ./router provider add s4-1 --type final --host 172.16.0.30

# Add DIDs
docker-compose exec ara-router ./router did add 18001234567 18001234568 --provider s3-1

# Create route
docker-compose exec ara-router ./router route add main s1 s3-1 s4-1

# Monitor system
docker-compose exec ara-router ./router monitor
# ara-production-system
