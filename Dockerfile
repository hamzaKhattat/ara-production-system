# Build stage
FROM golang:1.21-alpine AS builder

RUN apk add --no-cache git make

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN make build-prod

# Runtime stage
FROM alpine:latest

RUN apk add --no-cache ca-certificates

WORKDIR /app

# Copy binary
COPY --from=builder /app/bin/router /app/router

# Copy configs
COPY --from=builder /app/configs /app/configs

# Copy migrations
COPY --from=builder /app/internal/db/migrations /app/migrations

# Create directories
RUN mkdir -p /var/log/asterisk-router /var/spool/asterisk/monitor

# Expose ports
EXPOSE 4573 8080 9090

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
   CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health/live || exit 1

ENTRYPOINT ["/app/router"]
CMD ["-config", "/app/configs/production.yaml", "-agi"]
