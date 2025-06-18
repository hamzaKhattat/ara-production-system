# Makefile for Asterisk ARA Router

.PHONY: all build clean test install run-agi init-db fix-permissions docker-build help

# Variables
BINARY_NAME=router
BINARY_PATH=bin/$(BINARY_NAME)
GO_FILES=$(shell find . -name '*.go' -type f)
CONFIG_FILE=/etc/asterisk-router/production.yaml
VERSION=$(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
BUILD_TIME=$(shell date +%Y%m%d-%H%M%S)

# Build flags
LDFLAGS=-ldflags "-s -w -X main.Version=$(VERSION) -X main.BuildTime=$(BUILD_TIME)"
BUILD_FLAGS=-trimpath

# Default target
all: build

# Build the binary
build:
	@echo "Building $(BINARY_NAME) $(VERSION)..."
	@mkdir -p bin
	go build $(BUILD_FLAGS) $(LDFLAGS) -o $(BINARY_PATH) ./cmd/router

# Clean build artifacts
clean:
	@echo "Cleaning..."
	@rm -rf bin/
	@go clean -cache

# Run tests
test:
	@echo "Running tests..."
	@go test -v -cover ./...

# Install to system
install: build
	@echo "Installing..."
	@sudo cp $(BINARY_PATH) /usr/local/bin/
	@sudo mkdir -p /etc/asterisk-router
	@sudo mkdir -p /var/log/ara-router
	@sudo mkdir -p /var/spool/asterisk/monitor
	@[ -f $(CONFIG_FILE) ] || sudo cp configs/production.yaml $(CONFIG_FILE)
	@sudo chown -R asterisk:asterisk /var/log/ara-router
	@sudo chown -R asterisk:asterisk /var/spool/asterisk/monitor
	@echo "Installation complete"

# Fix permissions
fix-permissions:
	@echo "Fixing permissions..."
	@sudo chown -R asterisk:asterisk /var/log/ara-router
	@sudo chown -R asterisk:asterisk /var/spool/asterisk/monitor
	@sudo chmod 755 /var/log/ara-router
	@sudo chmod 755 /var/spool/asterisk/monitor

# Run AGI server
run-agi: build
	@echo "Starting AGI server..."
	$(BINARY_PATH) -agi -config $(CONFIG_FILE)

# Initialize database
init-db: build
	@echo "Initializing database..."
	$(BINARY_PATH) -init-db -config $(CONFIG_FILE)

# Initialize database with flush
init-db-flush: build
	@echo "Flushing and initializing database..."
	$(BINARY_PATH) -init-db -flush -config $(CONFIG_FILE)

# Development helpers
dev-run:
	@go run ./cmd/router -agi -verbose

dev-cli:
	@go run ./cmd/router

# Docker commands
docker-build:
	@docker build -t ara-router:$(VERSION) .

docker-run:
	@docker-compose up -d

docker-logs:
	@docker-compose logs -f

# System service commands
service-install: install
	@echo "Installing systemd service..."
	@sudo cp scripts/ara-router.service /etc/systemd/system/
	@sudo systemctl daemon-reload
	@sudo systemctl enable ara-router
	@echo "Service installed. Run 'make service-start' to start."

service-start:
	@sudo systemctl start ara-router
	@echo "AGI server started"

service-stop:
	@sudo systemctl stop ara-router
	@echo "AGI server stopped"

service-status:
	@sudo systemctl status ara-router

service-logs:
	@sudo journalctl -u ara-router -f

# Quick CLI commands
providers:
	@$(BINARY_PATH) provider list

routes:
	@$(BINARY_PATH) route list

dids:
	@$(BINARY_PATH) did list

stats:
	@$(BINARY_PATH) stats

monitor:
	@$(BINARY_PATH) monitor

# Database commands
db-backup:
	@echo "Backing up database..."
	@mysqldump -u asterisk -pasterisk asterisk_ara > backup_$(BUILD_TIME).sql
	@echo "Backup saved to backup_$(BUILD_TIME).sql"

db-restore:
	@echo "Restoring database from $(FILE)..."
	@[ -f "$(FILE)" ] || (echo "Usage: make db-restore FILE=backup.sql" && exit 1)
	@mysql -u asterisk -pasterisk asterisk_ara < $(FILE)
	@echo "Database restored"

# Help
help:
	@echo "Asterisk ARA Router - Makefile Commands"
	@echo ""
	@echo "Build & Install:"
	@echo "  make build          - Build the binary"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make test           - Run tests"
	@echo "  make install        - Install to system"
	@echo ""
	@echo "Database:"
	@echo "  make init-db        - Initialize database"
	@echo "  make init-db-flush  - Flush and initialize database"
	@echo "  make db-backup      - Backup database"
	@echo "  make db-restore     - Restore database (FILE=backup.sql)"
	@echo ""
	@echo "Service:"
	@echo "  make run-agi        - Run AGI server"
	@echo "  make service-install - Install systemd service"
	@echo "  make service-start  - Start service"
	@echo "  make service-stop   - Stop service"
	@echo "  make service-status - Show service status"
	@echo "  make service-logs   - View service logs"
	@echo ""
	@echo "CLI Commands:"
	@echo "  make providers      - List providers"
	@echo "  make routes         - List routes"
	@echo "  make dids           - List DIDs"
	@echo "  make stats          - Show statistics"
	@echo "  make monitor        - Real-time monitoring"
	@echo ""
	@echo "Development:"
	@echo "  make dev-run        - Run AGI server in dev mode"
	@echo "  make dev-cli        - Run CLI in dev mode"
	@echo "  make docker-build   - Build Docker image"
	@echo "  make docker-run     - Run with docker-compose"
