.PHONY: all build clean test docker run-dev run-prod init-db

# Variables
BINARY_NAME=router
BINARY_PATH=bin/$(BINARY_NAME)
DOCKER_IMAGE=asterisk-ara-router
VERSION=$(shell git describe --tags --always --dirty)
BUILD_TIME=$(shell date -u '+%Y-%m-%d_%H:%M:%S')
LDFLAGS=-ldflags "-X main.Version=$(VERSION) -X main.BuildTime=$(BUILD_TIME)"

# Default target
all: build

# Build the binary
build:
   @echo "Building $(BINARY_NAME)..."
   @mkdir -p bin
   @go build $(LDFLAGS) -o $(BINARY_PATH) ./cmd/router

# Build for production (optimized)
build-prod:
   @echo "Building production binary..."
   @mkdir -p bin
   @CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo $(LDFLAGS) -o $(BINARY_PATH) ./cmd/router

# Run tests
test:
   @echo "Running tests..."
   @go test -v -race -coverprofile=coverage.out ./...
   @go tool cover -html=coverage.out -o coverage.html

# Clean build artifacts
clean:
   @echo "Cleaning..."
   @rm -rf bin/
   @rm -f coverage.out coverage.html

# Run development server
run-dev: build
   @./$(BINARY_PATH) -config configs/development.yaml -agi -verbose

# Run production server
run-prod: build
   @./$(BINARY_PATH) -config configs/production.yaml -agi

# Initialize database
init-db: build
   @echo "Initializing database..."
   @./$(BINARY_PATH) -init-db

# Docker build
docker-build:
   @echo "Building Docker image..."
   @docker build -t $(DOCKER_IMAGE):$(VERSION) -t $(DOCKER_IMAGE):latest .

# Docker run
docker-run:
   @docker run -d \
   	--name ara-router \
   	-p 4573:4573 \
   	-p 8080:8080 \
   	-p 9090:9090 \
   	-e DB_HOST=mysql \
   	-e DB_PASS=secure_password \
   	--link mysql:mysql \
   	$(DOCKER_IMAGE):latest

# Generate mocks for testing
generate-mocks:
   @echo "Generating mocks..."
   @go generate ./...

# Lint code
lint:
   @echo "Running linter..."
   @golangci-lint run

# Format code
fmt:
   @echo "Formatting code..."
   @go fmt ./...

# Download dependencies
deps:
   @echo "Downloading dependencies..."
   @go mod download
   @go mod tidy

# Install the binary
install: build
   @echo "Installing $(BINARY_NAME)..."
   @cp $(BINARY_PATH) /usr/local/bin/

# Create release
release: clean build-prod
   @echo "Creating release..."
   @mkdir -p releases
   @tar -czf releases/$(BINARY_NAME)-$(VERSION)-linux-amd64.tar.gz -C bin $(BINARY_NAME)
   @echo "Release created: releases/$(BINARY_NAME)-$(VERSION)-linux-amd64.tar.gz"
