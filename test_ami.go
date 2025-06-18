package main

import (
    "context"
    "fmt"
    "log"
    "time"
    
    "github.com/spf13/viper"
    "github.com/hamzaKhattat/ara-production-system/internal/ami"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
)

func main() {
    // Initialize basic logging
    logConfig := logger.Config{
        Level:  "debug",
        Format: "text",
        Output: "stdout",
    }
    
    if err := logger.Init(logConfig); err != nil {
        log.Fatal("Failed to init logger:", err)
    }
    
    // Load config
    viper.SetConfigName("production")
    viper.SetConfigType("yaml")
    viper.AddConfigPath("./configs")
    viper.SetEnvPrefix("ARA_ROUTER")
    viper.AutomaticEnv()
    
    if err := viper.ReadInConfig(); err != nil {
        log.Printf("Config file error: %v", err)
        log.Println("Using environment variables or defaults...")
    }
    
    // Set some defaults
    viper.SetDefault("asterisk.ami.host", "localhost")
    viper.SetDefault("asterisk.ami.port", 5038)
    viper.SetDefault("asterisk.ami.username", "routerami")
    viper.SetDefault("asterisk.ami.password", "routerpass")
    
    // Debug: Print what we're trying to connect with
    host := viper.GetString("asterisk.ami.host")
    port := viper.GetInt("asterisk.ami.port")
    username := viper.GetString("asterisk.ami.username")
    password := viper.GetString("asterisk.ami.password")
    
    fmt.Printf("=== AMI Connection Debug ===\n")
    fmt.Printf("Host: %s\n", host)
    fmt.Printf("Port: %d\n", port)
    fmt.Printf("Username: %s\n", username)
    fmt.Printf("Password: %s\n", password)
    fmt.Printf("Config file used: %s\n", viper.ConfigFileUsed())
    
    // Create AMI config
    amiConfig := ami.Config{
        Host:              host,
        Port:              port,
        Username:          username,
        Password:          password,
        ReconnectInterval: 5 * time.Second,
        PingInterval:      30 * time.Second,
        ActionTimeout:     30 * time.Second,
        BufferSize:        1000,
    }
    
    fmt.Printf("\n=== Attempting AMI Connection ===\n")
    
    // Create AMI manager
    amiManager := ami.NewManager(amiConfig)
    
    // Try to connect
    ctx := context.Background()
    if err := amiManager.Connect(ctx); err != nil {
        log.Printf("AMI Connection failed: %v", err)
        
        // Try manual login test
        fmt.Printf("\n=== Manual Login Test ===\n")
        testManualLogin(host, port, username, password)
        return
    }
    
    fmt.Println("AMI Connected successfully!")
    
    // Test a simple action
    action := ami.Action{Action: "Ping"}
    response, err := amiManager.SendAction(action)
    if err != nil {
        log.Printf("Ping failed: %v", err)
    } else {
        fmt.Printf("Ping response: %v\n", response)
    }
    
    // Close connection
    amiManager.Close()
    fmt.Println("Connection closed.")
}

func testManualLogin(host string, port int, username, password string) {
    fmt.Printf("Testing manual TCP connection to %s:%d\n", host, port)
    
    conn, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", host, port), 10*time.Second)
    if err != nil {
        log.Printf("TCP connection failed: %v", err)
        return
    }
    defer conn.Close()
    
    fmt.Println("TCP connection successful")
    
    // Read banner
    reader := bufio.NewReader(conn)
    banner, err := reader.ReadString('\n')
    if err != nil {
        log.Printf("Failed to read banner: %v", err)
        return
    }
    fmt.Printf("Banner: %s", banner)
    
    // Send login
    loginAction := fmt.Sprintf("Action: Login\r\nUsername: %s\r\nSecret: %s\r\n\r\n", username, password)
    fmt.Printf("Sending login: %s", loginAction)
    
    _, err = conn.Write([]byte(loginAction))
    if err != nil {
        log.Printf("Failed to send login: %v", err)
        return
    }
    
    // Read response
    response, err := reader.ReadString('\n')
    if err != nil {
        log.Printf("Failed to read login response: %v", err)
        return
    }
    fmt.Printf("Login response: %s", response)
}
