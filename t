package main

import (
    "bufio"
    "context"
    "encoding/csv"
    "fmt"
    "os"
    "strings"
    "time"
    "database/sql"
    "github.com/spf13/viper"

    "github.com/fatih/color"
    "github.com/olekukonko/tablewriter"
    "github.com/spf13/cobra"
    "github.com/hamzaKhattat/ara-production-system/internal/models"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/internal/provider"
)

var (
    green  = color.New(color.FgGreen).SprintFunc()
    red    = color.New(color.FgRed).SprintFunc()
    yellow = color.New(color.FgYellow).SprintFunc()
    blue   = color.New(color.FgBlue).SprintFunc()
    bold   = color.New(color.Bold).SprintFunc()
)

func createProviderCommands() *cobra.Command {
    providerCmd := &cobra.Command{
        Use:   "provider",
        Short: "Manage providers",
        Long:  "Commands for managing external server providers (S1, S3, S4)",
    }
    
    // Add subcommands
    providerCmd.AddCommand(
        createProviderAddCommand(),
        createProviderListCommand(),
        createProviderDeleteCommand(),
        createProviderShowCommand(),
        createProviderTestCommand(),
    )
    
    return providerCmd
}

func createProviderAddCommand() *cobra.Command {
    var (
        providerType string
        host         string
        port         int
        username     string
        password     string
        authType     string
        codecs       []string
        maxChannels  int
        priority     int
        weight       int
    )
    
    cmd := &cobra.Command{
        Use:   "add <name>",
        Short: "Add a new provider",
        Args:  cobra.ExactArgs(1),
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            provider := &models.Provider{
                Name:               args[0],
                Type:               models.ProviderType(providerType),
                Host:               host,
                Port:               port,
                Username:           username,
                Password:           password,
                AuthType:           authType,
                Codecs:             codecs,
                MaxChannels:        maxChannels,
                Priority:           priority,
                Weight:             weight,
                Active:             true,
                HealthCheckEnabled: true,
            }
            
            if err := providerSvc.CreateProvider(ctx, provider); err != nil {
                return fmt.Errorf("failed to create provider: %v", err)
            }
            
            fmt.Printf("%s Provider '%s' created successfully\n", green("✓"), args[0])
            return nil
        },
    }
    
    cmd.Flags().StringVarP(&providerType, "type", "t", "", "Provider type (inbound/intermediate/final)")
    cmd.Flags().StringVar(&host, "host", "", "Provider host/IP address")
    cmd.Flags().IntVar(&port, "port", 5060, "Provider port")
    cmd.Flags().StringVarP(&username, "username", "u", "", "Authentication username")
    cmd.Flags().StringVarP(&password, "password", "p", "", "Authentication password")
    cmd.Flags().StringVar(&authType, "auth", "ip", "Authentication type (ip/credentials/both)")
    cmd.Flags().StringSliceVar(&codecs, "codecs", []string{"ulaw", "alaw"}, "Supported codecs")
    cmd.Flags().IntVar(&maxChannels, "max-channels", 0, "Maximum concurrent channels (0=unlimited)")
    cmd.Flags().IntVar(&priority, "priority", 10, "Provider priority")
    cmd.Flags().IntVar(&weight, "weight", 1, "Provider weight for load balancing")
    
    cmd.MarkFlagRequired("type")
    cmd.MarkFlagRequired("host")
    
    return cmd
}

func createProviderListCommand() *cobra.Command {
    var providerType string
    
    cmd := &cobra.Command{
        Use:   "list",
        Short: "List all providers",
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            filter := make(map[string]interface{})
            if providerType != "" {
                filter["type"] = providerType
            }
            
            providers, err := providerSvc.ListProviders(ctx, filter)
            if err != nil {
                return fmt.Errorf("failed to list providers: %v", err)
            }
            
            if len(providers) == 0 {
                fmt.Println("No providers found")
                return nil
            }
            
            table := tablewriter.NewWriter(os.Stdout)
            table.SetHeader([]string{"Name", "Type", "Host:Port", "Auth", "Priority", "Weight", "Channels", "Status"})
            table.SetBorder(false)
            table.SetAutoWrapText(false)
            
            for _, p := range providers {
                status := red("Inactive")
                if p.Active {
                    if p.HealthStatus == "healthy" {
                        status = green("Active")
                    } else {
                        status = yellow("Degraded")
                    }
                }
                
                channels := fmt.Sprintf("%d/%d", p.CurrentChannels, p.MaxChannels)
                if p.MaxChannels == 0 {
                    channels = fmt.Sprintf("%d/∞", p.CurrentChannels)
                }
                
                table.Append([]string{
                    p.Name,
                    string(p.Type),
                    fmt.Sprintf("%s:%d", p.Host, p.Port),
                    p.AuthType,
                    fmt.Sprintf("%d", p.Priority),
                    fmt.Sprintf("%d", p.Weight),
                    channels,
                    status,
                })
            }
            
            table.Render()
            return nil
        },
    }
    
    cmd.Flags().StringVarP(&providerType, "type", "t", "", "Filter by provider type")
    
    return cmd
}

func createProviderDeleteCommand() *cobra.Command {
    return &cobra.Command{
        Use:   "delete <name>",
        Short: "Delete a provider",
        Args:  cobra.ExactArgs(1),
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            // Confirm deletion
            fmt.Printf("Are you sure you want to delete provider '%s'? [y/N]: ", args[0])
            reader := bufio.NewReader(os.Stdin)
            response, _ := reader.ReadString('\n')
            response = strings.TrimSpace(strings.ToLower(response))
            
            if response != "y" && response != "yes" {
                fmt.Println("Deletion cancelled")
                return nil
            }
            
            if err := providerSvc.DeleteProvider(ctx, args[0]); err != nil {
                return fmt.Errorf("failed to delete provider: %v", err)
            }
            
            fmt.Printf("%s Provider '%s' deleted successfully\n", green("✓"), args[0])
            return nil
        },
    }
}

func createProviderShowCommand() *cobra.Command {
    return &cobra.Command{
        Use:   "show <name>",
        Short: "Show detailed provider information",
        Args:  cobra.ExactArgs(1),
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            provider, err := providerSvc.GetProvider(ctx, args[0])
            if err != nil {
                return fmt.Errorf("failed to get provider: %v", err)
            }
            
            fmt.Printf("\n%s\n", bold("Provider Details"))
            fmt.Printf("Name:             %s\n", provider.Name)
            fmt.Printf("Type:             %s\n", provider.Type)
            fmt.Printf("Host:             %s:%d\n", provider.Host, provider.Port)
            fmt.Printf("Transport:        %s\n", provider.Transport)
            fmt.Printf("Auth Type:        %s\n", provider.AuthType)
            if provider.Username != "" {
                fmt.Printf("Username:         %s\n", provider.Username)
            }
            fmt.Printf("Codecs:           %s\n", strings.Join(provider.Codecs, ", "))
            fmt.Printf("Priority:         %d\n", provider.Priority)
            fmt.Printf("Weight:           %d\n", provider.Weight)
            fmt.Printf("Max Channels:     %d\n", provider.MaxChannels)
            fmt.Printf("Current Channels: %d\n", provider.CurrentChannels)
            fmt.Printf("Cost/Min:         $%.4f\n", provider.CostPerMinute)
            fmt.Printf("Status:           %s\n", formatStatus(provider.Active, provider.HealthStatus))
            fmt.Printf("Health Check:     %s\n", formatBool(provider.HealthCheckEnabled))
            if provider.LastHealthCheck != nil {
                fmt.Printf("Last Check:       %s\n", provider.LastHealthCheck.Format(time.RFC3339))
            }
            fmt.Printf("Created:          %s\n", provider.CreatedAt.Format(time.RFC3339))
            fmt.Printf("Updated:          %s\n", provider.UpdatedAt.Format(time.RFC3339))
            
            // Get current stats from router
            stats := routerSvc.GetLoadBalancer().GetProviderStats()
            if stat, exists := stats[provider.Name]; exists {
                fmt.Printf("\n%s\n", bold("Current Statistics"))
                fmt.Printf("Active Calls:     %d\n", stat.ActiveCalls)
                fmt.Printf("Total Calls:      %d\n", stat.TotalCalls)
                fmt.Printf("Failed Calls:     %d\n", stat.FailedCalls)
                fmt.Printf("Success Rate:     %.2f%%\n", stat.SuccessRate)
                fmt.Printf("Avg Call Time:    %.2f seconds\n", stat.AvgCallDuration)
                fmt.Printf("Avg Response:     %d ms\n", stat.AvgResponseTime)
                fmt.Printf("Health:           %s\n", formatBool(stat.IsHealthy))
            }
            
            return nil
        },
    }
}

func createProviderTestCommand() *cobra.Command {
    return &cobra.Command{
        Use:   "test <name>",
        Short: "Test provider connectivity",
        Args:  cobra.ExactArgs(1),
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            fmt.Printf("Testing provider '%s'...\n", args[0])
            
            result, err := providerSvc.TestProvider(ctx, args[0])
            if err != nil {
                return fmt.Errorf("failed to test provider: %v", err)
            }
            
            for testName, test := range result.Tests {
                status := red("✗")
                if test.Success {
                    status = green("✓")
                }
                fmt.Printf("%s %s: %s (%.2fms)\n", status, testName, test.Message, test.Duration.Seconds()*1000)
            }
            
            return nil
        },
    }
}

func createDIDCommands() *cobra.Command {
    didCmd := &cobra.Command{
        Use:   "did",
        Short: "Manage DIDs (phone numbers)",
        Long:  "Commands for managing DID pool for dynamic allocation",
    }
    
    didCmd.AddCommand(
        createDIDAddCommand(),
        createDIDListCommand(),
        createDIDDeleteCommand(),
        createDIDReleaseCommand(),
    )
    
    return didCmd
}

func createDIDAddCommand() *cobra.Command {
    var (
        provider string
        csvFile  string
    )
    
    cmd := &cobra.Command{
        Use:   "add [numbers...]",
        Short: "Add DIDs to the pool",
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            var numbers []string
            
            if csvFile != "" {
                // Read from CSV file
                file, err := os.Open(csvFile)
                if err != nil {
                    return fmt.Errorf("failed to open CSV file: %v", err)
                }
                defer file.Close()
                
                reader := csv.NewReader(file)
                records, err := reader.ReadAll()
                if err != nil {
                    return fmt.Errorf("failed to read CSV: %v", err)
                }
                
                for i, record := range records {
                    if i == 0 && strings.ToLower(record[0]) == "number" {
                        continue // Skip header
                    }
                    if len(record) > 0 {
                        numbers = append(numbers, record[0])
                    }
                }
            } else if len(args) > 0 {
                numbers = args
            } else {
                return fmt.Errorf("no DIDs specified")
            }
            
            // Add DIDs to database
            added := 0
            for _, number := range numbers {
                did := &models.DID{
                    Number:       number,
                    ProviderName: provider,
                    InUse:        false,
                }
                
                if err := addDID(ctx, did); err != nil {
                    fmt.Printf("%s Failed to add %s: %v\n", red("✗"), number, err)
                } else {
                    added++
                }
            }
            
            fmt.Printf("%s Added %d DIDs successfully\n", green("✓"), added)
            return nil
        },
    }
    
    cmd.Flags().StringVarP(&provider, "provider", "p", "", "Associated provider name")
    cmd.Flags().StringVarP(&csvFile, "file", "f", "", "CSV file containing DIDs")
    
    return cmd
}

func createDIDListCommand() *cobra.Command {
    var (
        showAll  bool
        provider string
    )
    
    cmd := &cobra.Command{
        Use:   "list",
        Short: "List DIDs in the pool",
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            dids, err := listDIDs(ctx, provider, !showAll)
            if err != nil {
                return fmt.Errorf("failed to list DIDs: %v", err)
            }
            
            if len(dids) == 0 {
                fmt.Println("No DIDs found")
                return nil
            }
            
            table := tablewriter.NewWriter(os.Stdout)
            table.SetHeader([]string{"Number", "Provider", "Status", "Destination", "Usage Count", "Last Used"})
            table.SetBorder(false)
            
            for _, did := range dids {
                status := green("Available")
                destination := "-"
                if did.InUse {
                    status = yellow("In Use")
                    destination = did.Destination
                }
                
                lastUsed := "-"
                if did.LastUsedAt != nil {
                    lastUsed = did.LastUsedAt.Format("2006-01-02 15:04:05")
                }
                
                table.Append([]string{
                    did.Number,
                    did.ProviderName,
                    status,
                    destination,
                    fmt.Sprintf("%d", did.UsageCount),
                    lastUsed,
                })
            }
            
            table.Render()
            
            // Show summary
            var available, inUse int
            for _, did := range dids {
                if did.InUse {
                    inUse++
                } else {
                    available++
                }
            }
            
            fmt.Printf("\nTotal: %d | Available: %s | In Use: %s\n",
                len(dids),
                green(fmt.Sprintf("%d", available)),
                yellow(fmt.Sprintf("%d", inUse)))
            
            return nil
        },
    }
    
    cmd.Flags().BoolVarP(&showAll, "all", "a", false, "Show all DIDs (including in use)")
    cmd.Flags().StringVarP(&provider, "provider", "p", "", "Filter by provider")
    
    return cmd
}

func createDIDDeleteCommand() *cobra.Command {
    return &cobra.Command{
        Use:   "delete <number>",
        Short: "Delete a DID from the pool",
        Args:  cobra.ExactArgs(1),
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            // Check if DID is in use
            did, err := getDID(ctx, args[0])
            if err != nil {
                return fmt.Errorf("failed to get DID: %v", err)
            }
            
            if did.InUse {
                return fmt.Errorf("cannot delete DID %s: currently in use", args[0])
            }
            
            if err := deleteDID(ctx, args[0]); err != nil {
                return fmt.Errorf("failed to delete DID: %v", err)
            }
            
            fmt.Printf("%s DID '%s' deleted successfully\n", green("✓"), args[0])
            return nil
        },
    }
}

func createDIDReleaseCommand() *cobra.Command {
    return &cobra.Command{
        Use:   "release <number>",
        Short: "Manually release a DID",
        Args:  cobra.ExactArgs(1),
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            if err := releaseDID(ctx, args[0]); err != nil {
                return fmt.Errorf("failed to release DID: %v", err)
            }
            
            fmt.Printf("%s DID '%s' released successfully\n", green("✓"), args[0])
            return nil
        },
    }
}

func createRouteCommands() *cobra.Command {
    routeCmd := &cobra.Command{
        Use:   "route",
        Short: "Manage routing rules",
        Long:  "Commands for managing call routing between providers",
    }
    
    routeCmd.AddCommand(
        createRouteAddCommand(),
        createRouteListCommand(),
        createRouteDeleteCommand(),
        createRouteShowCommand(),
    )
    
    return routeCmd
}

func createRouteAddCommand() *cobra.Command {
    var (
        mode        string
        priority    int
        weight      int
        maxCalls    int
        description string
        useGroups   bool
    )
    
    cmd := &cobra.Command{
        Use:   "add <name> <inbound> <intermediate> <final>",
        Short: "Add a new route",
        Long:  "Add a new route. You can use provider names or group names (with --groups flag)",
        Example: `  # Route with individual providers
  router route add main s1 s3-provider1 s4-termination1
  
  # Route with groups
  router route add morocco-route inbound morocco-group panama-group --groups
  
  # Mixed providers and groups
  router route add mixed s1 intermediate-group s4-term1 --groups`,
        Args:  cobra.ExactArgs(4),
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            route := &models.ProviderRoute{
                Name:                 args[0],
                InboundProvider:      args[1],
                IntermediateProvider: args[2],
                FinalProvider:        args[3],
                Description:          description,
                LoadBalanceMode:      models.LoadBalanceMode(mode),
                Priority:             priority,
                Weight:               weight,
                MaxConcurrentCalls:   maxCalls,
                Enabled:              true,
            }
            
            // Check if using groups
            if useGroups {
                groupService := provider.NewGroupService(database.DB, cache)
                
                // Check each provider/group
                if _, err := groupService.GetGroup(ctx, args[1]); err == nil {
                    route.InboundIsGroup = true
                }
                if _, err := groupService.GetGroup(ctx, args[2]); err == nil {
                    route.IntermediateIsGroup = true
                }
                if _, err := groupService.GetGroup(ctx, args[3]); err == nil {
                    route.FinalIsGroup = true
                }
            }
            
            if err := createRoute(ctx, route); err != nil {
                return fmt.Errorf("failed to create route: %v", err)
            }
            
            fmt.Printf("%s Route '%s' created successfully\n", green("✓"), args[0])
            
            // Show route details
            fmt.Printf("\nRoute Configuration:\n")
            fmt.Printf("  Inbound:      %s %s\n", args[1], formatGroupIndicator(route.InboundIsGroup))
            fmt.Printf("  Intermediate: %s %s\n", args[2], formatGroupIndicator(route.IntermediateIsGroup))
            fmt.Printf("  Final:        %s %s\n", args[3], formatGroupIndicator(route.FinalIsGroup))
            fmt.Printf("  Load Balance: %s\n", mode)
            
            return nil
        },
    }
    
    cmd.Flags().StringVar(&mode, "mode", "round_robin", "Load balance mode")
    cmd.Flags().IntVar(&priority, "priority", 10, "Route priority")
    cmd.Flags().IntVar(&weight, "weight", 1, "Route weight")
    cmd.Flags().IntVar(&maxCalls, "max-calls", 0, "Maximum concurrent calls")
    cmd.Flags().StringVarP(&description, "description", "d", "", "Route description")
    cmd.Flags().BoolVar(&useGroups, "groups", false, "Enable group support for this route")
    
    return cmd
}

func formatGroupIndicator(isGroup bool) string {
    if isGroup {
        return blue("[GROUP]")
    }
    return ""
}

func createRouteListCommand() *cobra.Command {
    return &cobra.Command{
        Use:   "list",
        Short: "List all routes",
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            routes, err := listRoutes(ctx)
            if err != nil {
                return fmt.Errorf("failed to list routes: %v", err)
            }
            
            if len(routes) == 0 {
                fmt.Println("No routes found")
                return nil
            }
            
            table := tablewriter.NewWriter(os.Stdout)
            table.SetHeader([]string{"Name", "Inbound", "Intermediate", "Final", "Mode", "Priority", "Calls", "Status"})
            table.SetBorder(false)
            
            for _, r := range routes {
                status := green("Enabled")
                if !r.Enabled {
                    status = red("Disabled")
                }
                
                calls := fmt.Sprintf("%d", r.CurrentCalls)
                if r.MaxConcurrentCalls > 0 {
                    calls = fmt.Sprintf("%d/%d", r.CurrentCalls, r.MaxConcurrentCalls)
                }
                
                // Format provider names with group indicators
                inbound := r.InboundProvider
                if r.InboundIsGroup {
                    inbound = fmt.Sprintf("%s %s", r.InboundProvider, blue("[G]"))
                }
                
                intermediate := r.IntermediateProvider
                if r.IntermediateIsGroup {
                    intermediate = fmt.Sprintf("%s %s", r.IntermediateProvider, blue("[G]"))
                }
                
                final := r.FinalProvider
                if r.FinalIsGroup {
                    final = fmt.Sprintf("%s %s", r.FinalProvider, blue("[G]"))
                }
                
                table.Append([]string{
                    r.Name,
                    inbound,
                    intermediate,
                    final,
                    string(r.LoadBalanceMode),
                    fmt.Sprintf("%d", r.Priority),
                    calls,
                    status,
                })
            }
            
            table.Render()
            return nil
        },
    }
}

func createRouteDeleteCommand() *cobra.Command {
    return &cobra.Command{
        Use:   "delete <name>",
        Short: "Delete a route",
        Args:  cobra.ExactArgs(1),
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            // Confirm deletion
            fmt.Printf("Are you sure you want to delete route '%s'? [y/N]: ", args[0])
            reader := bufio.NewReader(os.Stdin)
            response, _ := reader.ReadString('\n')
            response = strings.TrimSpace(strings.ToLower(response))
            
            if response != "y" && response != "yes" {
                fmt.Println("Deletion cancelled")
                return nil
            }
            
            if err := deleteRoute(ctx, args[0]); err != nil {
                return fmt.Errorf("failed to delete route: %v", err)
            }
            
            fmt.Printf("%s Route '%s' deleted successfully\n", green("✓"), args[0])
            return nil
        },
    }
}

func createRouteShowCommand() *cobra.Command {
    return &cobra.Command{
        Use:   "show <name>",
        Short: "Show detailed route information",
        Args:  cobra.ExactArgs(1),
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            route, err := getRoute(ctx, args[0])
            if err != nil {
                return fmt.Errorf("failed to get route: %v", err)
            }
            
            fmt.Printf("\n%s\n", bold("Route Details"))
            fmt.Printf("Name:               %s\n", route.Name)
            if route.Description != "" {
                fmt.Printf("Description:        %s\n", route.Description)
            }
            
            // Show providers with group indicators
            fmt.Printf("Inbound Provider:   %s %s\n", route.InboundProvider, formatGroupIndicator(route.InboundIsGroup))
            fmt.Printf("Intermediate:       %s %s\n", route.IntermediateProvider, formatGroupIndicator(route.IntermediateIsGroup))
            fmt.Printf("Final Provider:     %s %s\n", route.FinalProvider, formatGroupIndicator(route.FinalIsGroup))
            
            fmt.Printf("Load Balance Mode:  %s\n", route.LoadBalanceMode)
            fmt.Printf("Priority:           %d\n", route.Priority)
            fmt.Printf("Weight:             %d\n", route.Weight)
            fmt.Printf("Max Concurrent:     %d\n", route.MaxConcurrentCalls)
            fmt.Printf("Current Calls:      %d\n", route.CurrentCalls)
            fmt.Printf("Status:             %s\n", formatBool(route.Enabled))
            if len(route.FailoverRoutes) > 0 {
                fmt.Printf("Failover Routes:    %s\n", strings.Join(route.FailoverRoutes, ", "))
            }
            fmt.Printf("Created:            %s\n", route.CreatedAt.Format(time.RFC3339))
            fmt.Printf("Updated:            %s\n", route.UpdatedAt.Format(time.RFC3339))
            
            return nil
        },
    }
}

func createStatsCommand() *cobra.Command {
    var (
        showProviders bool
        showCalls     bool
        showDIDs      bool
    )
    
    cmd := &cobra.Command{
        Use:   "stats",
        Short: "Show system statistics",
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            // If no specific flag, show all
            if !showProviders && !showCalls && !showDIDs {
                showProviders = true
                showCalls = true
                showDIDs = true
            }
            
            stats, err := routerSvc.GetStatistics(ctx)
            if err != nil {
                return fmt.Errorf("failed to get statistics: %v", err)
            }
            
            if showCalls {
                fmt.Printf("\n%s\n", bold("Call Statistics"))
                fmt.Printf("Active Calls: %s\n", yellow(fmt.Sprintf("%d", stats["active_calls"])))
                
                if routes, ok := stats["routes"].([]map[string]interface{}); ok {
                    fmt.Printf("\n%s\n", bold("Routes"))
                    for _, route := range routes {
                        fmt.Printf("  %s: %d/%d (%.1f%%)\n",
                            route["name"],
                            route["current"],
                            route["max"],
                            route["utilization"])
                    }
                }
            }
            
            if showDIDs {
                fmt.Printf("\n%s\n", bold("DID Pool"))
                fmt.Printf("Total DIDs:      %d\n", stats["total_dids"])
                fmt.Printf("Used:            %s\n", yellow(fmt.Sprintf("%d", stats["used_dids"])))
                fmt.Printf("Available:       %s\n", green(fmt.Sprintf("%d", stats["available_dids"])))
                fmt.Printf("Utilization:     %.1f%%\n", stats["did_utilization"])
            }
            
            if showProviders {
                fmt.Printf("\n%s\n", bold("Provider Statistics"))
                providerStats := routerSvc.GetLoadBalancer().GetProviderStats()
                
                table := tablewriter.NewWriter(os.Stdout)
                table.SetHeader([]string{"Provider", "Active", "Total", "Failed", "Success Rate", "Avg Duration"})
                table.SetBorder(false)
                
                for name, stat := range providerStats {
                    table.Append([]string{
                        name,
                        fmt.Sprintf("%d", stat.ActiveCalls),
                        fmt.Sprintf("%d", stat.TotalCalls),
                        fmt.Sprintf("%d", stat.FailedCalls),
                        fmt.Sprintf("%.1f%%", stat.SuccessRate),
                        fmt.Sprintf("%.1fs", stat.AvgCallDuration),
                    })
                }
                
                table.Render()
            }
            
            return nil
        },
    }
    
    cmd.Flags().BoolVar(&showProviders, "providers", false, "Show provider statistics")
    cmd.Flags().BoolVar(&showCalls, "calls", false, "Show call statistics")
    cmd.Flags().BoolVar(&showDIDs, "dids", false, "Show DID statistics")
    
    return cmd
}

func createLoadBalancerCommand() *cobra.Command {
    return &cobra.Command{
        Use:   "lb",
        Short: "Show load balancer status",
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            stats := routerSvc.GetLoadBalancer().GetProviderStats()
            
            fmt.Printf("\n%s\n", bold("Load Balancer Status"))
            
            // Group by provider type
            types := map[string][]*models.ProviderStats{
                "inbound":      {},
                "intermediate": {},
                "final":        {},
            }
            
            for name, stat := range stats {
                provider, err := providerSvc.GetProvider(ctx, name)
                if err == nil {
                    types[string(provider.Type)] = append(types[string(provider.Type)], stat)
                }
            }
            
            for providerType, providers := range types {
                if len(providers) == 0 {
                    continue
                }
                
                fmt.Printf("\n%s Providers:\n", bold(strings.Title(providerType)))
                
                for _, stat := range providers {
                    health := green("Healthy")
                    if !stat.IsHealthy {
                        health = red("Unhealthy")
                    }
                    
                    fmt.Printf("  %s:\n", stat.ProviderName)
                    fmt.Printf("    Status:       %s\n", health)
                    fmt.Printf("    Active Calls: %d\n", stat.ActiveCalls)
                    fmt.Printf("    Success Rate: %.1f%%\n", stat.SuccessRate)
                    fmt.Printf("    Response:     %dms\n", stat.AvgResponseTime)
                }
            }
            
            return nil
        },
    }
}

func createCallsCommand() *cobra.Command {
    return &cobra.Command{
        Use:   "calls",
        Short: "Show active calls",
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            calls, err := getActiveCalls(ctx)
            if err != nil {
                return fmt.Errorf("failed to get active calls: %v", err)
            }
            
            if len(calls) == 0 {
                fmt.Println("No active calls")
                return nil
            }
            
            table := tablewriter.NewWriter(os.Stdout)
            table.SetHeader([]string{"Call ID", "ANI", "DNIS", "DID", "Route", "Status", "Duration"})
            table.SetBorder(false)
            
            for _, call := range calls {
                duration := time.Since(call.StartTime)
                
                table.Append([]string{
                    call.CallID[:8] + "...",
                    call.OriginalANI,
                    call.OriginalDNIS,
                    call.AssignedDID,
                    call.RouteName,
                    string(call.Status),
                    fmt.Sprintf("%02d:%02d", int(duration.Minutes()), int(duration.Seconds())%60),
                })
            }
            
            table.Render()
            
            fmt.Printf("\nTotal active calls: %d\n", len(calls))
            
            return nil
        },
    }
}

func createMonitorCommand() *cobra.Command {
    return &cobra.Command{
        Use:   "monitor",
        Short: "Real-time system monitoring",
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            fmt.Println("Starting real-time monitor... Press Ctrl+C to exit")
            
            ticker := time.NewTicker(2 * time.Second)
            defer ticker.Stop()
            
            // Clear screen
            fmt.Print("\033[H\033[2J")
            
            for {
                select {
                case <-ticker.C:
                    // Clear screen
                    fmt.Print("\033[H\033[2J")
                    
                    // Get current stats
                    stats, _ := routerSvc.GetStatistics(ctx)
                    calls, _ := getActiveCalls(ctx)
                    providerStats := routerSvc.GetLoadBalancer().GetProviderStats()
                    
                    // Display header
                    fmt.Printf("%s %s\n\n", bold("Asterisk ARA Router Monitor"), time.Now().Format("15:04:05"))
                    
                    // Active calls summary
                    fmt.Printf("%s Active Calls: %s\n", bold("📞"), yellow(fmt.Sprintf("%d", len(calls))))
                    
                    // DID utilization
                    if didUtil, ok := stats["did_utilization"].(float64); ok {
                        fmt.Printf("%s DID Utilization: %.1f%%\n", bold("📱"), didUtil)
                    }
                    
                    // Provider health
                    fmt.Printf("\n%s\n", bold("Provider Health:"))
                    for name, stat := range providerStats {
                        status := green("●")
                        if !stat.IsHealthy {
                            status = red("●")
                        }
                        fmt.Printf("  %s %s - Active: %d, Success: %.1f%%\n",
                            status, name, stat.ActiveCalls, stat.SuccessRate)
                    }
                    
                    // Recent calls
                    if len(calls) > 0 {
                        fmt.Printf("\n%s\n", bold("Recent Calls:"))
                        for i, call := range calls {
                            if i >= 5 {
                                break
                            }
                            duration := time.Since(call.StartTime)
                            fmt.Printf("  %s → %s [%s] %02d:%02d\n",
                                call.OriginalANI, call.OriginalDNIS,
                                call.Status,
                                int(duration.Minutes()), int(duration.Seconds())%60)
                        }
                    }
                    
                case <-cmd.Context().Done():
                    return nil
                }
            }
        },
    }
}

// Helper functions
func initializeForCLI(ctx context.Context) error {
    if err := loadConfig(); err != nil {
        return fmt.Errorf("failed to load config: %v", err)
    }
    
    // Initialize logger
    logConfig := logger.Config{
        Level:  viper.GetString("monitoring.logging.level"),
        Format: viper.GetString("monitoring.logging.format"),
        Output: viper.GetString("monitoring.logging.output"),
        File: logger.FileConfig{
            Enabled:    viper.GetBool("monitoring.logging.file.enabled"),
            Path:       viper.GetString("monitoring.logging.file.path"),
            MaxSize:    viper.GetInt("monitoring.logging.file.max_size"),
            MaxBackups: viper.GetInt("monitoring.logging.file.max_backups"),
            MaxAge:     viper.GetInt("monitoring.logging.file.max_age"),
            Compress:   viper.GetBool("monitoring.logging.file.compress"),
        },
    }
    
    // Set defaults if not configured
    if logConfig.Level == "" {
        logConfig.Level = "info"
    }
    if logConfig.Format == "" {
        logConfig.Format = "text"  // Use text format for CLI
    }
    
    if err := logger.Init(logConfig); err != nil {
        return fmt.Errorf("failed to initialize logger: %v", err)
    }
    
    if err := initializeDatabase(ctx); err != nil {
        return fmt.Errorf("failed to initialize database: %v", err)
    }
    
    return nil
}

func formatStatus(active bool, healthStatus string) string {
    if !active {
        return red("Inactive")
    }
    
    switch healthStatus {
    case "healthy":
        return green("Active")
    case "degraded":
        return yellow("Degraded")
    default:
        return red("Unhealthy")
    }
}

func formatBool(b bool) string {
    if b {
        return green("Yes")
    }
    return red("No")
}

// Database helper functions
func addDID(ctx context.Context, did *models.DID) error {
    query := `
        INSERT INTO dids (number, provider_name, in_use, monthly_cost, per_minute_cost)
        VALUES (?, ?, ?, ?, ?)`
    
    _, err := database.ExecContext(ctx, query,
        did.Number, did.ProviderName, did.InUse,
        did.MonthlyCost, did.PerMinuteCost)
    
    return err
}

func listDIDs(ctx context.Context, provider string, availableOnly bool) ([]*models.DID, error) {
    query := `
        SELECT id, number, provider_name, in_use, destination,
               last_used_at, usage_count, created_at, updated_at
        FROM dids
        WHERE 1=1`
    
    var args []interface{}
    
    if provider != "" {
        query += " AND provider_name = ?"
        args = append(args, provider)
    }
    
    if availableOnly {
        query += " AND in_use = 0"
    }
    
    query += " ORDER BY number"
    
    rows, err := database.QueryContext(ctx, query, args...)
    if err != nil {
        return nil, err
    }
    defer rows.Close()
    
    var dids []*models.DID
    
    for rows.Next() {
        var did models.DID
        var destination sql.NullString
        
        err := rows.Scan(
            &did.ID, &did.Number, &did.ProviderName, &did.InUse,
            &destination, &did.LastUsedAt, &did.UsageCount,
            &did.CreatedAt, &did.UpdatedAt,
        )
        
        if err != nil {
            logger.WithContext(ctx).WithError(err).Warn("Failed to scan DID")
            continue
        }
        
        if destination.Valid {
            did.Destination = destination.String
        }
        
        dids = append(dids, &did)
    }
    
    return dids, nil
}

func getDID(ctx context.Context, number string) (*models.DID, error) {
    var did models.DID
    var destination sql.NullString
    
    query := `
        SELECT id, number, provider_name, in_use, destination,
               last_used_at, usage_count, created_at, updated_at
        FROM dids
        WHERE number = ?`
    
    err := database.QueryRowContext(ctx, query, number).Scan(
        &did.ID, &did.Number, &did.ProviderName, &did.InUse,
        &destination, &did.LastUsedAt, &did.UsageCount,
        &did.CreatedAt, &did.UpdatedAt,
    )
    
    if err != nil {
        return nil, err
    }
    
    if destination.Valid {
        did.Destination = destination.String
    }
    
    return &did, nil
}

func deleteDID(ctx context.Context, number string) error {
    _, err := database.ExecContext(ctx, "DELETE FROM dids WHERE number = ?", number)
    return err
}

func releaseDID(ctx context.Context, number string) error {
    query := `
        UPDATE dids 
        SET in_use = 0, destination = NULL, released_at = NOW()
        WHERE number = ?`
    
    _, err := database.ExecContext(ctx, query, number)
    return err
}

func createRoute(ctx context.Context, route *models.ProviderRoute) error {
    query := `
        INSERT INTO provider_routes (
            name, description, inbound_provider, intermediate_provider,
            final_provider, inbound_is_group, intermediate_is_group,
            final_is_group, load_balance_mode, priority, weight,
            max_concurrent_calls, enabled
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    
    _, err := database.ExecContext(ctx, query,
        route.Name, route.Description, route.InboundProvider,
        route.IntermediateProvider, route.FinalProvider,
        route.InboundIsGroup, route.IntermediateIsGroup, route.FinalIsGroup,
        route.LoadBalanceMode, route.Priority, route.Weight,
        route.MaxConcurrentCalls, route.Enabled)
    
    return err
}

func listRoutes(ctx context.Context) ([]*models.ProviderRoute, error) {
    query := `
        SELECT id, name, COALESCE(description, ''), inbound_provider, intermediate_provider,
               final_provider, COALESCE(inbound_is_group, 0), COALESCE(intermediate_is_group, 0),
               COALESCE(final_is_group, 0), load_balance_mode, priority, weight,
               max_concurrent_calls, current_calls, enabled,
               created_at, updated_at
        FROM provider_routes
        ORDER BY priority DESC, name`
    
    rows, err := database.QueryContext(ctx, query)
    if err != nil {
        return nil, err
    }
    defer rows.Close()
    
    var routes []*models.ProviderRoute
    
    for rows.Next() {
        var route models.ProviderRoute
        
        err := rows.Scan(
            &route.ID, &route.Name, &route.Description,
            &route.InboundProvider, &route.IntermediateProvider,
            &route.FinalProvider, &route.InboundIsGroup,
            &route.IntermediateIsGroup, &route.FinalIsGroup,
            &route.LoadBalanceMode, &route.Priority, &route.Weight,
            &route.MaxConcurrentCalls, &route.CurrentCalls,
            &route.Enabled, &route.CreatedAt, &route.UpdatedAt,
        )
        
        if err != nil {
            logger.WithContext(ctx).WithError(err).Warn("Failed to scan route")
            continue
        }
        
        routes = append(routes, &route)
    }
    
    return routes, nil
}

func getRoute(ctx context.Context, name string) (*models.ProviderRoute, error) {
    var route models.ProviderRoute
    
    query := `
        SELECT id, name, COALESCE(description, ''), inbound_provider, intermediate_provider,
               final_provider, COALESCE(inbound_is_group, 0), COALESCE(intermediate_is_group, 0),
               COALESCE(final_is_group, 0), load_balance_mode, priority, weight,
               max_concurrent_calls, current_calls, enabled,
               COALESCE(failover_routes, '[]'), COALESCE(routing_rules, '{}'), 
               COALESCE(metadata, '{}'), created_at, updated_at
        FROM provider_routes
        WHERE name = ?`
    
    err := database.QueryRowContext(ctx, query, name).Scan(
        &route.ID, &route.Name, &route.Description,
        &route.InboundProvider, &route.IntermediateProvider,
        &route.FinalProvider, &route.InboundIsGroup,
        &route.IntermediateIsGroup, &route.FinalIsGroup,
        &route.LoadBalanceMode, &route.Priority, &route.Weight,
        &route.MaxConcurrentCalls, &route.CurrentCalls,
        &route.Enabled, &route.FailoverRoutes,
        &route.RoutingRules, &route.Metadata,
        &route.CreatedAt, &route.UpdatedAt,
    )
    
    if err != nil {
        return nil, err
    }
    
    return &route, nil
}

func deleteRoute(ctx context.Context, name string) error {
    _, err := database.ExecContext(ctx, "DELETE FROM provider_routes WHERE name = ?", name)
    return err
}

func getActiveCalls(ctx context.Context) ([]*models.CallRecord, error) {
    query := `
        SELECT call_id, original_ani, original_dnis, 
               COALESCE(transformed_ani, ''), COALESCE(assigned_did, ''),
               inbound_provider, intermediate_provider, final_provider, 
               COALESCE(route_name, ''), status, COALESCE(current_step, ''),
               start_time, answer_time
        FROM call_records
        WHERE status IN ('INITIATED', 'ACTIVE', 'RETURNED_FROM_S3', 'ROUTING_TO_S4')
        ORDER BY start_time DESC`
    
    rows, err := database.QueryContext(ctx, query)
    if err != nil {
        return nil, err
    }
    defer rows.Close()
    
    var calls []*models.CallRecord
    
    for rows.Next() {
        var call models.CallRecord
        
        err := rows.Scan(
            &call.CallID, &call.OriginalANI, &call.OriginalDNIS,
            &call.TransformedANI, &call.AssignedDID,
            &call.InboundProvider, &call.IntermediateProvider,
            &call.FinalProvider, &call.RouteName,
            &call.Status, &call.CurrentStep,
            &call.StartTime, &call.AnswerTime,
        )
        
        if err != nil {
            logger.WithContext(ctx).WithError(err).Warn("Failed to scan call record")
            continue
        }
        
        calls = append(calls, &call)
    }
    
    return calls, nil
}
package main

import (
    "context"
    "fmt"
    "time"
    
    "github.com/spf13/viper"
    "github.com/hamzaKhattat/ara-production-system/internal/ami"
    "github.com/hamzaKhattat/ara-production-system/internal/ara"
    "github.com/hamzaKhattat/ara-production-system/internal/db"
    "github.com/hamzaKhattat/ara-production-system/internal/health"
    "github.com/hamzaKhattat/ara-production-system/internal/metrics"
    "github.com/hamzaKhattat/ara-production-system/internal/provider"
    "github.com/hamzaKhattat/ara-production-system/internal/router"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
)

func loadConfig() error {
    if configFile != "" {
        viper.SetConfigFile(configFile)
    } else {
        viper.SetConfigName("production")
        viper.SetConfigType("yaml")
        viper.AddConfigPath("./configs")
        viper.AddConfigPath("/etc/asterisk-router")
    }
    
    // Environment variables
    viper.SetEnvPrefix("ARA_ROUTER")
    viper.AutomaticEnv()
    
    // Defaults
    setDefaults()
    
    if err := viper.ReadInConfig(); err != nil {
        if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
            return err
        }
        logger.Warn("No config file found, using defaults and environment")
    }
    
    return nil
}

func setDefaults() {
    // Database defaults
    viper.SetDefault("database.driver", "mysql")
    viper.SetDefault("database.host", "localhost")
    viper.SetDefault("database.port", 3306)
    viper.SetDefault("database.username", "asterisk")
    viper.SetDefault("database.password", "asterisk")
    viper.SetDefault("database.database", "asterisk_ara")
    viper.SetDefault("database.max_open_conns", 25)
    viper.SetDefault("database.max_idle_conns", 5)
    viper.SetDefault("database.conn_max_lifetime", "5m")
    
    // AGI defaults
    viper.SetDefault("agi.listen_address", "0.0.0.0")
    viper.SetDefault("agi.port", 4573)
    viper.SetDefault("agi.max_connections", 1000)
    viper.SetDefault("agi.read_timeout", "30s")
    viper.SetDefault("agi.write_timeout", "30s")
    viper.SetDefault("agi.idle_timeout", "120s")
    viper.SetDefault("agi.shutdown_timeout", "30s")
    
    // Router defaults
    viper.SetDefault("router.did_allocation_timeout", "5s")
    viper.SetDefault("router.call_cleanup_interval", "5m")
    viper.SetDefault("router.stale_call_timeout", "30m")
    viper.SetDefault("router.verification.enabled", true)
    
    // Monitoring defaults
    viper.SetDefault("monitoring.metrics.enabled", true)
    viper.SetDefault("monitoring.metrics.port", 9090)
    viper.SetDefault("monitoring.health.enabled", true)
    viper.SetDefault("monitoring.health.port", 8080)
    viper.SetDefault("monitoring.logging.level", "info")
    viper.SetDefault("monitoring.logging.format", "json")
}

func initializeDatabase(ctx context.Context) error {
    // Database configuration
    dbConfig := db.Config{
        Driver:          viper.GetString("database.driver"),
        Host:            viper.GetString("database.host"),
        Port:            viper.GetInt("database.port"),
        Username:        viper.GetString("database.username"),
        Password:        viper.GetString("database.password"),
        Database:        viper.GetString("database.database"),
        MaxOpenConns:    viper.GetInt("database.max_open_conns"),
        MaxIdleConns:    viper.GetInt("database.max_idle_conns"),
        ConnMaxLifetime: viper.GetDuration("database.conn_max_lifetime"),
        RetryAttempts:   3,
        RetryDelay:      time.Second,
    }
    
    // Initialize database
    if err := db.Initialize(dbConfig); err != nil {
        return err
    }
    
    database = db.GetDB()
    
    // Initialize cache
    cacheConfig := db.CacheConfig{
        Host:         viper.GetString("redis.host"),
        Port:         viper.GetInt("redis.port"),
        Password:     viper.GetString("redis.password"),
        DB:           viper.GetInt("redis.db"),
        PoolSize:     viper.GetInt("redis.pool_size"),
        MinIdleConns: viper.GetInt("redis.min_idle_conns"),
        MaxRetries:   viper.GetInt("redis.max_retries"),
    }
    
    if err := db.InitializeCache(cacheConfig, "ara-router"); err != nil {
        logger.WithError(err).Warn("Failed to initialize Redis cache, using memory cache")
    }
    
    cache = db.GetCache()
    
    // Initialize ARA manager
    araManager = ara.NewManager(database.DB, cache)
    
    // Initialize AMI manager if configured
    if viper.GetString("asterisk.ami.host") != "" {
        amiConfig := ami.Config{
            Host:              viper.GetString("asterisk.ami.host"),
            Port:              viper.GetInt("asterisk.ami.port"),
            Username:          viper.GetString("asterisk.ami.username"),
            Password:          viper.GetString("asterisk.ami.password"),
            ReconnectInterval: viper.GetDuration("asterisk.ami.reconnect_interval"),
            PingInterval:      viper.GetDuration("asterisk.ami.ping_interval"),
            ActionTimeout:     30 * time.Second, // Ensure we have a good timeout
            BufferSize:        1000,
        }
        
        amiManager = ami.NewManager(amiConfig)
        
        // Try to connect with retries
        ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
        err := amiManager.ConnectWithRetry(ctx, 3)
        cancel()
        
        if err != nil {
            logger.WithError(err).Warn("Failed to connect to AMI initially, will retry in background")
            // Start background connection attempts
            amiManager.ConnectOptional(context.Background())
        } else {
            logger.Info("AMI connected successfully")
        }
    } else {
        logger.Warn("AMI not configured, some features will be unavailable")
    }
    
    // Initialize metrics
    metricsSvc = metrics.NewPrometheusMetrics()
    
    // Initialize router
    routerConfig := router.Config{
        DIDAllocationTimeout: viper.GetDuration("router.did_allocation_timeout"),
        CallCleanupInterval:  viper.GetDuration("router.call_cleanup_interval"),
        StaleCallTimeout:     viper.GetDuration("router.stale_call_timeout"),
        MaxRetries:           viper.GetInt("router.max_retries"),
        VerificationEnabled:  viper.GetBool("router.verification.enabled"),
        StrictMode:           viper.GetBool("router.verification.strict_mode"),
    }
    
    routerSvc = router.NewRouter(database.DB, cache, metricsSvc, routerConfig)
    
    // Initialize provider service
    providerSvc = provider.NewService(database.DB, araManager, amiManager, cache)
    
    // Initialize health service
    if viper.GetBool("monitoring.health.enabled") {
        healthPort := viper.GetInt("monitoring.health.port")
        healthSvc = health.NewHealthService(healthPort)
        
        // Register health checks
        healthSvc.RegisterLivenessCheck("database", health.CheckFunc(func(ctx context.Context) error {
            if !database.IsHealthy() {
                return fmt.Errorf("database not healthy")
            }
            return database.PingContext(ctx)
        }))
        
        healthSvc.RegisterReadinessCheck("database", health.CheckFunc(func(ctx context.Context) error {
            return database.PingContext(ctx)
        }))
        
        if amiManager != nil {
            healthSvc.RegisterReadinessCheck("ami", health.CheckFunc(func(ctx context.Context) error {
                if !amiManager.IsConnected() {
                    return fmt.Errorf("AMI not connected")
                }
                _, err := amiManager.SendAction(ami.Action{Action: "Ping"})
                return err
            }))
        }
        
        go healthSvc.Start()
    }
    
    // Start metrics server
    if viper.GetBool("monitoring.metrics.enabled") {
        metricsPort := viper.GetInt("monitoring.metrics.port")
        go metricsSvc.ServeHTTP(metricsPort)
    }
    
    return nil
}

/*func initializeForCLI(ctx context.Context) error {
    if err := loadConfig(); err != nil {
        return fmt.Errorf("failed to load config: %v", err)
    }
    
    // Initialize logger
    logConfig := logger.Config{
        Level:  viper.GetString("monitoring.logging.level"),
        Format: viper.GetString("monitoring.logging.format"),
        Output: viper.GetString("monitoring.logging.output"),
        File: logger.FileConfig{
            Enabled:    viper.GetBool("monitoring.logging.file.enabled"),
            Path:       viper.GetString("monitoring.logging.file.path"),
            MaxSize:    viper.GetInt("monitoring.logging.file.max_size"),
            MaxBackups: viper.GetInt("monitoring.logging.file.max_backups"),
            MaxAge:     viper.GetInt("monitoring.logging.file.max_age"),
            Compress:   viper.GetBool("monitoring.logging.file.compress"),
        },
    }
    
    // Set defaults if not configured
    if logConfig.Level == "" {
        logConfig.Level = "info"
    }
    if logConfig.Format == "" {
        logConfig.Format = "text"  // Use text format for CLI
    }
    
    if err := logger.Init(logConfig); err != nil {
        return fmt.Errorf("failed to initialize logger: %v", err)
    }
    
    if err := initializeDatabase(ctx); err != nil {
        return fmt.Errorf("failed to initialize database: %v", err)
    }
    
    return nil
}*/
package main

import (
    "context"
    "encoding/json"
    "fmt"
    "os"
//    "strings"
    
    "github.com/spf13/cobra"
    "github.com/olekukonko/tablewriter"
    "github.com/hamzaKhattat/ara-production-system/internal/models"
    "github.com/hamzaKhattat/ara-production-system/internal/provider"
)

func createGroupCommands() *cobra.Command {
    groupCmd := &cobra.Command{
        Use:   "group",
        Short: "Manage provider groups",
        Long:  "Commands for managing provider groups with pattern matching and metadata filtering",
    }
    
    groupCmd.AddCommand(
        createGroupAddCommand(),
        createGroupListCommand(),
        createGroupShowCommand(),
        createGroupDeleteCommand(),
        createGroupAddMemberCommand(),
        createGroupRemoveMemberCommand(),
        createGroupRefreshCommand(),
    )
    
    return groupCmd
}

func createGroupAddCommand() *cobra.Command {
    var (
        description  string
        groupType    string
        pattern      string
        field        string
        operator     string
        value        string
        providerType string
        priority     int
    )
    
    cmd := &cobra.Command{
        Use:   "add <name>",
        Short: "Create a new provider group",
        Args:  cobra.ExactArgs(1),
        Example: `  # Create a regex group for Morocco providers
  router group add morocco --type regex --pattern "^mor.*" --provider-type intermediate
  
  # Create a metadata group for Panama providers
  router group add panama --type metadata --field country --operator equals --value Panama
  
  # Create a group for providers in specific regions
  router group add latam --type metadata --field region --operator in --value '["Central America","South America"]'`,
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            groupService := provider.NewGroupService(database.DB, cache)
            
            group := &models.ProviderGroup{
                Name:        args[0],
                Description: description,
                GroupType:   models.GroupType(groupType),
                Priority:    priority,
                Enabled:     true,
            }
            
            // Set type-specific fields
            switch group.GroupType {
            case models.GroupTypeRegex:
                if pattern == "" {
                    return fmt.Errorf("pattern is required for regex groups")
                }
                group.MatchPattern = pattern
            
            case models.GroupTypeMetadata:
                if field == "" || operator == "" || value == "" {
                    return fmt.Errorf("field, operator, and value are required for metadata groups")
                }
                group.MatchField = field
                group.MatchOperator = models.MatchOperator(operator)
                
                // Try to parse value as JSON first (for arrays)
                var parsedValue interface{}
                if err := json.Unmarshal([]byte(value), &parsedValue); err != nil {
                    // If not valid JSON, use as string
                    parsedValue = value
                }
                group.MatchValue, _ = json.Marshal(parsedValue)
            
            case models.GroupTypeManual:
                // No additional fields needed
            
            default:
                return fmt.Errorf("invalid group type: %s", groupType)
            }
            
            if providerType != "" {
                group.ProviderType = models.ProviderType(providerType)
            }
            
            if err := groupService.CreateGroup(ctx, group); err != nil {
                return fmt.Errorf("failed to create group: %v", err)
            }
            
            fmt.Printf("%s Group '%s' created successfully\n", green("✓"), args[0])
            
            // Show members if it's a dynamic group
            if group.GroupType != models.GroupTypeManual {
                members, err := groupService.GetGroupMembers(ctx, args[0])
                if err == nil && len(members) > 0 {
                    fmt.Printf("\nMatched %d providers:\n", len(members))
                    for _, m := range members {
                        fmt.Printf("  - %s (%s)\n", m.Name, m.Type)
                    }
                }
            }
            
            return nil
        },
    }
    
    cmd.Flags().StringVarP(&description, "description", "d", "", "Group description")
    cmd.Flags().StringVar(&groupType, "type", "manual", "Group type (manual/regex/metadata)")
    cmd.Flags().StringVar(&pattern, "pattern", "", "Regex pattern for matching provider names")
    cmd.Flags().StringVar(&field, "field", "", "Field to match (name/country/region/city/metadata.key)")
    cmd.Flags().StringVar(&operator, "operator", "equals", "Match operator (equals/contains/starts_with/ends_with/regex/in/not_in)")
    cmd.Flags().StringVar(&value, "value", "", "Value to match against")
    cmd.Flags().StringVar(&providerType, "provider-type", "", "Filter by provider type (inbound/intermediate/final)")
    cmd.Flags().IntVar(&priority, "priority", 10, "Group priority")
    
    return cmd
}

func createGroupListCommand() *cobra.Command {
    var (
        groupType    string
        providerType string
        showMembers  bool
    )
    
    cmd := &cobra.Command{
        Use:   "list",
        Short: "List all provider groups",
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            groupService := provider.NewGroupService(database.DB, cache)
            
            filter := make(map[string]interface{})
            if groupType != "" {
                filter["type"] = groupType
            }
            if providerType != "" {
                filter["provider_type"] = providerType
            }
            
            groups, err := groupService.ListGroups(ctx, filter)
            if err != nil {
                return fmt.Errorf("failed to list groups: %v", err)
            }
            
            if len(groups) == 0 {
                fmt.Println("No groups found")
                return nil
            }
            
            table := tablewriter.NewWriter(os.Stdout)
            table.SetHeader([]string{"Name", "Type", "Match", "Provider Type", "Members", "Priority", "Status"})
            table.SetBorder(false)
            
            for _, g := range groups {
                match := "-"
                switch g.GroupType {
                case models.GroupTypeRegex:
                    match = fmt.Sprintf("Pattern: %s", g.MatchPattern)
                case models.GroupTypeMetadata:
                    match = fmt.Sprintf("%s %s %s", g.MatchField, g.MatchOperator, string(g.MatchValue))
                }
                
                status := green("Enabled")
                if !g.Enabled {
                    status = red("Disabled")
                }
                
                provType := "any"
                if g.ProviderType != "" {
                    provType = string(g.ProviderType)
                }
                
                table.Append([]string{
                    g.Name,
                    string(g.GroupType),
                    match,
                    provType,
                    fmt.Sprintf("%d", g.MemberCount),
                    fmt.Sprintf("%d", g.Priority),
                    status,
                })
            }
            
            table.Render()
            
            if showMembers {
                fmt.Println("\nGroup Members:")
                for _, g := range groups {
                    members, err := groupService.GetGroupMembers(ctx, g.Name)
                    if err != nil {
                        continue
                    }
                    
                    if len(members) > 0 {
                        fmt.Printf("\n%s (%d members):\n", bold(g.Name), len(members))
                        for _, m := range members {
                            fmt.Printf("  - %s (%s) [Priority: %d, Weight: %d]\n", 
                                m.Name, m.Type, m.Priority, m.Weight)
                        }
                    }
                }
            }
            
            return nil
        },
    }
    
    cmd.Flags().StringVar(&groupType, "type", "", "Filter by group type")
    cmd.Flags().StringVar(&providerType, "provider-type", "", "Filter by provider type")
    cmd.Flags().BoolVar(&showMembers, "members", false, "Show group members")
    
    return cmd
}

func createGroupShowCommand() *cobra.Command {
    return &cobra.Command{
        Use:   "show <name>",
        Short: "Show detailed group information",
        Args:  cobra.ExactArgs(1),
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            groupService := provider.NewGroupService(database.DB, cache)
            
            group, err := groupService.GetGroup(ctx, args[0])
            if err != nil {
                return fmt.Errorf("failed to get group: %v", err)
            }
            
            fmt.Printf("\n%s\n", bold("Group Details"))
            fmt.Printf("Name:         %s\n", group.Name)
            if group.Description != "" {
                fmt.Printf("Description:  %s\n", group.Description)
            }
            fmt.Printf("Type:         %s\n", group.GroupType)
            
            switch group.GroupType {
            case models.GroupTypeRegex:
                fmt.Printf("Pattern:      %s\n", group.MatchPattern)
            case models.GroupTypeMetadata:
                fmt.Printf("Match Field:  %s\n", group.MatchField)
                fmt.Printf("Operator:     %s\n", group.MatchOperator)
                fmt.Printf("Value:        %s\n", string(group.MatchValue))
            }
            
            if group.ProviderType != "" && group.ProviderType != "any" {
                fmt.Printf("Provider Type: %s\n", group.ProviderType)
            }
            
            fmt.Printf("Priority:     %d\n", group.Priority)
            fmt.Printf("Status:       %s\n", formatBool(group.Enabled))
            fmt.Printf("Members:      %d\n", group.MemberCount)
            fmt.Printf("Created:      %s\n", group.CreatedAt.Format("2006-01-02 15:04:05"))
            fmt.Printf("Updated:      %s\n", group.UpdatedAt.Format("2006-01-02 15:04:05"))
            
            // Show members
            members, err := groupService.GetGroupMembers(ctx, args[0])
            if err == nil && len(members) > 0 {
                fmt.Printf("\n%s\n", bold("Group Members"))
                
                table := tablewriter.NewWriter(os.Stdout)
                table.SetHeader([]string{"Provider", "Type", "Host", "Priority", "Weight", "Status"})
                table.SetBorder(false)
                
                for _, m := range members {
                    status := green("Active")
                    if !m.Active {
                        status = red("Inactive")
                    } else if m.HealthStatus != "healthy" {
                        status = yellow("Degraded")
                    }
                    
                    table.Append([]string{
                        m.Name,
                        string(m.Type),
                        fmt.Sprintf("%s:%d", m.Host, m.Port),
                        fmt.Sprintf("%d", m.Priority),
                        fmt.Sprintf("%d", m.Weight),
                        status,
                    })
                }
                
                table.Render()
            }
            
            return nil
        },
    }
}

func createGroupDeleteCommand() *cobra.Command {
    return &cobra.Command{
        Use:   "delete <name>",
        Short: "Delete a provider group",
        Args:  cobra.ExactArgs(1),
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            groupService := provider.NewGroupService(database.DB, cache)
            
            if err := groupService.DeleteGroup(ctx, args[0]); err != nil {
                return fmt.Errorf("failed to delete group: %v", err)
            }
            
            fmt.Printf("%s Group '%s' deleted successfully\n", green("✓"), args[0])
            return nil
        },
    }
}

func createGroupAddMemberCommand() *cobra.Command {
    var (
        priority int
        weight   int
    )
    
    cmd := &cobra.Command{
        Use:   "add-member <group> <provider>",
        Short: "Add a provider to a group",
        Args:  cobra.ExactArgs(2),
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            groupService := provider.NewGroupService(database.DB, cache)
            
            overrides := make(map[string]interface{})
            if cmd.Flags().Changed("priority") {
                overrides["priority"] = priority
            }
            if cmd.Flags().Changed("weight") {
                overrides["weight"] = weight
            }
            
            if err := groupService.AddProviderToGroup(ctx, args[0], args[1], overrides); err != nil {
                return fmt.Errorf("failed to add provider to group: %v", err)
            }
            
            fmt.Printf("%s Added provider '%s' to group '%s'\n", green("✓"), args[1], args[0])
            return nil
        },
    }
    
    cmd.Flags().IntVar(&priority, "priority", 0, "Override provider priority in this group")
    cmd.Flags().IntVar(&weight, "weight", 0, "Override provider weight in this group")
    
    return cmd
}

func createGroupRemoveMemberCommand() *cobra.Command {
    return &cobra.Command{
        Use:   "remove-member <group> <provider>",
        Short: "Remove a provider from a group",
        Args:  cobra.ExactArgs(2),
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            groupService := provider.NewGroupService(database.DB, cache)
            
            if err := groupService.RemoveProviderFromGroup(ctx, args[0], args[1]); err != nil {
                return fmt.Errorf("failed to remove provider from group: %v", err)
            }
            
            fmt.Printf("%s Removed provider '%s' from group '%s'\n", green("✓"), args[1], args[0])
            return nil
        },
    }
}

func createGroupRefreshCommand() *cobra.Command {
    return &cobra.Command{
        Use:   "refresh <name>",
        Short: "Refresh dynamic group members",
        Args:  cobra.ExactArgs(1),
        RunE: func(cmd *cobra.Command, args []string) error {
            ctx := context.Background()
            
            if err := initializeForCLI(ctx); err != nil {
                return err
            }
            
            groupService := provider.NewGroupService(database.DB, cache)
            
            if err := groupService.RefreshGroupMembers(ctx, args[0]); err != nil {
                return fmt.Errorf("failed to refresh group: %v", err)
            }
            
            fmt.Printf("%s Group '%s' members refreshed\n", green("✓"), args[0])
            
            // Show updated members
            members, err := groupService.GetGroupMembers(ctx, args[0])
            if err == nil {
                fmt.Printf("Current members: %d\n", len(members))
                for _, m := range members {
                    fmt.Printf("  - %s (%s)\n", m.Name, m.Type)
                }
            }
            
            return nil
        },
    }
}
package main

import (
    "context"
    "flag"
    "fmt"
    "os"
    "os/signal"
    "syscall"
    
    "github.com/spf13/cobra"
    "github.com/spf13/viper"
    "github.com/hamzaKhattat/ara-production-system/internal/agi"
    "github.com/hamzaKhattat/ara-production-system/internal/ami"
    "github.com/hamzaKhattat/ara-production-system/internal/ara"
    "github.com/hamzaKhattat/ara-production-system/internal/db"
    "github.com/hamzaKhattat/ara-production-system/internal/health"
    "github.com/hamzaKhattat/ara-production-system/internal/metrics"
    "github.com/hamzaKhattat/ara-production-system/internal/provider"
    "github.com/hamzaKhattat/ara-production-system/internal/router"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
)

var (
    configFile string
    initDB     bool
    flushDB    bool
    agiMode    bool
    verbose    bool
    
    // Global services - these are shared with commands.go
    database     *db.DB
    cache        *db.Cache
    araManager   *ara.Manager
    amiManager   *ami.Manager
    routerSvc    *router.Router
    providerSvc  *provider.Service
    agiServer    *agi.Server
    healthSvc    *health.HealthService
    metricsSvc   *metrics.PrometheusMetrics
)

func main() {
    // Parse flags for server mode
    flag.StringVar(&configFile, "config", "", "Configuration file path")
    flag.BoolVar(&initDB, "init-db", false, "Initialize database (WARNING: Drops existing data if --flush is used)")
    flag.BoolVar(&flushDB, "flush", false, "Flush existing database before initialization")
    flag.BoolVar(&agiMode, "agi", false, "Run AGI server")
    flag.BoolVar(&verbose, "verbose", false, "Enable verbose logging")
    flag.Parse()
    
    // If flags are set, run in server mode
    if flag.NFlag() > 0 {
        runServerMode()
        return
    }
    
    // Otherwise, run CLI mode
    runCLI()
}

func runServerMode() {
    ctx := context.Background()
    
    // Load configuration
    if err := loadConfig(); err != nil {
        fmt.Fprintf(os.Stderr, "Failed to load config: %v\n", err)
        os.Exit(1)
    }
    
    // Initialize logger
    logConfig := logger.Config{
        Level:  viper.GetString("monitoring.logging.level"),
        Format: viper.GetString("monitoring.logging.format"),
        Output: viper.GetString("monitoring.logging.output"),
        File: logger.FileConfig{
            Enabled:    viper.GetBool("monitoring.logging.file.enabled"),
            Path:       viper.GetString("monitoring.logging.file.path"),
            MaxSize:    viper.GetInt("monitoring.logging.file.max_size"),
            MaxBackups: viper.GetInt("monitoring.logging.file.max_backups"),
            MaxAge:     viper.GetInt("monitoring.logging.file.max_age"),
            Compress:   viper.GetBool("monitoring.logging.file.compress"),
        },
    }
    
    if verbose {
        logConfig.Level = "debug"
    }
    
    if err := logger.Init(logConfig); err != nil {
        fmt.Fprintf(os.Stderr, "Failed to initialize logger: %v\n", err)
        os.Exit(1)
    }
    
    // Initialize database connection
    if err := initializeDatabase(ctx); err != nil {
        logger.Fatal("Failed to initialize database", "error", err)
    }
    
    // Initialize database schema if requested
    if initDB {
        logger.Info("Initializing database schema")
        
        if flushDB {
            logger.Warn("FLUSH mode enabled - All existing data will be deleted!")
            fmt.Print("\nWARNING: This will DELETE ALL existing data. Continue? [y/N]: ")
            var response string
            fmt.Scanln(&response)
            if response != "y" && response != "Y" {
                logger.Info("Database initialization cancelled")
                return
            }
        }
        
        // Initialize the database schema
        if err := db.InitializeDatabase(ctx, database.DB, flushDB); err != nil {
            logger.Fatal("Failed to initialize database schema", "error", err)
        }
        
        // Create initial dialplan through ARA manager
        if err := araManager.CreateDialplan(ctx); err != nil {
            logger.WithError(err).Warn("Failed to create dialplan through ARA manager")
        }
        
        // Add sample data
        if err := addSampleData(ctx); err != nil {
            logger.WithError(err).Warn("Failed to add sample data")
        }
        
        logger.Info("Database initialization completed successfully")
        logger.Info("Next steps:")
        logger.Info("1. Restart Asterisk: systemctl restart asterisk")
        logger.Info("2. Start AGI server: ./bin/router -agi")
        logger.Info("3. Add providers: ./bin/router provider add <name> -t <type> --host <ip>")
        return
    }
    
    // Run AGI server if requested
    if agiMode {
        runAGIServer(ctx)
        return
    }
    
    // Otherwise show usage
    fmt.Println("Usage:")
    fmt.Println("  router [command] [flags]")
    fmt.Println("  router -agi              # Run AGI server")
    fmt.Println("  router -init-db          # Initialize database")
    fmt.Println("  router -init-db -flush   # Flush and reinitialize database")
    fmt.Println("")
    fmt.Println("Run 'router --help' for more information")
}

func runCLI() {
    rootCmd := &cobra.Command{
        Use:   "router",
        Short: "Asterisk ARA Dynamic Call Router",
        Long:  "Production-level dynamic call routing system with full ARA integration",
    }
    
    // Add commands
    rootCmd.AddCommand(
        createProviderCommands(),
        createGroupCommands(), 
        createDIDCommands(),
        createRouteCommands(),
        createStatsCommand(),
        createLoadBalancerCommand(),
        createCallsCommand(),
        createMonitorCommand(),
    )
    
    if err := rootCmd.Execute(); err != nil {
        fmt.Fprintf(os.Stderr, "Error: %v\n", err)
        os.Exit(1)
    }
}

func runAGIServer(ctx context.Context) {
    logger.Info("Starting AGI server")
    
    // Initialize AGI server
    agiConfig := agi.Config{
        ListenAddress:   viper.GetString("agi.listen_address"),
        Port:            viper.GetInt("agi.port"),
        MaxConnections:  viper.GetInt("agi.max_connections"),
        ReadTimeout:     viper.GetDuration("agi.read_timeout"),
        WriteTimeout:    viper.GetDuration("agi.write_timeout"),
        IdleTimeout:     viper.GetDuration("agi.idle_timeout"),
        ShutdownTimeout: viper.GetDuration("agi.shutdown_timeout"),
    }
    
    agiServer = agi.NewServer(routerSvc, agiConfig, metricsSvc)
    
    // Handle shutdown
    sigChan := make(chan os.Signal, 1)
    signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
    
    go func() {
        if err := agiServer.Start(); err != nil {
            logger.Fatal("AGI server failed", "error", err)
        }
    }()
    
    <-sigChan
    logger.Info("Shutting down AGI server")
    
    if err := agiServer.Stop(); err != nil {
        logger.WithError(err).Error("Error stopping AGI server")
    }
    
    // Cleanup
    if amiManager != nil {
        amiManager.Close()
    }
    
    if healthSvc != nil {
        healthSvc.Stop()
    }
    
    logger.Info("Shutdown complete")
}

func addSampleData(ctx context.Context) error {
    log := logger.WithContext(ctx)
    log.Info("Adding sample data...")
    
    // Check if we already have data
    var count int
    if err := database.DB.QueryRowContext(ctx, "SELECT COUNT(*) FROM providers").Scan(&count); err == nil && count > 0 {
        log.Info("Sample data already exists, skipping...")
        return nil
    }
    
    // Add sample providers
    sampleProviders := []string{
        `INSERT INTO providers (name, type, host, port, auth_type, active, transport, codecs) VALUES 
         ('s1', 'inbound', '10.0.0.1', 5060, 'ip', 1, 'udp', '["ulaw","alaw"]'),
         ('s3-intermediate', 'intermediate', '10.0.0.3', 5060, 'ip', 1, 'udp', '["ulaw","alaw"]'),
         ('s4-final', 'final', '10.0.0.4', 5060, 'ip', 1, 'udp', '["ulaw","alaw"]')`,
    }
    
    for _, query := range sampleProviders {
        if _, err := database.DB.ExecContext(ctx, query); err != nil {
            log.WithError(err).Warn("Failed to insert sample providers")
        }
    }
    
    // Add sample DIDs
    sampleDIDs := `
        INSERT INTO dids (number, provider_name, provider_id, in_use, country, city, monthly_cost, per_minute_cost) VALUES
        ('584148757547', 's1', 1, 0, 'VE', 'Caracas', 10.00, 0.01),
        ('584249726299', 's1', 1, 0, 'VE', 'Caracas', 10.00, 0.01),
        ('584167000000', 's1', 1, 0, 'VE', 'Caracas', 10.00, 0.01),
        ('584267000011', 's1', 1, 0, 'VE', 'Caracas', 10.00, 0.01),
        ('15551234001', 's3-intermediate', 2, 0, 'US', 'New York', 12.00, 0.012),
        ('15551234002', 's3-intermediate', 2, 0, 'US', 'New York', 12.00, 0.012),
        ('15551234003', 's3-intermediate', 2, 0, 'US', 'Chicago', 12.00, 0.012),
        ('15551234004', 's4-final', 3, 0, 'US', 'Miami', 15.00, 0.015),
        ('15551234005', 's4-final', 3, 0, 'US', 'Miami', 15.00, 0.015)`
    
    if _, err := database.DB.ExecContext(ctx, sampleDIDs); err != nil {
        log.WithError(err).Warn("Failed to insert sample DIDs")
    }
    
    // Add sample route
    sampleRoute := `
        INSERT INTO provider_routes (name, inbound_provider, intermediate_provider, final_provider, enabled) 
        VALUES ('main-route', 's1', 's3-intermediate', 's4-final', 1)`
    
    if _, err := database.DB.ExecContext(ctx, sampleRoute); err != nil {
        log.WithError(err).Warn("Failed to insert sample route")
    }
    
    // Create ARA endpoints for providers
    providers, err := providerSvc.ListProviders(ctx, nil)
    if err == nil {
        for _, p := range providers {
            if err := araManager.CreateEndpoint(ctx, p); err != nil {
                log.WithError(err).WithField("provider", p.Name).Warn("Failed to create ARA endpoint")
            }
        }
    }
    
    log.Info("Sample data added successfully")
    return nil
}
package agi

import (
    "bufio"
    "context"
    "fmt"
    "io"
    "net"
    "strings"
    "sync"
    "sync/atomic"
    "time"
    
    "github.com/hamzaKhattat/ara-production-system/internal/router"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
)

const (
    AGISuccess = "200 result=1"
    AGIFailure = "200 result=0"
    AGIError   = "510 Invalid or unknown command"
)

type Server struct {
    router  *router.Router
    config  Config
    
    listener     net.Listener
    connections  sync.WaitGroup
    shutdown     chan struct{}
    shuttingDown atomic.Bool
    
    // Connection tracking
    mu          sync.RWMutex
    activeConns map[string]*Session
    connCount   atomic.Int64
    
    // Metrics
    metrics MetricsInterface
}

type Config struct {
    ListenAddress    string
    Port             int
    MaxConnections   int
    ReadTimeout      time.Duration
    WriteTimeout     time.Duration
    IdleTimeout      time.Duration
    ShutdownTimeout  time.Duration
}

type MetricsInterface interface {
    IncrementCounter(name string, labels map[string]string)
    ObserveHistogram(name string, value float64, labels map[string]string)
    SetGauge(name string, value float64, labels map[string]string)
}

type Session struct {
    id         string
    conn       net.Conn
    reader     *bufio.Reader
    writer     *bufio.Writer
    headers    map[string]string
    server     *Server
    startTime  time.Time
    lastActive time.Time
    ctx        context.Context
    cancel     context.CancelFunc
}

func NewServer(router *router.Router, config Config, metrics MetricsInterface) *Server {
    return &Server{
        router:      router,
        config:      config,
        shutdown:    make(chan struct{}),
        activeConns: make(map[string]*Session),
        metrics:     metrics,
    }
}

func (s *Server) Start() error {
    addr := fmt.Sprintf("%s:%d", s.config.ListenAddress, s.config.Port)
    
    listener, err := net.Listen("tcp", addr)
    if err != nil {
        return errors.Wrap(err, errors.ErrInternal, "failed to start AGI server")
    }
    
    s.listener = listener
    logger.Info("AGI server started", "address", addr)
    
    // Start connection monitor
    go s.connectionMonitor()
    
    // Accept connections
    for {
        select {
        case <-s.shutdown:
            return nil
        default:
            // Set accept timeout to check shutdown periodically
            if tcpListener, ok := listener.(*net.TCPListener); ok {
                tcpListener.SetDeadline(time.Now().Add(1 * time.Second))
            }
            
            conn, err := listener.Accept()
            if err != nil {
                if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
                    continue
                }
                if s.shuttingDown.Load() {
                    return nil
                }
                logger.Warn("Failed to accept connection", "error", err.Error())
                continue
            }
            
            // Check connection limit
            if s.config.MaxConnections > 0 && int(s.connCount.Load()) >= s.config.MaxConnections {
                logger.Warn("Connection limit reached, rejecting connection")
                conn.Close()
                s.metrics.IncrementCounter("agi_connections_rejected", map[string]string{
                    "reason": "limit_exceeded",
                })
                continue
            }
            
            s.connections.Add(1)
            s.connCount.Add(1)
            go s.handleConnection(conn)
        }
    }
}

func (s *Server) Stop() error {
    s.shuttingDown.Store(true)
    close(s.shutdown)
    
    if s.listener != nil {
        s.listener.Close()
    }
    
    // Wait for connections to finish with timeout
    done := make(chan struct{})
    go func() {
        s.connections.Wait()
        close(done)
    }()
    
    select {
    case <-done:
        logger.Info("AGI server stopped gracefully")
    case <-time.After(s.config.ShutdownTimeout):
        logger.Warn("AGI server shutdown timeout, forcing close")
        s.forceCloseConnections()
    }
    
    return nil
}

func (s *Server) handleConnection(conn net.Conn) {
    defer func() {
        s.connections.Done()
        s.connCount.Add(-1)
        conn.Close()
    }()
    
    // Create session
    ctx, cancel := context.WithCancel(context.Background())
    session := &Session{
        id:         fmt.Sprintf("%s-%d", conn.RemoteAddr().String(), time.Now().UnixNano()),
        conn:       conn,
        reader:     bufio.NewReader(conn),
        writer:     bufio.NewWriter(conn),
        headers:    make(map[string]string),
        server:     s,
        startTime:  time.Now(),
        lastActive: time.Now(),
        ctx:        ctx,
        cancel:     cancel,
    }
    
    // Track session
    s.mu.Lock()
    s.activeConns[session.id] = session
    s.mu.Unlock()
    
    defer func() {
        s.mu.Lock()
        delete(s.activeConns, session.id)
        s.mu.Unlock()
        cancel()
    }()
    
    // Set initial timeout
    conn.SetDeadline(time.Now().Add(s.config.ReadTimeout))
    
    // Log connection
    logger.Debug("New AGI connection", 
        "session_id", session.id,
        "remote_addr", conn.RemoteAddr().String())
    
    // Update metrics
    s.metrics.IncrementCounter("agi_connections_total", nil)
    s.metrics.SetGauge("agi_connections_active", float64(s.connCount.Load()), nil)
    
    // Handle session
    if err := session.handle(); err != nil {
        if err != io.EOF && !strings.Contains(err.Error(), "use of closed network connection") {
            logger.Warn("Session error", "session_id", session.id, "error", err.Error())
        }
    }
    
    // Log session duration
    duration := time.Since(session.startTime)
    logger.Debug("AGI session completed",
        "session_id", session.id,
        "duration", duration.Seconds())
    
    s.metrics.ObserveHistogram("agi_session_duration", duration.Seconds(), nil)
}

func (session *Session) handle() error {
    // Read AGI headers
    if err := session.readHeaders(); err != nil {
        return errors.Wrap(err, errors.ErrAGIConnection, "failed to read headers")
    }
    
    // Extract request info
    request := session.headers["agi_request"]
    if request == "" {
        return errors.New(errors.ErrAGIInvalidCmd, "no AGI request found")
    }
    
    // Add context values
    session.ctx = context.WithValue(session.ctx, "session_id", session.id)
    session.ctx = context.WithValue(session.ctx, "request_id", session.headers["agi_uniqueid"])
    session.ctx = context.WithValue(session.ctx, "call_id", session.headers["agi_uniqueid"])
    
    // Log request
    log := logger.WithContext(session.ctx)
    log.Info("Processing AGI request",
        "request", request,
        "channel", session.headers["agi_channel"],
        "callerid", session.headers["agi_callerid"],
        "extension", session.headers["agi_extension"])
    
    // Route request
    switch {
    case strings.Contains(request, "processIncoming"):
        return session.handleProcessIncoming()
    case strings.Contains(request, "processReturn"):
        return session.handleProcessReturn()
    case strings.Contains(request, "processFinal"):
        return session.handleProcessFinal()
    case strings.Contains(request, "hangup"):
        return session.handleHangup()
    default:
        log.Warn("Unknown AGI request", "request", request)
        return session.sendResponse(AGIFailure)
    }
}

func (session *Session) readHeaders() error {
    session.updateActivity()
    
    for {
        line, err := session.reader.ReadString('\n')
        if err != nil {
            return err
        }
        
        line = strings.TrimSpace(line)
        
        // Empty line indicates end of headers
        if line == "" {
            break
        }
        
        // Parse header
        parts := strings.SplitN(line, ":", 2)
        if len(parts) == 2 {
            key := strings.TrimSpace(parts[0])
            value := strings.TrimSpace(parts[1])
            session.headers[key] = value
        }
    }
    
    return nil
}

func (session *Session) handleProcessIncoming() error {
    // Extract call information
    callID := session.headers["agi_uniqueid"]
    ani := session.headers["agi_callerid"]
    dnis := session.headers["agi_extension"]
    channel := session.headers["agi_channel"]
    
    // Extract provider from channel
    inboundProvider := session.extractProviderFromChannel(channel)
    
    // Process through router
    startTime := time.Now()
    response, err := session.server.router.ProcessIncomingCall(session.ctx, callID, ani, dnis, inboundProvider)
    processingTime := time.Since(startTime)
    
    // Update metrics
    session.server.metrics.ObserveHistogram("agi_processing_time", processingTime.Seconds(), map[string]string{
        "action": "process_incoming",
    })
    
    if err != nil {
        log := logger.WithContext(session.ctx)
        log.Error("Failed to process incoming call", "error", err.Error())
        session.setVariable("ROUTER_STATUS", "failed")
        session.setVariable("ROUTER_ERROR", err.Error())
        
        errorCode := "UNKNOWN_ERROR"
        if appErr, ok := err.(*errors.AppError); ok {
            errorCode = string(appErr.Code)
        }
        
        session.server.metrics.IncrementCounter("agi_requests_failed", map[string]string{
            "action": "process_incoming",
            "error": errorCode,
        })
        
        return session.sendResponse(AGISuccess)
    }
    
    // Set channel variables for dialplan
    session.setVariable("ROUTER_STATUS", "success")
    session.setVariable("DID_ASSIGNED", response.DIDAssigned)
    session.setVariable("NEXT_HOP", response.NextHop)
    session.setVariable("ANI_TO_SEND", response.ANIToSend)
    session.setVariable("DNIS_TO_SEND", response.DNISToSend)
    session.setVariable("INTERMEDIATE_PROVIDER", strings.TrimPrefix(response.NextHop, "endpoint-"))
    
    session.server.metrics.IncrementCounter("agi_requests_success", map[string]string{
        "action": "process_incoming",
    })
    
    return session.sendResponse(AGISuccess)
}

func (session *Session) handleProcessReturn() error {
    // Extract call information
    ani2 := session.headers["agi_callerid"]
    did := session.headers["agi_extension"]
    channel := session.headers["agi_channel"]
    
    // Get source IP from channel variable
    sourceIP := session.getVariable("SOURCE_IP")
    
    // Extract provider from channel
    intermediateProvider := session.extractProviderFromChannel(channel)
    
    // Process through router
    startTime := time.Now()
    response, err := session.server.router.ProcessReturnCall(session.ctx, ani2, did, intermediateProvider, sourceIP)
    processingTime := time.Since(startTime)
    
    // Update metrics
    session.server.metrics.ObserveHistogram("agi_processing_time", processingTime.Seconds(), map[string]string{
        "action": "process_return",
    })
    
    if err != nil {
        log := logger.WithContext(session.ctx)
        log.Error("Failed to process return call", "error", err.Error())
        session.setVariable("ROUTER_STATUS", "failed")
        session.setVariable("ROUTER_ERROR", err.Error())
        
        errorCode := "UNKNOWN_ERROR"
        if appErr, ok := err.(*errors.AppError); ok {
            errorCode = string(appErr.Code)
        }
        
        session.server.metrics.IncrementCounter("agi_requests_failed", map[string]string{
            "action": "process_return",
            "error": errorCode,
        })
        
        return session.sendResponse(AGISuccess)
    }
    
    // Set channel variables for routing to S4
    session.setVariable("ROUTER_STATUS", "success")
    session.setVariable("NEXT_HOP", response.NextHop)
    session.setVariable("ANI_TO_SEND", response.ANIToSend)
    session.setVariable("DNIS_TO_SEND", response.DNISToSend)
    session.setVariable("FINAL_PROVIDER", strings.TrimPrefix(response.NextHop, "endpoint-"))
    
    session.server.metrics.IncrementCounter("agi_requests_success", map[string]string{
        "action": "process_return",
    })
    
    return session.sendResponse(AGISuccess)
}

func (session *Session) handleProcessFinal() error {
    // Extract call information
    callID := session.headers["agi_uniqueid"]
    ani := session.headers["agi_callerid"]
    dnis := session.headers["agi_extension"]
    channel := session.headers["agi_channel"]
    
    // Get source IP from channel variable
    sourceIP := session.getVariable("SOURCE_IP")
    
    // Extract provider from channel
    finalProvider := session.extractProviderFromChannel(channel)
    
    // Process through router
    startTime := time.Now()
    err := session.server.router.ProcessFinalCall(session.ctx, callID, ani, dnis, finalProvider, sourceIP)
    processingTime := time.Since(startTime)
    
    // Update metrics
    session.server.metrics.ObserveHistogram("agi_processing_time", processingTime.Seconds(), map[string]string{
        "action": "process_final",
    })
    
    if err != nil {
        log := logger.WithContext(session.ctx)
        log.Error("Failed to process final call", "error", err.Error())
        
        errorCode := "UNKNOWN_ERROR"
        if appErr, ok := err.(*errors.AppError); ok {
            errorCode = string(appErr.Code)
        }
        
        session.server.metrics.IncrementCounter("agi_requests_failed", map[string]string{
            "action": "process_final",
            "error": errorCode,
        })
    } else {
        session.server.metrics.IncrementCounter("agi_requests_success", map[string]string{
            "action": "process_final",
        })
    }
    
    return session.sendResponse(AGISuccess)
}

func (session *Session) handleHangup() error {
    callID := session.headers["agi_uniqueid"]
    
    // Process hangup
    startTime := time.Now()
    err := session.server.router.ProcessHangup(session.ctx, callID)
    processingTime := time.Since(startTime)
    
    // Update metrics
    session.server.metrics.ObserveHistogram("agi_processing_time", processingTime.Seconds(), map[string]string{
        "action": "hangup",
    })
    
    if err != nil {
        log := logger.WithContext(session.ctx)
        log.Warn("Failed to process hangup", "error", err.Error())
    }
    
    session.server.metrics.IncrementCounter("agi_requests_success", map[string]string{
        "action": "hangup",
    })
    
    return session.sendResponse(AGISuccess)
}

func (session *Session) setVariable(name, value string) error {
    session.updateActivity()
    
    cmd := fmt.Sprintf("SET VARIABLE %s \"%s\"", name, value)
    if err := session.sendCommand(cmd); err != nil {
        return err
    }
    
    response, err := session.readResponse()
    if err != nil {
        return err
    }
    
    log := logger.WithContext(session.ctx)
    log.Debug("Set AGI variable",
        "variable", name,
        "value", value,
        "response", response)
    
    return nil
}

func (session *Session) getVariable(name string) string {
    session.updateActivity()
    
    cmd := fmt.Sprintf("GET VARIABLE %s", name)
    if err := session.sendCommand(cmd); err != nil {
        return ""
    }
    
    response, err := session.readResponse()
    if err != nil {
        return ""
    }
    
    // Parse response: "200 result=1 (value)"
    if strings.Contains(response, "result=1") {
        start := strings.Index(response, "(")
        end := strings.LastIndex(response, ")")
        if start > 0 && end > start {
            value := response[start+1 : end]
            log := logger.WithContext(session.ctx)
            log.Debug("Got AGI variable",
                "variable", name,
                "value", value)
            return value
        }
    }
    
    return ""
}

func (session *Session) sendCommand(cmd string) error {
    session.conn.SetWriteDeadline(time.Now().Add(session.server.config.WriteTimeout))
    
    _, err := session.writer.WriteString(cmd + "\n")
    if err != nil {
        return err
    }
    
    return session.writer.Flush()
}

func (session *Session) readResponse() (string, error) {
    session.conn.SetReadDeadline(time.Now().Add(session.server.config.ReadTimeout))
    
    response, err := session.reader.ReadString('\n')
    if err != nil {
        return "", err
    }
    
    return strings.TrimSpace(response), nil
}

func (session *Session) sendResponse(response string) error {
    return session.sendCommand(response)
}

func (session *Session) extractProviderFromChannel(channel string) string {
    // Channel format examples:
    // PJSIP/endpoint-provider1-00000001
    // SIP/provider1-00000001
    
    if channel == "" {
        return ""
    }
    
    // Remove technology prefix
    parts := strings.Split(channel, "/")
    if len(parts) < 2 {
        return ""
    }
    
    // Get endpoint part
    endpointPart := parts[1]
    
    // Extract provider name
    // Format: "endpoint-providername-uniqueid" or "providername-uniqueid"
    endpointParts := strings.Split(endpointPart, "-")
    
    if len(endpointParts) >= 3 && endpointParts[0] == "endpoint" {
        // Join all parts except first and last
        providerParts := endpointParts[1 : len(endpointParts)-1]
        return strings.Join(providerParts, "-")
    } else if len(endpointParts) >= 2 {
        // Join all parts except last
        providerParts := endpointParts[:len(endpointParts)-1]
        return strings.Join(providerParts, "-")
    }
    
    return ""
}

func (session *Session) updateActivity() {
    session.lastActive = time.Now()
}

func (s *Server) connectionMonitor() {
    ticker := time.NewTicker(30 * time.Second)
    defer ticker.Stop()
    
    for {
        select {
        case <-s.shutdown:
            return
        case <-ticker.C:
            s.checkIdleConnections()
        }
    }
}

func (s *Server) checkIdleConnections() {
    s.mu.Lock()
    defer s.mu.Unlock()
    
    now := time.Now()
    var toClose []string
    
    for id, session := range s.activeConns {
        if now.Sub(session.lastActive) > s.config.IdleTimeout {
            toClose = append(toClose, id)
        }
    }
    
    for _, id := range toClose {
        if session, exists := s.activeConns[id]; exists {
            logger.Info("Closing idle connection", "session_id", id)
            session.conn.Close()
            session.cancel()
        }
    }
}

func (s *Server) forceCloseConnections() {
    s.mu.Lock()
    defer s.mu.Unlock()
    
    for id, session := range s.activeConns {
        logger.Info("Force closing connection", "session_id", id)
        session.conn.Close()
        session.cancel()
    }
}

// GetRouter returns the router instance (for testing)
func (s *Server) GetRouter() *router.Router {
    return s.router
}
package ami

import (
    "bufio"
    "context"
    "fmt"
    "net"
    "strings"
    "sync"
    "sync/atomic"
    "time"
    
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
)

// Manager handles Asterisk Manager Interface connections
type Manager struct {
    config     Config
    conn       net.Conn
    reader     *bufio.Reader
    writer     *bufio.Writer
    
    mu         sync.RWMutex
    connected  bool
    loggedIn   bool
    
    // Event handling
    eventChan     chan Event
    eventHandlers map[string][]EventHandler
    loginChan     chan Event  // Special channel for login responses
    
    // Action handling
    actionID       uint64
    pendingActions map[string]chan Event
    actionMutex    sync.Mutex
    
    // Connection management
    shutdown      chan struct{}
    reconnectChan chan struct{}
    wg            sync.WaitGroup
    
    // Metrics
    totalEvents   uint64
    totalActions  uint64
    failedActions uint64
}

// Config holds AMI connection configuration
type Config struct {
    Host              string
    Port              int
    Username          string
    Password          string
    ReconnectInterval time.Duration
    PingInterval      time.Duration
    ActionTimeout     time.Duration
    ConnectTimeout    time.Duration
    ReadTimeout       time.Duration
    BufferSize        int
}

// Event represents an AMI event
type Event map[string]string

// EventHandler is a function that handles AMI events
type EventHandler func(event Event)

// Action represents an AMI action
type Action struct {
    Action   string
    ActionID string
    Fields   map[string]string
}

// NewManager creates a new AMI manager
func NewManager(config Config) *Manager {
    // Set defaults
    if config.Port == 0 {
        config.Port = 5038
    }
    if config.ReconnectInterval == 0 {
        config.ReconnectInterval = 5 * time.Second
    }
    if config.PingInterval == 0 {
        config.PingInterval = 30 * time.Second
    }
    if config.ActionTimeout == 0 {
        config.ActionTimeout = 30 * time.Second
    }
    if config.ConnectTimeout == 0 {
        config.ConnectTimeout = 10 * time.Second
    }
    if config.ReadTimeout == 0 {
        config.ReadTimeout = 30 * time.Second
    }
    if config.BufferSize == 0 {
        config.BufferSize = 1000
    }
    
    return &Manager{
        config:         config,
        eventChan:      make(chan Event, config.BufferSize),
        eventHandlers:  make(map[string][]EventHandler),
        pendingActions: make(map[string]chan Event),
        loginChan:      make(chan Event, 10),
        shutdown:       make(chan struct{}),
        reconnectChan:  make(chan struct{}, 1),
    }
}

// Connect establishes connection to AMI
func (m *Manager) Connect(ctx context.Context) error {
    m.mu.Lock()
    defer m.mu.Unlock()
    
    if m.connected {
        return nil
    }
    
    addr := fmt.Sprintf("%s:%d", m.config.Host, m.config.Port)
    logger.Info("Connecting to Asterisk AMI", "addr", addr)
    
    // Connect with timeout
    dialer := net.Dialer{
        Timeout: m.config.ConnectTimeout,
    }
    
    conn, err := dialer.DialContext(ctx, "tcp", addr)
    if err != nil {
        return errors.Wrap(err, errors.ErrInternal, "failed to connect to AMI")
    }
    
    m.conn = conn
    m.reader = bufio.NewReader(conn)
    m.writer = bufio.NewWriter(conn)
    
    // Set read deadline for banner
    conn.SetReadDeadline(time.Now().Add(5 * time.Second))
    
    // Read banner
    banner, err := m.reader.ReadString('\n')
    if err != nil {
        conn.Close()
        return errors.Wrap(err, errors.ErrInternal, "failed to read AMI banner")
    }
    
    // Reset deadline
    conn.SetReadDeadline(time.Time{})
    
    banner = strings.TrimSpace(banner)
    logger.Debug("AMI Banner received", "banner", banner)
    
    if !strings.Contains(banner, "Asterisk Call Manager") {
        conn.Close()
        return errors.New(errors.ErrInternal, fmt.Sprintf("invalid AMI banner: %s", banner))
    }
    
    m.connected = true
    
    // Start event reader
    m.wg.Add(1)
    go m.eventReader()
    
    // Login
    if err := m.performLogin(); err != nil {
        m.connected = false
        m.conn.Close()
        return err
    }
    
    m.loggedIn = true
    
    // Start background goroutines
    m.wg.Add(2)
    go m.pingLoop()
    go m.reconnectHandler()
    
    logger.Info("Connected to Asterisk AMI successfully")
    
    return nil
}

// performLogin handles the login process
func (m *Manager) performLogin() error {
    logger.Debug("Performing AMI login", "username", m.config.Username)
    
    // Build login action
    loginAction := fmt.Sprintf("Action: Login\r\nUsername: %s\r\nSecret: %s\r\n\r\n",
        m.config.Username, m.config.Password)
    
    // Send login
    if _, err := m.writer.WriteString(loginAction); err != nil {
        return errors.Wrap(err, errors.ErrInternal, "failed to send login")
    }
    
    if err := m.writer.Flush(); err != nil {
        return errors.Wrap(err, errors.ErrInternal, "failed to flush login")
    }
    
    // Wait for response
    timeout := time.NewTimer(m.config.ActionTimeout)
    defer timeout.Stop()
    
    for {
        select {
        case event := <-m.loginChan:
            if response, ok := event["Response"]; ok {
                if response == "Success" {
                    logger.Debug("AMI login successful")
                    return nil
                } else if response == "Error" {
                    msg := event["Message"]
                    if msg == "" {
                        msg = "Authentication failed"
                    }
                    return errors.New(errors.ErrAuthFailed, msg)
                }
            }
        case <-timeout.C:
            return errors.New(errors.ErrAGITimeout, "login timeout")
        }
    }
}

// Close closes the AMI connection
func (m *Manager) Close() {
    m.mu.Lock()
    if !m.connected {
        m.mu.Unlock()
        return
    }
    
    m.connected = false
    m.loggedIn = false
    
    // Close shutdown channel
    close(m.shutdown)
    
    // Close connection
    if m.conn != nil {
        m.conn.Close()
    }
    m.mu.Unlock()
    
    // Wait for goroutines
    done := make(chan struct{})
    go func() {
        m.wg.Wait()
        close(done)
    }()
    
    select {
    case <-done:
        logger.Info("AMI manager closed gracefully")
    case <-time.After(5 * time.Second):
        logger.Warn("AMI manager close timeout")
    }
}

// SendAction sends an AMI action
func (m *Manager) SendAction(action Action) (Event, error) {
    m.mu.RLock()
    if !m.connected {
        m.mu.RUnlock()
        return nil, errors.New(errors.ErrInternal, "not connected to AMI")
    }
    if action.Action != "Login" && !m.loggedIn {
        m.mu.RUnlock()
        return nil, errors.New(errors.ErrInternal, "not logged in to AMI")
    }
    m.mu.RUnlock()
    
    // Generate action ID
    actionID := fmt.Sprintf("%d", atomic.AddUint64(&m.actionID, 1))
    action.ActionID = actionID
    
    // Create response channel
    responseChan := make(chan Event, 1)
    
    m.actionMutex.Lock()
    m.pendingActions[actionID] = responseChan
    m.actionMutex.Unlock()
    
    defer func() {
        m.actionMutex.Lock()
        delete(m.pendingActions, actionID)
        m.actionMutex.Unlock()
        close(responseChan)
    }()
    
    // Build action
    var sb strings.Builder
    sb.WriteString(fmt.Sprintf("Action: %s\r\n", action.Action))
    sb.WriteString(fmt.Sprintf("ActionID: %s\r\n", actionID))
    
    for key, value := range action.Fields {
        sb.WriteString(fmt.Sprintf("%s: %s\r\n", key, value))
    }
    sb.WriteString("\r\n")
    
    // Send action
    m.mu.Lock()
    _, err := m.writer.WriteString(sb.String())
    if err != nil {
        m.mu.Unlock()
        return nil, errors.Wrap(err, errors.ErrInternal, "failed to write AMI action")
    }
    
    err = m.writer.Flush()
    m.mu.Unlock()
    
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrInternal, "failed to flush AMI action")
    }
    
    atomic.AddUint64(&m.totalActions, 1)
    
    // Wait for response
    timer := time.NewTimer(m.config.ActionTimeout)
    defer timer.Stop()
    
    select {
    case response := <-responseChan:
        return response, nil
    case <-timer.C:
        atomic.AddUint64(&m.failedActions, 1)
        return nil, errors.New(errors.ErrAGITimeout, "AMI action timeout")
    case <-m.shutdown:
        return nil, errors.New(errors.ErrInternal, "AMI manager shutting down")
    }
}

// eventReader reads events from AMI
func (m *Manager) eventReader() {
    defer m.wg.Done()
    
    for {
        select {
        case <-m.shutdown:
            return
        default:
            event, err := m.readEvent()
            if err != nil {
                if !strings.Contains(err.Error(), "use of closed network connection") {
                    logger.Error("Failed to read AMI event", "error", err.Error())
                }
                
                // Trigger reconnect
                select {
                case m.reconnectChan <- struct{}{}:
                default:
                }
                return
            }
            
            if event != nil {
                atomic.AddUint64(&m.totalEvents, 1)
                
                // Check if this is a login response (no ActionID)
                if response, hasResponse := event["Response"]; hasResponse {
                fmt.Println(response)
                    if _, hasActionID := event["ActionID"]; !hasActionID {
                        // This is a login response
                        select {
                        case m.loginChan <- event:
                        default:
                        }
                        continue
                    }
                }
                
                // Handle action responses
                if actionID, ok := event["ActionID"]; ok && actionID != "" {
                    m.actionMutex.Lock()
                    if ch, exists := m.pendingActions[actionID]; exists {
                        select {
                        case ch <- event:
                        default:
                        }
                    }
                    m.actionMutex.Unlock()
                }
                
                // Send to general event channel
                select {
                case m.eventChan <- event:
                case <-time.After(100 * time.Millisecond):
                    logger.Warn("AMI event channel full, dropping event")
                }
                
                // Handle registered handlers
                if eventType, ok := event["Event"]; ok {
                    m.handleEvent(eventType, event)
                }
            }
        }
    }
}

// readEvent reads a single event from AMI
func (m *Manager) readEvent() (Event, error) {
    event := make(Event)
    
    for {
        // Set read deadline
        if m.config.ReadTimeout > 0 {
            m.conn.SetReadDeadline(time.Now().Add(m.config.ReadTimeout))
        }
        
        line, err := m.reader.ReadString('\n')
        if err != nil {
            return nil, err
        }
        
        line = strings.TrimSpace(line)
        
        // Empty line = end of event
        if line == "" {
            if len(event) > 0 {
                return event, nil
            }
            continue
        }
        
        // Parse key: value
        if idx := strings.Index(line, ":"); idx > 0 {
            key := strings.TrimSpace(line[:idx])
            value := strings.TrimSpace(line[idx+1:])
            event[key] = value
        }
    }
}

// handleEvent calls registered event handlers
func (m *Manager) handleEvent(eventType string, event Event) {
    m.mu.RLock()
    handlers := m.eventHandlers[eventType]
    m.mu.RUnlock()
    
    for _, handler := range handlers {
        go func(h EventHandler) {
            defer func() {
                if r := recover(); r != nil {
                    logger.Error("Event handler panic", "event", eventType, "panic", r)
                }
            }()
            h(event)
        }(handler)
    }
}

// pingLoop sends periodic pings
func (m *Manager) pingLoop() {
    defer m.wg.Done()
    
    ticker := time.NewTicker(m.config.PingInterval)
    defer ticker.Stop()
    
    for {
        select {
        case <-m.shutdown:
            return
        case <-ticker.C:
            if _, err := m.SendAction(Action{Action: "Ping"}); err != nil {
                logger.Warn("AMI ping failed", "error", err.Error())
            }
        }
    }
}

// reconnectHandler handles reconnection
func (m *Manager) reconnectHandler() {
    defer m.wg.Done()
    
    for {
        select {
        case <-m.shutdown:
            return
        case <-m.reconnectChan:
            logger.Info("AMI reconnection triggered")
            
            m.mu.Lock()
            m.connected = false
            m.loggedIn = false
            if m.conn != nil {
                m.conn.Close()
            }
            m.mu.Unlock()
            
            time.Sleep(m.config.ReconnectInterval)
            
            select {
            case <-m.shutdown:
                return
            default:
                ctx := context.Background()
                if err := m.Connect(ctx); err != nil {
                    logger.Error("AMI reconnection failed", "error", err.Error())
                    select {
                    case m.reconnectChan <- struct{}{}:
                    default:
                    }
                }
            }
        }
    }
}

// Helper methods

// IsConnected returns connection status
func (m *Manager) IsConnected() bool {
    m.mu.RLock()
    defer m.mu.RUnlock()
    return m.connected
}

// IsLoggedIn returns login status
func (m *Manager) IsLoggedIn() bool {
    m.mu.RLock()
    defer m.mu.RUnlock()
    return m.loggedIn
}

// RegisterEventHandler registers an event handler
func (m *Manager) RegisterEventHandler(eventType string, handler EventHandler) {
    m.mu.Lock()
    defer m.mu.Unlock()
    m.eventHandlers[eventType] = append(m.eventHandlers[eventType], handler)
}

// UnregisterEventHandler removes event handlers
func (m *Manager) UnregisterEventHandler(eventType string, handlerID string) {
    m.mu.Lock()
    defer m.mu.Unlock()
    delete(m.eventHandlers, eventType)
}

// GetStats returns AMI statistics
func (m *Manager) GetStats() map[string]interface{} {
    return map[string]interface{}{
        "total_events":   atomic.LoadUint64(&m.totalEvents),
        "total_actions":  atomic.LoadUint64(&m.totalActions),
        "failed_actions": atomic.LoadUint64(&m.failedActions),
        "connected":      m.IsConnected(),
        "logged_in":      m.IsLoggedIn(),
    }
}

// EventChannel returns the event channel
func (m *Manager) EventChannel() <-chan Event {
    return m.eventChan
}

// ConnectWithRetry attempts connection with retries
func (m *Manager) ConnectWithRetry(ctx context.Context, maxRetries int) error {
    var lastErr error
    
    for i := 0; i < maxRetries; i++ {
        if i > 0 {
            logger.Info("Retrying AMI connection", "attempt", i+1, "max", maxRetries)
            time.Sleep(m.config.ReconnectInterval)
        }
        
        err := m.Connect(ctx)
        if err == nil {
            return nil
        }
        
        lastErr = err
        logger.Warn("AMI connection attempt failed", "attempt", i+1, "error", err)
    }
    
    return lastErr
}

// ConnectOptional attempts connection without failing
func (m *Manager) ConnectOptional(ctx context.Context) {
    go func() {
        for {
            select {
            case <-ctx.Done():
                return
            default:
                if !m.IsConnected() {
                    if err := m.Connect(ctx); err != nil {
                        logger.Debug("AMI connection failed, will retry", "error", err)
                        time.Sleep(m.config.ReconnectInterval)
                        continue
                    }
                    logger.Info("AMI connected successfully")
                }
                time.Sleep(30 * time.Second)
            }
        }
    }()
}

// ARA-specific commands

// ReloadPJSIP reloads PJSIP configuration
func (m *Manager) ReloadPJSIP() error {
    action := Action{
        Action: "Command",
        Fields: map[string]string{
            "Command": "pjsip reload",
        },
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return err
    }
    
    if response["Response"] != "Success" {
        return errors.New(errors.ErrInternal, "PJSIP reload failed")
    }
    
    logger.Info("PJSIP configuration reloaded")
    return nil
}

// ReloadDialplan reloads dialplan
func (m *Manager) ReloadDialplan() error {
    action := Action{
        Action: "Command",
        Fields: map[string]string{
            "Command": "dialplan reload",
        },
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return err
    }
    
    if response["Response"] != "Success" {
        return errors.New(errors.ErrInternal, "Dialplan reload failed")
    }
    
    logger.Info("Dialplan reloaded")
    return nil
}

// ShowChannels returns active channels
func (m *Manager) ShowChannels() ([]map[string]string, error) {
    action := Action{
        Action: "CoreShowChannels",
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return nil, err
    }
    
    if response["Response"] != "Success" {
        return nil, errors.New(errors.ErrInternal, "Failed to get channels")
    }
    
    var channels []map[string]string
    completeChan := make(chan bool, 1)
    
    handler := func(event Event) {
        if event["Event"] == "CoreShowChannel" {
            channels = append(channels, event)
        } else if event["Event"] == "CoreShowChannelsComplete" {
            select {
            case completeChan <- true:
            default:
            }
        }
    }
    
    m.RegisterEventHandler("CoreShowChannel", handler)
    m.RegisterEventHandler("CoreShowChannelsComplete", handler)
    
    defer func() {
        m.UnregisterEventHandler("CoreShowChannel", "")
        m.UnregisterEventHandler("CoreShowChannelsComplete", "")
    }()
    
    select {
    case <-completeChan:
        return channels, nil
    case <-time.After(5 * time.Second):
        return channels, nil
    }
}

// HangupChannel hangs up a channel
func (m *Manager) HangupChannel(channel string, cause int) error {
    action := Action{
        Action: "Hangup",
        Fields: map[string]string{
            "Channel": channel,
            "Cause":   fmt.Sprintf("%d", cause),
        },
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return err
    }
    
    if response["Response"] != "Success" {
        return errors.New(errors.ErrInternal, "Failed to hangup channel")
    }
    
    return nil
}

// Additional helper methods for other AMI actions...
// (GetVar, SetVar, OriginateCall, QueueStatus, etc. remain the same)

// GetVar gets a global variable
func (m *Manager) GetVar(variable string) (string, error) {
    action := Action{
        Action: "GetVar",
        Fields: map[string]string{
            "Variable": variable,
        },
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return "", err
    }
    
    if response["Response"] != "Success" {
        return "", errors.New(errors.ErrInternal, "GetVar failed")
    }
    
    return response["Value"], nil
}

// SetVar sets a global variable
func (m *Manager) SetVar(variable, value string) error {
    action := Action{
        Action: "SetVar",
        Fields: map[string]string{
            "Variable": variable,
            "Value":    value,
        },
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return err
    }
    
    if response["Response"] != "Success" {
        return errors.New(errors.ErrInternal, "SetVar failed")
    }
    
    return nil
}

// QueueStatus gets queue status
func (m *Manager) QueueStatus(queue string) ([]Event, error) {
    fields := make(map[string]string)
    if queue != "" {
        fields["Queue"] = queue
    }
    
    action := Action{
        Action: "QueueStatus",
        Fields: fields,
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return nil, err
    }
    
    if response["Response"] != "Success" {
        return nil, errors.New(errors.ErrInternal, "QueueStatus failed")
    }
    
    // Collect queue events
    var events []Event
    timeout := time.After(5 * time.Second)
    
    for {
        select {
        case event := <-m.eventChan:
            eventType := event["Event"]
            if eventType == "QueueParams" || eventType == "QueueMember" || eventType == "QueueEntry" {
                events = append(events, event)
            } else if eventType == "QueueStatusComplete" {
                return events, nil
            }
        case <-timeout:
            return events, nil
        }
    }
}


package ara

import (
    "context"
    "database/sql"
    "fmt"
    "strings"
    "time"
    
    "github.com/hamzaKhattat/ara-production-system/internal/models"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
)

type Manager struct {
    db    *sql.DB
    cache CacheInterface
}

type CacheInterface interface {
    Get(ctx context.Context, key string, dest interface{}) error
    Set(ctx context.Context, key string, value interface{}, expiration time.Duration) error
    Delete(ctx context.Context, keys ...string) error
}

func NewManager(db *sql.DB, cache CacheInterface) *Manager {
    return &Manager{
        db:    db,
        cache: cache,
    }
}

func (m *Manager) CreateEndpoint(ctx context.Context, provider *models.Provider) error {
    log := logger.WithContext(ctx)
    
    // Start transaction
    tx, err := m.db.BeginTx(ctx, nil)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
    }
    defer tx.Rollback()
    
    endpointID := fmt.Sprintf("endpoint-%s", provider.Name)
    authID := fmt.Sprintf("auth-%s", provider.Name)
    aorID := fmt.Sprintf("aor-%s", provider.Name)
    
    // Create/update AOR
    aorQuery := `
        INSERT INTO ps_aors (id, max_contacts, remove_existing, qualify_frequency)
        VALUES (?, 1, 'yes', ?)
        ON DUPLICATE KEY UPDATE
            qualify_frequency = VALUES(qualify_frequency)`
    
    qualifyFreq := 60
    if provider.HealthCheckEnabled {
        qualifyFreq = 30
    }
    
    if _, err := tx.ExecContext(ctx, aorQuery, aorID, qualifyFreq); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to create AOR")
    }
    
    // Create/update Auth if using credentials
    if provider.AuthType == "credentials" || provider.AuthType == "both" {
        authQuery := `
            INSERT INTO ps_auths (id, auth_type, username, password, realm)
            VALUES (?, 'userpass', ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                username = VALUES(username),
                password = VALUES(password)`
        
        realm := provider.Host
        if _, err := tx.ExecContext(ctx, authQuery, authID, provider.Username, provider.Password, realm); err != nil {
            return errors.Wrap(err, errors.ErrDatabase, "failed to create auth")
        }
    }
    
    // Create/update Endpoint
    codecs := strings.Join(provider.Codecs, ",")
    if codecs == "" {
        codecs = "ulaw,alaw"
    }
    
    // Determine context based on provider type
    context := fmt.Sprintf("from-provider-%s", provider.Type)
    
    // CRITICAL: Set identify_by correctly based on auth type
    identifyBy := "username"
    if provider.AuthType == "ip" {
        identifyBy = "ip"
    } else if provider.AuthType == "both" {
        identifyBy = "username,ip"
    }
    
    // Build endpoint query
    endpointQuery := `
        INSERT INTO ps_endpoints (
            id, transport, aors, auth, context, 
            disallow, allow, direct_media, trust_id_inbound, trust_id_outbound,
            send_pai, send_rpid, rtp_symmetric, force_rport, rewrite_contact,
            timers, timers_min_se, timers_sess_expires, dtmf_mode,
            media_encryption, rtp_timeout, rtp_timeout_hold, identify_by
        ) VALUES (
            ?, 'transport-udp', ?, ?, ?,
            'all', ?, 'no', 'yes', 'yes',
            'yes', 'yes', 'yes', 'yes', 'yes',
            'yes', 90, 1800, 'rfc4733',
            'no', 120, 60, ?
        )
        ON DUPLICATE KEY UPDATE
            transport = VALUES(transport),
            aors = VALUES(aors),
            auth = VALUES(auth),
            context = VALUES(context),
            allow = VALUES(allow),
            direct_media = VALUES(direct_media),
            identify_by = VALUES(identify_by)`
    
    authRef := ""
    if provider.AuthType == "credentials" || provider.AuthType == "both" {
        authRef = authID
    }
    
    if _, err := tx.ExecContext(ctx, endpointQuery, endpointID, aorID, authRef, context, codecs, identifyBy); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to create endpoint")
    }
    
    // Create IP-based authentication if needed
    if provider.AuthType == "ip" || provider.AuthType == "both" {
        // Remove any existing entries first
        deleteQuery := `DELETE FROM ps_endpoint_id_ips WHERE endpoint = ?`
        if _, err := tx.ExecContext(ctx, deleteQuery, endpointID); err != nil {
            log.WithError(err).Warn("Failed to delete existing IP identifiers")
        }
        
        ipQuery := `
            INSERT INTO ps_endpoint_id_ips (id, endpoint, ` + "`match`" + `, srv_lookups)
            VALUES (?, ?, ?, 'yes')`
        
        ipID := fmt.Sprintf("ip-%s", provider.Name)
        // Use just the IP address without CIDR notation for exact match
        match := provider.Host
        
        if _, err := tx.ExecContext(ctx, ipQuery, ipID, endpointID, match); err != nil {
            return errors.Wrap(err, errors.ErrDatabase, "failed to create IP auth")
        }
        
        log.WithFields(map[string]interface{}{
            "endpoint": endpointID,
            "ip_match": match,
            "identify_by": identifyBy,
        }).Debug("Created IP identifier")
    }
    
    // Commit transaction
    if err := tx.Commit(); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to commit transaction")
    }
    
    // Clear cache
    m.cache.Delete(ctx, fmt.Sprintf("endpoint:%s", provider.Name))
    
    log.WithFields(map[string]interface{}{
        "provider": provider.Name,
        "auth_type": provider.AuthType,
        "endpoint_id": endpointID,
        "identify_by": identifyBy,
    }).Info("ARA endpoint created/updated")
    
    return nil
}

// DeleteEndpoint removes PJSIP endpoint from ARA
func (m *Manager) DeleteEndpoint(ctx context.Context, providerName string) error {
    tx, err := m.db.BeginTx(ctx, nil)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
    }
    defer tx.Rollback()
    
    endpointID := fmt.Sprintf("endpoint-%s", providerName)
    authID := fmt.Sprintf("auth-%s", providerName)
    aorID := fmt.Sprintf("aor-%s", providerName)
    ipID := fmt.Sprintf("ip-%s", providerName)
    
    // Delete in reverse order
    queries := []string{
        fmt.Sprintf("DELETE FROM ps_endpoint_id_ips WHERE id = '%s'", ipID),
        fmt.Sprintf("DELETE FROM ps_endpoints WHERE id = '%s'", endpointID),
        fmt.Sprintf("DELETE FROM ps_auths WHERE id = '%s'", authID),
        fmt.Sprintf("DELETE FROM ps_aors WHERE id = '%s'", aorID),
    }
    
    for _, query := range queries {
        if _, err := tx.ExecContext(ctx, query); err != nil {
            logger.WithContext(ctx).WithError(err).Warn("Failed to delete ARA component")
        }
    }
    
    if err := tx.Commit(); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to commit transaction")
    }
    
    // Clear cache
    m.cache.Delete(ctx, fmt.Sprintf("endpoint:%s", providerName))
    
    return nil
}

// CreateDialplan creates the complete dialplan in ARA
func (m *Manager) CreateDialplan(ctx context.Context) error {
    log := logger.WithContext(ctx)
    
    // Clear existing dialplan for our contexts
    contexts := []string{
        "from-provider-inbound",
        "from-provider-intermediate",
        "from-provider-final",
        "router-outbound",
        "router-internal",
        "hangup-handler",
        "sub-recording",
    }
    
    tx, err := m.db.BeginTx(ctx, nil)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
    }
    defer tx.Rollback()
    
    // Clear existing extensions
    for _, context := range contexts {
        if _, err := tx.ExecContext(ctx, "DELETE FROM extensions WHERE context = ?", context); err != nil {
            log.WithError(err).Warn("Failed to clear context")
        }
    }
    
    // Create inbound context (from S1)
    inboundExtensions := []DialplanExtension{
        {Exten: "_X.", Priority: 1, App: "NoOp", AppData: "Incoming call from S1: ${CALLERID(num)} -> ${EXTEN}"},
        {Exten: "_X.", Priority: 2, App: "Set", AppData: "CHANNEL(hangup_handler_push)=hangup-handler,s,1"},
        {Exten: "_X.", Priority: 3, App: "Set", AppData: "__CALLID=${UNIQUEID}"},
        {Exten: "_X.", Priority: 4, App: "Set", AppData: "__INBOUND_PROVIDER=${CHANNEL(endpoint)}"},
        {Exten: "_X.", Priority: 5, App: "Set", AppData: "__ORIGINAL_ANI=${CALLERID(num)}"},
        {Exten: "_X.", Priority: 6, App: "Set", AppData: "__ORIGINAL_DNIS=${EXTEN}"},
        {Exten: "_X.", Priority: 7, App: "Set", AppData: "__SOURCE_IP=${CHANNEL(pjsip,remote_addr)}"},
        {Exten: "_X.", Priority: 8, App: "Set", AppData: "CDR(inbound_provider)=${INBOUND_PROVIDER}"},
        {Exten: "_X.", Priority: 9, App: "Set", AppData: "CDR(original_ani)=${ORIGINAL_ANI}"},
        {Exten: "_X.", Priority: 10, App: "Set", AppData: "CDR(original_dnis)=${ORIGINAL_DNIS}"},
        {Exten: "_X.", Priority: 11, App: "MixMonitor", AppData: "${UNIQUEID}.wav,b,/usr/local/bin/post-recording.sh ${UNIQUEID}"},
        {Exten: "_X.", Priority: 12, App: "AGI", AppData: "agi://localhost:4573/processIncoming"},
        {Exten: "_X.", Priority: 13, App: "GotoIf", AppData: "$[\"${ROUTER_STATUS}\" = \"success\"]?route:failed"},
        {Exten: "_X.", Priority: 14, App: "Hangup", AppData: "21", Label: "failed"},
        {Exten: "_X.", Priority: 15, App: "Set", AppData: "CALLERID(num)=${ANI_TO_SEND}", Label: "route"},
        {Exten: "_X.", Priority: 16, App: "Set", AppData: "CDR(intermediate_provider)=${INTERMEDIATE_PROVIDER}"},
        {Exten: "_X.", Priority: 17, App: "Set", AppData: "CDR(assigned_did)=${DID_ASSIGNED}"},
        {Exten: "_X.", Priority: 18, App: "Dial", AppData: "PJSIP/${DNIS_TO_SEND}@${NEXT_HOP},180,U(sub-recording^${UNIQUEID})"},
        {Exten: "_X.", Priority: 19, App: "Set", AppData: "CDR(sip_response)=${HANGUPCAUSE}"},
        {Exten: "_X.", Priority: 20, App: "GotoIf", AppData: "$[\"${DIALSTATUS}\" = \"ANSWER\"]?end:failed"},
        {Exten: "_X.", Priority: 21, App: "Hangup", AppData: "", Label: "end"},
    }
    
    if err := m.insertExtensions(tx, "from-provider-inbound", inboundExtensions); err != nil {
        return err
    }
    
    // Create intermediate context (from S3)
    intermediateExtensions := []DialplanExtension{
        {Exten: "_X.", Priority: 1, App: "NoOp", AppData: "Return call from S3: ${CALLERID(num)} -> ${EXTEN}"},
        {Exten: "_X.", Priority: 2, App: "Set", AppData: "__INTERMEDIATE_PROVIDER=${CHANNEL(endpoint)}"},
        {Exten: "_X.", Priority: 3, App: "Set", AppData: "__SOURCE_IP=${CHANNEL(pjsip,remote_addr)}"},
        {Exten: "_X.", Priority: 4, App: "Set", AppData: "CDR(intermediate_return)=true"},
        {Exten: "_X.", Priority: 5, App: "AGI", AppData: "agi://localhost:4573/processReturn"},
        {Exten: "_X.", Priority: 6, App: "GotoIf", AppData: "$[\"${ROUTER_STATUS}\" = \"success\"]?route:failed"},
        {Exten: "_X.", Priority: 7, App: "Hangup", AppData: "21", Label: "failed"},
        {Exten: "_X.", Priority: 8, App: "Set", AppData: "CALLERID(num)=${ANI_TO_SEND}", Label: "route"},
        {Exten: "_X.", Priority: 9, App: "Set", AppData: "CDR(final_provider)=${FINAL_PROVIDER}"},
        {Exten: "_X.", Priority: 10, App: "Dial", AppData: "PJSIP/${DNIS_TO_SEND}@${NEXT_HOP},180"},
        {Exten: "_X.", Priority: 11, App: "Set", AppData: "CDR(final_sip_response)=${HANGUPCAUSE}"},
        {Exten: "_X.", Priority: 12, App: "Hangup", AppData: ""},
    }
    
    if err := m.insertExtensions(tx, "from-provider-intermediate", intermediateExtensions); err != nil {
        return err
    }
    
    // Create final context (from S4)
    finalExtensions := []DialplanExtension{
        {Exten: "_X.", Priority: 1, App: "NoOp", AppData: "Final call from S4: ${CALLERID(num)} -> ${EXTEN}"},
        {Exten: "_X.", Priority: 2, App: "Set", AppData: "__FINAL_PROVIDER=${CHANNEL(endpoint)}"},
        {Exten: "_X.", Priority: 3, App: "Set", AppData: "__SOURCE_IP=${CHANNEL(pjsip,remote_addr)}"},
        {Exten: "_X.", Priority: 4, App: "Set", AppData: "CDR(final_confirmation)=true"},
        {Exten: "_X.", Priority: 5, App: "AGI", AppData: "agi://localhost:4573/processFinal"},
        {Exten: "_X.", Priority: 6, App: "Congestion", AppData: "5"},
        {Exten: "_X.", Priority: 7, App: "Hangup", AppData: ""},
    }
    
    if err := m.insertExtensions(tx, "from-provider-final", finalExtensions); err != nil {
        return err
    }
    
    // Create hangup handler
    hangupExtensions := []DialplanExtension{
        {Exten: "s", Priority: 1, App: "NoOp", AppData: "Call ended: ${UNIQUEID}"},
        {Exten: "s", Priority: 2, App: "Set", AppData: "CDR(end_time)=${EPOCH}"},
        {Exten: "s", Priority: 3, App: "Set", AppData: "CDR(duration)=${CDR(billsec)}"},
        {Exten: "s", Priority: 4, App: "AGI", AppData: "agi://localhost:4573/hangup"},
        {Exten: "s", Priority: 5, App: "Return", AppData: ""},
    }
    
    if err := m.insertExtensions(tx, "hangup-handler", hangupExtensions); err != nil {
        return err
    }
    
    // Create recording subroutine
    recordingExtensions := []DialplanExtension{
        {Exten: "s", Priority: 1, App: "NoOp", AppData: "Starting recording on originated channel"},
        {Exten: "s", Priority: 2, App: "Set", AppData: "AUDIOHOOK_INHERIT(MixMonitor)=yes"},
        {Exten: "s", Priority: 3, App: "MixMonitor", AppData: "${ARG1}-out.wav,b"},
        {Exten: "s", Priority: 4, App: "Return", AppData: ""},
    }
    
    if err := m.insertExtensions(tx, "sub-recording", recordingExtensions); err != nil {
        return err
    }
    
    if err := tx.Commit(); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to commit dialplan")
    }
    
    // Clear dialplan cache
    m.cache.Delete(ctx, "dialplan:*")
    
    log.Info("Dialplan created successfully in ARA")
    return nil
}

// DialplanExtension represents a dialplan extension
type DialplanExtension struct {
    Exten    string
    Priority int
    App      string
    AppData  string
    Label    string // For Asterisk labels
}

func (m *Manager) insertExtensions(tx *sql.Tx, context string, extensions []DialplanExtension) error {
    stmt, err := tx.Prepare(`
        INSERT INTO extensions (context, exten, priority, app, appdata)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            app = VALUES(app),
            appdata = VALUES(appdata)`)
    
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to prepare statement")
    }
    defer stmt.Close()
    
    for _, ext := range extensions {
        if _, err := stmt.Exec(context, ext.Exten, ext.Priority, ext.App, ext.AppData); err != nil {
            return errors.Wrap(err, errors.ErrDatabase, fmt.Sprintf("failed to insert extension %s@%s", ext.Exten, context))
        }
    }
    
    return nil
}

func (m *Manager) GetEndpoint(ctx context.Context, name string) (*Endpoint, error) {
    cacheKey := fmt.Sprintf("endpoint:%s", name)
    
    // Try cache first
    var endpoint Endpoint
    if err := m.cache.Get(ctx, cacheKey, &endpoint); err == nil {
        return &endpoint, nil
    }
    
    // Query database
    query := `
        SELECT e.id, e.transport, e.aors, e.auth, e.context, e.allow,
               e.direct_media, e.dtmf_mode, e.media_encryption,
               a.username, a.password,
               i.` + "`match`" + ` as ip_match
        FROM ps_endpoints e
        LEFT JOIN ps_auths a ON e.auth = a.id
        LEFT JOIN ps_endpoint_id_ips i ON i.endpoint = e.id
        WHERE e.id = ?`
    
    err := m.db.QueryRowContext(ctx, query, fmt.Sprintf("endpoint-%s", name)).Scan(
        &endpoint.ID, &endpoint.Transport, &endpoint.AORs, &endpoint.Auth,
        &endpoint.Context, &endpoint.Allow, &endpoint.DirectMedia,
        &endpoint.DTMFMode, &endpoint.MediaEncryption,
        &endpoint.Username, &endpoint.Password, &endpoint.IPMatch,
    )
    
    if err == sql.ErrNoRows {
        return nil, errors.New(errors.ErrProviderNotFound, "endpoint not found")
    }
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query endpoint")
    }
    
    // Cache for 5 minutes
    m.cache.Set(ctx, cacheKey, endpoint, 5*time.Minute)
    
    return &endpoint, nil
}

type Endpoint struct {
    ID              string
    Transport       string
    AORs            string
    Auth            string
    Context         string
    Allow           string
    DirectMedia     string
    DTMFMode        string
    MediaEncryption string
    Username        sql.NullString
    Password        sql.NullString
    IPMatch         sql.NullString
}

// ReloadEndpoints triggers Asterisk to reload PJSIP
func (m *Manager) ReloadEndpoints(ctx context.Context) error {
    // This would typically use AMI to reload
    // For now, we'll mark it as needing reload
    logger.WithContext(ctx).Info("PJSIP endpoints need reload")
    return nil
}

// ReloadDialplan triggers Asterisk to reload dialplan
func (m *Manager) ReloadDialplan(ctx context.Context) error {
    // This would typically use AMI to reload
    logger.WithContext(ctx).Info("Dialplan needs reload")
    return nil
}
package config

import (
    "fmt"
    "strings"
    "time"
    
    "github.com/spf13/viper"
)

// Config represents the complete application configuration
type Config struct {
    App         AppConfig         `mapstructure:"app"`
    Database    DatabaseConfig    `mapstructure:"database"`
    Redis       RedisConfig       `mapstructure:"redis"`
    AGI         AGIConfig         `mapstructure:"agi"`
    Asterisk    AsteriskConfig    `mapstructure:"asterisk"`
    Router      RouterConfig      `mapstructure:"router"`
    Monitoring  MonitoringConfig  `mapstructure:"monitoring"`
    Security    SecurityConfig    `mapstructure:"security"`
    Performance PerformanceConfig `mapstructure:"performance"`
}

// AppConfig holds application-level configuration
type AppConfig struct {
    Name        string `mapstructure:"name"`
    Version     string `mapstructure:"version"`
    Environment string `mapstructure:"environment"`
    Debug       bool   `mapstructure:"debug"`
}

// DatabaseConfig holds database configuration
type DatabaseConfig struct {
    Driver          string        `mapstructure:"driver"`
    Host            string        `mapstructure:"host"`
    Port            int           `mapstructure:"port"`
    Username        string        `mapstructure:"username"`
    Password        string        `mapstructure:"password"`
    Database        string        `mapstructure:"database"`
    MaxOpenConns    int           `mapstructure:"max_open_conns"`
    MaxIdleConns    int           `mapstructure:"max_idle_conns"`
    ConnMaxLifetime time.Duration `mapstructure:"conn_max_lifetime"`
    RetryAttempts   int           `mapstructure:"retry_attempts"`
    RetryDelay      time.Duration `mapstructure:"retry_delay"`
    SSLMode         string        `mapstructure:"ssl_mode"`
    Charset         string        `mapstructure:"charset"`
}

// RedisConfig holds Redis cache configuration
type RedisConfig struct {
    Host         string        `mapstructure:"host"`
    Port         int           `mapstructure:"port"`
    Password     string        `mapstructure:"password"`
    DB           int           `mapstructure:"db"`
    PoolSize     int           `mapstructure:"pool_size"`
    MinIdleConns int           `mapstructure:"min_idle_conns"`
    MaxRetries   int           `mapstructure:"max_retries"`
    DialTimeout  time.Duration `mapstructure:"dial_timeout"`
    ReadTimeout  time.Duration `mapstructure:"read_timeout"`
    WriteTimeout time.Duration `mapstructure:"write_timeout"`
    PoolTimeout  time.Duration `mapstructure:"pool_timeout"`
    IdleTimeout  time.Duration `mapstructure:"idle_timeout"`
}

// AGIConfig holds AGI server configuration
type AGIConfig struct {
    ListenAddress    string        `mapstructure:"listen_address"`
    Port             int           `mapstructure:"port"`
    MaxConnections   int           `mapstructure:"max_connections"`
    ReadTimeout      time.Duration `mapstructure:"read_timeout"`
    WriteTimeout     time.Duration `mapstructure:"write_timeout"`
    IdleTimeout      time.Duration `mapstructure:"idle_timeout"`
    ShutdownTimeout  time.Duration `mapstructure:"shutdown_timeout"`
    BufferSize       int           `mapstructure:"buffer_size"`
    EnableTLS        bool          `mapstructure:"enable_tls"`
    TLSCertFile      string        `mapstructure:"tls_cert_file"`
    TLSKeyFile       string        `mapstructure:"tls_key_file"`
}

// AsteriskConfig holds Asterisk-related configuration
type AsteriskConfig struct {
    AMI AMIConfig `mapstructure:"ami"`
    ARA ARAConfig `mapstructure:"ara"`
}

// AMIConfig holds Asterisk Manager Interface configuration
type AMIConfig struct {
    Enabled             bool          `mapstructure:"enabled"`
    Host                string        `mapstructure:"host"`
    Port                int           `mapstructure:"port"`
    Username            string        `mapstructure:"username"`
    Password            string        `mapstructure:"password"`
    ReconnectInterval   time.Duration `mapstructure:"reconnect_interval"`
    PingInterval        time.Duration `mapstructure:"ping_interval"`
    ActionTimeout       time.Duration `mapstructure:"action_timeout"`
    ConnectTimeout      time.Duration `mapstructure:"connect_timeout"`
    EventBufferSize     int           `mapstructure:"event_buffer_size"`
}

// ARAConfig holds Asterisk Realtime Architecture configuration
type ARAConfig struct {
    TransportReloadInterval time.Duration `mapstructure:"transport_reload_interval"`
    EndpointCacheTTL        time.Duration `mapstructure:"endpoint_cache_ttl"`
    DialplanCacheTTL        time.Duration `mapstructure:"dialplan_cache_ttl"`
    AORCacheTTL             time.Duration `mapstructure:"aor_cache_ttl"`
    AuthCacheTTL            time.Duration `mapstructure:"auth_cache_ttl"`
    EnableCache             bool          `mapstructure:"enable_cache"`
    SyncInterval            time.Duration `mapstructure:"sync_interval"`
}

// RouterConfig holds call routing configuration
type RouterConfig struct {
    DIDAllocationTimeout time.Duration        `mapstructure:"did_allocation_timeout"`
    CallCleanupInterval  time.Duration        `mapstructure:"call_cleanup_interval"`
    StaleCallTimeout     time.Duration        `mapstructure:"stale_call_timeout"`
    MaxRetries           int                  `mapstructure:"max_retries"`
    RetryBackoff         string               `mapstructure:"retry_backoff"`
    Verification         VerificationConfig   `mapstructure:"verification"`
    Recording            RecordingConfig      `mapstructure:"recording"`
    LoadBalancer         LoadBalancerConfig   `mapstructure:"load_balancer"`
}

// VerificationConfig holds call verification settings
type VerificationConfig struct {
    Enabled     bool `mapstructure:"enabled"`
    StrictMode  bool `mapstructure:"strict_mode"`
    LogFailures bool `mapstructure:"log_failures"`
    Timeout     time.Duration `mapstructure:"timeout"`
}

// RecordingConfig holds call recording settings
type RecordingConfig struct {
    Enabled    bool   `mapstructure:"enabled"`
    Path       string `mapstructure:"path"`
    Format     string `mapstructure:"format"`
    MixType    string `mapstructure:"mix_type"`
    MaxSize    int64  `mapstructure:"max_size"`
    MaxAge     int    `mapstructure:"max_age"`
}

// LoadBalancerConfig holds load balancing configuration
type LoadBalancerConfig struct {
    DefaultMode           string        `mapstructure:"default_mode"`
    HealthCheckInterval   time.Duration `mapstructure:"health_check_interval"`
    FailoverTimeout       time.Duration `mapstructure:"failover_timeout"`
    MaxFailures           int           `mapstructure:"max_failures"`
    RecoveryTime          time.Duration `mapstructure:"recovery_time"`
}

// MonitoringConfig holds monitoring and observability configuration
type MonitoringConfig struct {
    Metrics MetricsConfig `mapstructure:"metrics"`
    Health  HealthConfig  `mapstructure:"health"`
    Logging LoggingConfig `mapstructure:"logging"`
    Tracing TracingConfig `mapstructure:"tracing"`
}

// MetricsConfig holds metrics configuration
type MetricsConfig struct {
    Enabled          bool          `mapstructure:"enabled"`
    Port             int           `mapstructure:"port"`
    Path             string        `mapstructure:"path"`
    Namespace        string        `mapstructure:"namespace"`
    Subsystem        string        `mapstructure:"subsystem"`
    CollectInterval  time.Duration `mapstructure:"collect_interval"`
}

// HealthConfig holds health check configuration
type HealthConfig struct {
    Enabled             bool          `mapstructure:"enabled"`
    Port                int           `mapstructure:"port"`
    LivenessPath        string        `mapstructure:"liveness_path"`
    ReadinessPath       string        `mapstructure:"readiness_path"`
    CheckInterval       time.Duration `mapstructure:"check_interval"`
    CheckTimeout        time.Duration `mapstructure:"check_timeout"`
}

// LoggingConfig holds logging configuration
type LoggingConfig struct {
    Level      string          `mapstructure:"level"`
    Format     string          `mapstructure:"format"`
    Output     string          `mapstructure:"output"`
    File       FileLogConfig   `mapstructure:"file"`
    Fields     map[string]interface{} `mapstructure:"fields"`
}

// FileLogConfig holds file-based logging configuration
type FileLogConfig struct {
    Enabled    bool   `mapstructure:"enabled"`
    Path       string `mapstructure:"path"`
    MaxSize    int    `mapstructure:"max_size"`
    MaxBackups int    `mapstructure:"max_backups"`
    MaxAge     int    `mapstructure:"max_age"`
    Compress   bool   `mapstructure:"compress"`
}

// TracingConfig holds distributed tracing configuration
type TracingConfig struct {
    Enabled      bool    `mapstructure:"enabled"`
    Provider     string  `mapstructure:"provider"`
    Endpoint     string  `mapstructure:"endpoint"`
    ServiceName  string  `mapstructure:"service_name"`
    SampleRate   float64 `mapstructure:"sample_rate"`
}

// SecurityConfig holds security-related configuration
type SecurityConfig struct {
    TLS       TLSConfig       `mapstructure:"tls"`
    API       APIConfig       `mapstructure:"api"`
    RateLimit RateLimitConfig `mapstructure:"rate_limit"`
}

// TLSConfig holds TLS configuration
type TLSConfig struct {
    Enabled            bool     `mapstructure:"enabled"`
    CertFile           string   `mapstructure:"cert_file"`
    KeyFile            string   `mapstructure:"key_file"`
    CAFile             string   `mapstructure:"ca_file"`
    InsecureSkipVerify bool     `mapstructure:"insecure_skip_verify"`
    MinVersion         string   `mapstructure:"min_version"`
    CipherSuites       []string `mapstructure:"cipher_suites"`
}

// APIConfig holds API configuration
type APIConfig struct {
    Enabled       bool     `mapstructure:"enabled"`
    Port          int      `mapstructure:"port"`
    AuthToken     string   `mapstructure:"auth_token"`
    RateLimit     int      `mapstructure:"rate_limit"`
    CORSEnabled   bool     `mapstructure:"cors_enabled"`
    CORSOrigins   []string `mapstructure:"cors_origins"`
    ReadTimeout   time.Duration `mapstructure:"read_timeout"`
    WriteTimeout  time.Duration `mapstructure:"write_timeout"`
}

// RateLimitConfig holds rate limiting configuration
type RateLimitConfig struct {
    Enabled         bool          `mapstructure:"enabled"`
    RequestsPerMin  int           `mapstructure:"requests_per_min"`
    BurstSize       int           `mapstructure:"burst_size"`
    CleanupInterval time.Duration `mapstructure:"cleanup_interval"`
}

// PerformanceConfig holds performance tuning configuration
type PerformanceConfig struct {
    WorkerPoolSize   int           `mapstructure:"worker_pool_size"`
    QueueSize        int           `mapstructure:"queue_size"`
    BatchSize        int           `mapstructure:"batch_size"`
    GCInterval       time.Duration `mapstructure:"gc_interval"`
    MaxProcs         int           `mapstructure:"max_procs"`
    EnableProfiling  bool          `mapstructure:"enable_profiling"`
    ProfilingPort    int           `mapstructure:"profiling_port"`
}

// Load loads configuration from file and environment
func Load(configFile string) (*Config, error) {
    if configFile != "" {
        viper.SetConfigFile(configFile)
    } else {
        viper.SetConfigName("config")
        viper.SetConfigType("yaml")
        viper.AddConfigPath("./configs")
        viper.AddConfigPath("/etc/asterisk-ara-router")
        viper.AddConfigPath(".")
    }
    
    // Set environment variable support
    viper.SetEnvPrefix("ARA_ROUTER")
    viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
    viper.AutomaticEnv()
    
    // Set defaults
    setDefaults()
    
    // Read configuration
    if err := viper.ReadInConfig(); err != nil {
        if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
            return nil, fmt.Errorf("failed to read config file: %w", err)
        }
        // Config file not found; use defaults and environment
    }
    
    // Unmarshal into config struct
    var config Config
    if err := viper.Unmarshal(&config); err != nil {
        return nil, fmt.Errorf("failed to unmarshal config: %w", err)
    }
    
    // Validate configuration
    if err := config.Validate(); err != nil {
        return nil, fmt.Errorf("invalid configuration: %w", err)
    }
    
    return &config, nil
}

// setDefaults sets default configuration values
func setDefaults() {
    // App defaults
    viper.SetDefault("app.name", "asterisk-ara-router")
    viper.SetDefault("app.version", "2.0.0")
    viper.SetDefault("app.environment", "development")
    viper.SetDefault("app.debug", false)
    
    // Database defaults
    viper.SetDefault("database.driver", "mysql")
    viper.SetDefault("database.host", "localhost")
    viper.SetDefault("database.port", 3306)
    viper.SetDefault("database.username", "asterisk")
    viper.SetDefault("database.password", "asterisk")
    viper.SetDefault("database.database", "asterisk_ara")
    viper.SetDefault("database.max_open_conns", 25)
    viper.SetDefault("database.max_idle_conns", 5)
    viper.SetDefault("database.conn_max_lifetime", "5m")
    viper.SetDefault("database.retry_attempts", 3)
    viper.SetDefault("database.retry_delay", "1s")
    viper.SetDefault("database.charset", "utf8mb4")
    
    // Redis defaults
    viper.SetDefault("redis.host", "localhost")
    viper.SetDefault("redis.port", 6379)
    viper.SetDefault("redis.db", 0)
    viper.SetDefault("redis.pool_size", 10)
    viper.SetDefault("redis.min_idle_conns", 5)
    viper.SetDefault("redis.max_retries", 3)
    viper.SetDefault("redis.dial_timeout", "5s")
    viper.SetDefault("redis.read_timeout", "3s")
    viper.SetDefault("redis.write_timeout", "3s")
    
    // AGI defaults
    viper.SetDefault("agi.listen_address", "0.0.0.0")
    viper.SetDefault("agi.port", 4573)
    viper.SetDefault("agi.max_connections", 1000)
    viper.SetDefault("agi.read_timeout", "30s")
    viper.SetDefault("agi.write_timeout", "30s")
    viper.SetDefault("agi.idle_timeout", "120s")
    viper.SetDefault("agi.shutdown_timeout", "30s")
    viper.SetDefault("agi.buffer_size", 4096)
    
    // AMI defaults
    viper.SetDefault("asterisk.ami.enabled", true)
    viper.SetDefault("asterisk.ami.host", "localhost")
    viper.SetDefault("asterisk.ami.port", 5038)
    viper.SetDefault("asterisk.ami.reconnect_interval", "5s")
    viper.SetDefault("asterisk.ami.ping_interval", "30s")
    viper.SetDefault("asterisk.ami.action_timeout", "10s")
    viper.SetDefault("asterisk.ami.connect_timeout", "10s")
    viper.SetDefault("asterisk.ami.event_buffer_size", 1000)
    
    // ARA defaults
    viper.SetDefault("asterisk.ara.transport_reload_interval", "60s")
    viper.SetDefault("asterisk.ara.endpoint_cache_ttl", "300s")
    viper.SetDefault("asterisk.ara.dialplan_cache_ttl", "600s")
    viper.SetDefault("asterisk.ara.enable_cache", true)
    
    // Router defaults
    viper.SetDefault("router.did_allocation_timeout", "5s")
    viper.SetDefault("router.call_cleanup_interval", "5m")
    viper.SetDefault("router.stale_call_timeout", "30m")
    viper.SetDefault("router.max_retries", 3)
    viper.SetDefault("router.retry_backoff", "exponential")
    viper.SetDefault("router.verification.enabled", true)
    viper.SetDefault("router.verification.strict_mode", false)
    viper.SetDefault("router.verification.log_failures", true)
    viper.SetDefault("router.recording.enabled", false)
    viper.SetDefault("router.recording.format", "wav")
    viper.SetDefault("router.recording.mix_type", "both")
    viper.SetDefault("router.load_balancer.default_mode", "round_robin")
    viper.SetDefault("router.load_balancer.health_check_interval", "30s")
    
    // Monitoring defaults
    viper.SetDefault("monitoring.metrics.enabled", true)
    viper.SetDefault("monitoring.metrics.port", 9090)
    viper.SetDefault("monitoring.metrics.path", "/metrics")
    viper.SetDefault("monitoring.health.enabled", true)
    viper.SetDefault("monitoring.health.port", 8080)
    viper.SetDefault("monitoring.health.liveness_path", "/healthz")
    viper.SetDefault("monitoring.health.readiness_path", "/ready")
    viper.SetDefault("monitoring.logging.level", "info")
    viper.SetDefault("monitoring.logging.format", "json")
    viper.SetDefault("monitoring.logging.output", "stdout")
    
    // Security defaults
    viper.SetDefault("security.tls.enabled", false)
    viper.SetDefault("security.api.enabled", true)
    viper.SetDefault("security.api.port", 8081)
    viper.SetDefault("security.api.rate_limit", 100)
    viper.SetDefault("security.api.cors_enabled", true)
    
    // Performance defaults
    viper.SetDefault("performance.worker_pool_size", 100)
    viper.SetDefault("performance.queue_size", 1000)
    viper.SetDefault("performance.batch_size", 50)
    viper.SetDefault("performance.gc_interval", "1m")
}

// Validate validates the configuration
func (c *Config) Validate() error {
    // Validate database configuration
    if c.Database.Host == "" {
        return fmt.Errorf("database host is required")
    }
    if c.Database.Port <= 0 || c.Database.Port > 65535 {
        return fmt.Errorf("invalid database port: %d", c.Database.Port)
    }
    if c.Database.Username == "" {
        return fmt.Errorf("database username is required")
    }
    if c.Database.Database == "" {
        return fmt.Errorf("database name is required")
    }
    
    // Validate AGI configuration
    if c.AGI.Port <= 0 || c.AGI.Port > 65535 {
        return fmt.Errorf("invalid AGI port: %d", c.AGI.Port)
    }
    if c.AGI.MaxConnections <= 0 {
        return fmt.Errorf("AGI max connections must be positive")
    }
    
    // Validate Redis configuration if host is provided
    if c.Redis.Host != "" {
        if c.Redis.Port <= 0 || c.Redis.Port > 65535 {
            return fmt.Errorf("invalid Redis port: %d", c.Redis.Port)
        }
    }
    
    // Validate AMI configuration if enabled
    if c.Asterisk.AMI.Enabled && c.Asterisk.AMI.Host != "" {
        if c.Asterisk.AMI.Port <= 0 || c.Asterisk.AMI.Port > 65535 {
            return fmt.Errorf("invalid AMI port: %d", c.Asterisk.AMI.Port)
        }
        if c.Asterisk.AMI.Username == "" {
            return fmt.Errorf("AMI username is required when AMI is enabled")
        }
    }
    
    // Validate monitoring ports
    if c.Monitoring.Metrics.Enabled {
        if c.Monitoring.Metrics.Port <= 0 || c.Monitoring.Metrics.Port > 65535 {
            return fmt.Errorf("invalid metrics port: %d", c.Monitoring.Metrics.Port)
        }
    }
    if c.Monitoring.Health.Enabled {
        if c.Monitoring.Health.Port <= 0 || c.Monitoring.Health.Port > 65535 {
            return fmt.Errorf("invalid health port: %d", c.Monitoring.Health.Port)
        }
    }
    
    // Validate API configuration
    if c.Security.API.Enabled {
        if c.Security.API.Port <= 0 || c.Security.API.Port > 65535 {
            return fmt.Errorf("invalid API port: %d", c.Security.API.Port)
        }
    }
    
    // Validate performance settings
    if c.Performance.WorkerPoolSize <= 0 {
        return fmt.Errorf("worker pool size must be positive")
    }
    if c.Performance.QueueSize <= 0 {
        return fmt.Errorf("queue size must be positive")
    }
    
    return nil
}

// GetDSN returns the database connection string
func (c *DatabaseConfig) GetDSN() string {
    charset := c.Charset
    if charset == "" {
        charset = "utf8mb4"
    }
    
    return fmt.Sprintf("%s:%s@tcp(%s:%d)/%s?charset=%s&parseTime=true&loc=Local",
        c.Username,
        c.Password,
        c.Host,
        c.Port,
        c.Database,
        charset,
    )
}

// GetRedisAddr returns the Redis address
func (c *RedisConfig) GetRedisAddr() string {
    return fmt.Sprintf("%s:%d", c.Host, c.Port)
}

// GetAGIAddr returns the AGI server address
func (c *AGIConfig) GetAGIAddr() string {
    return fmt.Sprintf("%s:%d", c.ListenAddress, c.Port)
}

// GetAMIAddr returns the AMI server address
func (c *AMIConfig) GetAMIAddr() string {
    return fmt.Sprintf("%s:%d", c.Host, c.Port)
}

// IsProduction returns true if running in production environment
func (c *AppConfig) IsProduction() bool {
    return strings.ToLower(c.Environment) == "production"
}

// IsDevelopment returns true if running in development environment
func (c *AppConfig) IsDevelopment() bool {
    return strings.ToLower(c.Environment) == "development"
}

// IsDebug returns true if debug mode is enabled
func (c *AppConfig) IsDebug() bool {
    return c.Debug
}
package db

import (
    "context"
    "encoding/json"
    "fmt"
    "time"
    
    "github.com/go-redis/redis/v8"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
)

type CacheConfig struct {
    Host          string
    Port          int
    Password      string
    DB            int
    PoolSize      int
    MinIdleConns  int
    MaxRetries    int
}

type Cache struct {
    client *redis.Client
    prefix string
}

var (
    cacheInstance *Cache
)

func InitializeCache(cfg CacheConfig, prefix string) error {
    client := redis.NewClient(&redis.Options{
        Addr:         fmt.Sprintf("%s:%d", cfg.Host, cfg.Port),
        Password:     cfg.Password,
        DB:           cfg.DB,
        PoolSize:     cfg.PoolSize,
        MinIdleConns: cfg.MinIdleConns,
        MaxRetries:   cfg.MaxRetries,
    })
    
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()
    
    if err := client.Ping(ctx).Err(); err != nil {
        return errors.Wrap(err, errors.ErrRedis, "failed to connect to Redis")
    }
    
    cacheInstance = &Cache{
        client: client,
        prefix: prefix,
    }
    
    logger.Info("Redis cache initialized")
    return nil
}

func GetCache() *Cache {
    if cacheInstance == nil {
        // Return nil cache that doesn't error
        return &Cache{}
    }
    return cacheInstance
}

func (c *Cache) key(k string) string {
    if c.prefix != "" {
        return fmt.Sprintf("%s:%s", c.prefix, k)
    }
    return k
}

func (c *Cache) Get(ctx context.Context, key string, dest interface{}) error {
    if c.client == nil {
        return nil // Cache miss
    }
    
    val, err := c.client.Get(ctx, c.key(key)).Result()
    if err == redis.Nil {
        return nil // Cache miss
    }
    if err != nil {
        logger.WithContext(ctx).WithField("key", key).WithField("error", err.Error()).Warn("Cache get failed")
        return nil // Don't fail on cache errors
    }
    
    if err := json.Unmarshal([]byte(val), dest); err != nil {
        logger.WithContext(ctx).WithField("key", key).WithField("error", err.Error()).Warn("Cache unmarshal failed")
        return nil
    }
    
    return nil
}

func (c *Cache) Set(ctx context.Context, key string, value interface{}, expiration time.Duration) error {
    if c.client == nil {
        return nil
    }
    
    data, err := json.Marshal(value)
    if err != nil {
        return nil // Don't fail on cache errors
    }
    
    if err := c.client.Set(ctx, c.key(key), data, expiration).Err(); err != nil {
        logger.WithContext(ctx).WithField("key", key).WithField("error", err.Error()).Warn("Cache set failed")
    }
    
    return nil
}

func (c *Cache) Delete(ctx context.Context, keys ...string) error {
    if c.client == nil {
        return nil
    }
    
    fullKeys := make([]string, len(keys))
    for i, k := range keys {
        fullKeys[i] = c.key(k)
    }
    
    if err := c.client.Del(ctx, fullKeys...).Err(); err != nil {
        logger.WithContext(ctx).WithField("error", err.Error()).Warn("Cache delete failed")
    }
    
    return nil
}

// Distributed lock
func (c *Cache) Lock(ctx context.Context, key string, ttl time.Duration) (func(), error) {
    if c.client == nil {
        return func() {}, nil // No-op
    }
    
    lockKey := c.key(fmt.Sprintf("lock:%s", key))
    value := fmt.Sprintf("%d", time.Now().UnixNano())
    
    ok, err := c.client.SetNX(ctx, lockKey, value, ttl).Result()
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrRedis, "failed to acquire lock")
    }
    
    if !ok {
        return nil, errors.New(errors.ErrInternal, "lock already held")
    }
    
    // Return unlock function
    return func() {
        script := redis.NewScript(`
            if redis.call("get", KEYS[1]) == ARGV[1] then
                return redis.call("del", KEYS[1])
            else
                return 0
            end
        `)
        
        script.Run(ctx, c.client, []string{lockKey}, value)
    }, nil
}
package db

import (
    "context"
    "database/sql"
    "fmt"
    "strings"
    "sync"
    "time"
    
    _ "github.com/go-sql-driver/mysql"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
)

type Config struct {
    Driver           string
    Host             string
    Port             int
    Username         string
    Password         string
    Database         string
    MaxOpenConns     int
    MaxIdleConns     int
    ConnMaxLifetime  time.Duration
    RetryAttempts    int
    RetryDelay       time.Duration
}

type DB struct {
    *sql.DB
    cfg    Config
    mu     sync.RWMutex
    health bool
}

var (
    instance *DB
    once     sync.Once
)

func Initialize(cfg Config) error {
    var err error
    once.Do(func() {
        instance, err = newDB(cfg)
    })
    return err
}

func GetDB() *DB {
    if instance == nil {
        panic("database not initialized")
    }
    return instance
}

func newDB(cfg Config) (*DB, error) {
    dsn := fmt.Sprintf("%s:%s@tcp(%s:%d)/%s?parseTime=true&multiStatements=true&interpolateParams=true",
        cfg.Username, cfg.Password, cfg.Host, cfg.Port, cfg.Database)
    
    var db *sql.DB
    var err error
    
    // Retry connection
    for i := 0; i <= cfg.RetryAttempts; i++ {
        db, err = sql.Open(cfg.Driver, dsn)
        if err == nil {
            err = db.Ping()
            if err == nil {
                break
            }
        }
        
        if i < cfg.RetryAttempts {
            logger.WithField("attempt", i+1).WithField("error", err.Error()).Warn("Database connection failed, retrying...")
            time.Sleep(cfg.RetryDelay * time.Duration(i+1))
        }
    }
    
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to connect to database")
    }
    
    // Configure connection pool
    db.SetMaxOpenConns(cfg.MaxOpenConns)
    db.SetMaxIdleConns(cfg.MaxIdleConns)
    db.SetConnMaxLifetime(cfg.ConnMaxLifetime)
    
    wrapper := &DB{
        DB:     db,
        cfg:    cfg,
        health: true,
    }
    
    // Start health checker
    go wrapper.healthCheck()
    
    logger.Info("Database connection established")
    return wrapper, nil
}

func (db *DB) healthCheck() {
    ticker := time.NewTicker(30 * time.Second)
    defer ticker.Stop()
    
    for range ticker.C {
        ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
        err := db.PingContext(ctx)
        cancel()
        
        db.mu.Lock()
        oldHealth := db.health
        db.health = err == nil
        db.mu.Unlock()
        
        if oldHealth != db.health {
            if db.health {
                logger.Info("Database connection recovered")
            } else {
                logger.WithField("error", err.Error()).Error("Database connection lost")
            }
        }
    }
}

func (db *DB) IsHealthy() bool {
    db.mu.RLock()
    defer db.mu.RUnlock()
    return db.health
}

// Transaction with retry
func (db *DB) Transaction(ctx context.Context, fn func(*sql.Tx) error) error {
    var err error
    for i := 0; i <= db.cfg.RetryAttempts; i++ {
        err = db.transaction(ctx, fn)
        if err == nil {
            return nil
        }
        
        if !isRetryableError(err) {
            return err
        }
        
        if i < db.cfg.RetryAttempts {
            select {
            case <-ctx.Done():
                return ctx.Err()
            case <-time.After(db.cfg.RetryDelay * time.Duration(i+1)):
                logger.WithField("attempt", i+1).WithField("error", err.Error()).Warn("Transaction failed, retrying...")
            }
        }
    }
    
    return errors.Wrap(err, errors.ErrDatabase, "transaction failed after retries")
}

func (db *DB) transaction(ctx context.Context, fn func(*sql.Tx) error) error {
    tx, err := db.BeginTx(ctx, nil)
    if err != nil {
        return err
    }
    
    defer func() {
        if p := recover(); p != nil {
            tx.Rollback()
            panic(p)
        }
    }()
    
    err = fn(tx)
    if err != nil {
        tx.Rollback()
        return err
    }
    
    return tx.Commit()
}

func isRetryableError(err error) bool {
    if err == nil {
        return false
    }
    
    errStr := err.Error()
    retryableErrors := []string{
        "connection refused",
        "connection reset",
        "broken pipe",
        "timeout",
        "deadlock",
        "try restarting transaction",
    }
    
    for _, e := range retryableErrors {
        if strings.Contains(strings.ToLower(errStr), e) {
            return true
        }
    }
    
    return false
}

// Prepared statement cache
type StmtCache struct {
    mu    sync.RWMutex
    stmts map[string]*sql.Stmt
    db    *sql.DB
}

func NewStmtCache(db *sql.DB) *StmtCache {
    return &StmtCache{
        stmts: make(map[string]*sql.Stmt),
        db:    db,
    }
}

func (c *StmtCache) Prepare(query string) (*sql.Stmt, error) {
    c.mu.RLock()
    stmt, exists := c.stmts[query]
    c.mu.RUnlock()
    
    if exists {
        return stmt, nil
    }
    
    c.mu.Lock()
    defer c.mu.Unlock()
    
    // Double-check
    if stmt, exists := c.stmts[query]; exists {
        return stmt, nil
    }
    
    stmt, err := c.db.Prepare(query)
    if err != nil {
        return nil, err
    }
    
    c.stmts[query] = stmt
    return stmt, nil
}

func (c *StmtCache) Close() {
    c.mu.Lock()
    defer c.mu.Unlock()
    
    for _, stmt := range c.stmts {
        stmt.Close()
    }
    
    c.stmts = make(map[string]*sql.Stmt)
}

// RunMigrations runs database migrations
func RunMigrations(db *sql.DB) error {
    // This is a placeholder - in production you'd use golang-migrate
    // For now, just check if tables exist
    query := `SHOW TABLES LIKE 'providers'`
    var tableName string
    err := db.QueryRow(query).Scan(&tableName)
    
    if err == sql.ErrNoRows {
        // Tables don't exist, run initial schema
        logger.Info("Running initial database migration")
        // You would execute your migration SQL here
        return fmt.Errorf("please run the initial schema SQL manually")
    }
    
    return nil
}

package db

import (
    "context"
    "database/sql"
    "fmt"
    "strings"
    
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
)

// InitializeDatabase completely resets and recreates the database
func InitializeDatabase(ctx context.Context, db *sql.DB, dropExisting bool) error {
    log := logger.WithContext(ctx)
    
    if dropExisting {
        log.Warn("Dropping existing tables and data...")
        if err := dropAllTables(ctx, db); err != nil {
            return fmt.Errorf("failed to drop existing tables: %w", err)
        }
    }
    
    log.Info("Creating database schema...")
    
    // Create tables in correct order due to foreign key constraints
    if err := createCoreTables(ctx, db); err != nil {
        return fmt.Errorf("failed to create core tables: %w", err)
    }
    
    if err := createARATables(ctx, db); err != nil {
        return fmt.Errorf("failed to create ARA tables: %w", err)
    }
    
    if err := createStoredProcedures(ctx, db); err != nil {
        return fmt.Errorf("failed to create stored procedures: %w", err)
    }
    
    if err := createViews(ctx, db); err != nil {
        return fmt.Errorf("failed to create views: %w", err)
    }
    
    if err := insertInitialData(ctx, db); err != nil {
        return fmt.Errorf("failed to insert initial data: %w", err)
    }
    
    if err := createDialplan(ctx, db); err != nil {
        return fmt.Errorf("failed to create dialplan: %w", err)
    }
    
    log.Info("Database initialization completed successfully")
    return nil
}

func dropAllTables(ctx context.Context, db *sql.DB) error {
    // Disable foreign key checks
    if _, err := db.ExecContext(ctx, "SET FOREIGN_KEY_CHECKS = 0"); err != nil {
        return err
    }
    
    // Get all tables
    rows, err := db.QueryContext(ctx, `
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = DATABASE()
    `)
    if err != nil {
        return err
    }
    defer rows.Close()
    
    var tables []string
    for rows.Next() {
        var tableName string
        if err := rows.Scan(&tableName); err != nil {
            continue
        }
        tables = append(tables, tableName)
    }
    
    // Drop each table
    for _, table := range tables {
        if _, err := db.ExecContext(ctx, fmt.Sprintf("DROP TABLE IF EXISTS `%s`", table)); err != nil {
            logger.WithContext(ctx).WithError(err).WithField("table", table).Warn("Failed to drop table")
        }
    }
    
    // Re-enable foreign key checks
    if _, err := db.ExecContext(ctx, "SET FOREIGN_KEY_CHECKS = 1"); err != nil {
        return err
    }
    
    return nil
}

func createCoreTables(ctx context.Context, db *sql.DB) error {
    queries := []string{
        // Providers table
        `CREATE TABLE IF NOT EXISTS providers (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(100) UNIQUE NOT NULL,
            type ENUM('inbound', 'intermediate', 'final') NOT NULL,
            host VARCHAR(255) NOT NULL,
            port INT DEFAULT 5060,
            username VARCHAR(100),
            password VARCHAR(100),
            auth_type ENUM('ip', 'credentials', 'both') DEFAULT 'ip',
            transport VARCHAR(10) DEFAULT 'udp',
            codecs JSON,
            max_channels INT DEFAULT 0,
            current_channels INT DEFAULT 0,
            priority INT DEFAULT 10,
            weight INT DEFAULT 1,
            cost_per_minute DECIMAL(10,4) DEFAULT 0,
            active BOOLEAN DEFAULT TRUE,
            health_check_enabled BOOLEAN DEFAULT TRUE,
            last_health_check TIMESTAMP NULL,
            health_status VARCHAR(50) DEFAULT 'unknown',
            country VARCHAR(50),
            region VARCHAR(100),
            city VARCHAR(100),
            metadata JSON,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_type (type),
            INDEX idx_active (active),
            INDEX idx_priority (priority DESC)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // DIDs table
        `CREATE TABLE IF NOT EXISTS dids (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            number VARCHAR(20) UNIQUE NOT NULL,
            provider_id INT,
            provider_name VARCHAR(100),
            in_use BOOLEAN DEFAULT FALSE,
            destination VARCHAR(100),
            allocation_time TIMESTAMP NULL,
            released_at TIMESTAMP NULL,
            last_used_at TIMESTAMP NULL,
            usage_count BIGINT DEFAULT 0,
            country VARCHAR(50),
            city VARCHAR(100),
            rate_center VARCHAR(100),
            monthly_cost DECIMAL(10,2) DEFAULT 0,
            per_minute_cost DECIMAL(10,4) DEFAULT 0,
            metadata JSON,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_in_use (in_use),
            INDEX idx_provider (provider_name),
            INDEX idx_last_used (last_used_at),
            FOREIGN KEY (provider_id) REFERENCES providers(id) ON DELETE SET NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // Provider groups
        `CREATE TABLE IF NOT EXISTS provider_groups (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(100) UNIQUE NOT NULL,
            description TEXT,
            group_type ENUM('manual', 'regex', 'metadata', 'dynamic') NOT NULL,
            match_pattern VARCHAR(255),
            match_field VARCHAR(100),
            match_operator ENUM('equals', 'contains', 'starts_with', 'ends_with', 'regex', 'in', 'not_in'),
            match_value JSON,
            provider_type ENUM('inbound', 'intermediate', 'final', 'any') DEFAULT 'any',
            enabled BOOLEAN DEFAULT TRUE,
            priority INT DEFAULT 10,
            metadata JSON,
            member_count INT DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_type (group_type),
            INDEX idx_enabled (enabled)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // Provider group members
        `CREATE TABLE IF NOT EXISTS provider_group_members (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            group_id INT NOT NULL,
            provider_id INT NOT NULL,
            provider_name VARCHAR(100) NOT NULL,
            added_manually BOOLEAN DEFAULT FALSE,
            matched_by_rule BOOLEAN DEFAULT FALSE,
            priority_override INT,
            weight_override INT,
            metadata JSON,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY unique_group_provider (group_id, provider_id),
            INDEX idx_group (group_id),
            INDEX idx_provider (provider_id),
            FOREIGN KEY (group_id) REFERENCES provider_groups(id) ON DELETE CASCADE,
            FOREIGN KEY (provider_id) REFERENCES providers(id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // Provider routes with group support
        `CREATE TABLE IF NOT EXISTS provider_routes (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(100) UNIQUE NOT NULL,
            description TEXT,
            inbound_provider VARCHAR(100) NOT NULL,
            intermediate_provider VARCHAR(100) NOT NULL,
            final_provider VARCHAR(100) NOT NULL,
            inbound_is_group BOOLEAN DEFAULT FALSE,
            intermediate_is_group BOOLEAN DEFAULT FALSE,
            final_is_group BOOLEAN DEFAULT FALSE,
            load_balance_mode ENUM('round_robin', 'weighted', 'priority', 'failover', 'least_connections', 'response_time', 'hash') DEFAULT 'round_robin',
            priority INT DEFAULT 0,
            weight INT DEFAULT 1,
            max_concurrent_calls INT DEFAULT 0,
            current_calls INT DEFAULT 0,
            enabled BOOLEAN DEFAULT TRUE,
            failover_routes JSON,
            routing_rules JSON,
            metadata JSON,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_inbound (inbound_provider),
            INDEX idx_enabled (enabled),
            INDEX idx_priority (priority DESC)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // Call records
        `CREATE TABLE IF NOT EXISTS call_records (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            call_id VARCHAR(100) UNIQUE NOT NULL,
            original_ani VARCHAR(20) NOT NULL,
            original_dnis VARCHAR(20) NOT NULL,
            transformed_ani VARCHAR(20),
            assigned_did VARCHAR(20),
            inbound_provider VARCHAR(100),
            intermediate_provider VARCHAR(100),
            final_provider VARCHAR(100),
            route_name VARCHAR(100),
            status ENUM('INITIATED', 'ACTIVE', 'RETURNED_FROM_S3', 'ROUTING_TO_S4', 'COMPLETED', 'FAILED', 'ABANDONED', 'TIMEOUT') DEFAULT 'INITIATED',
            current_step VARCHAR(50),
            failure_reason VARCHAR(255),
            start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            answer_time TIMESTAMP NULL,
            end_time TIMESTAMP NULL,
            duration INT DEFAULT 0,
            billable_duration INT DEFAULT 0,
            recording_path VARCHAR(255),
            sip_response_code INT,
            quality_score DECIMAL(3,2),
            metadata JSON,
            INDEX idx_call_id (call_id),
            INDEX idx_status (status),
            INDEX idx_start_time (start_time),
            INDEX idx_providers (inbound_provider, intermediate_provider, final_provider),
            INDEX idx_did (assigned_did)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // Call verifications
        `CREATE TABLE IF NOT EXISTS call_verifications (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            call_id VARCHAR(100) NOT NULL,
            verification_step VARCHAR(50) NOT NULL,
            expected_ani VARCHAR(20),
            expected_dnis VARCHAR(20),
            received_ani VARCHAR(20),
            received_dnis VARCHAR(20),
            source_ip VARCHAR(45),
            expected_ip VARCHAR(45),
            verified BOOLEAN DEFAULT FALSE,
            failure_reason VARCHAR(255),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_call_id (call_id),
            INDEX idx_verified (verified),
            INDEX idx_created (created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // Provider statistics
        `CREATE TABLE IF NOT EXISTS provider_stats (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            provider_name VARCHAR(100) NOT NULL,
            stat_type ENUM('minute', 'hour', 'day') NOT NULL,
            period_start TIMESTAMP NOT NULL,
            total_calls BIGINT DEFAULT 0,
            completed_calls BIGINT DEFAULT 0,
            failed_calls BIGINT DEFAULT 0,
            total_duration BIGINT DEFAULT 0,
            avg_duration DECIMAL(10,2) DEFAULT 0,
            asr DECIMAL(5,2) DEFAULT 0,
            acd DECIMAL(10,2) DEFAULT 0,
            avg_response_time INT DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY unique_provider_period (provider_name, stat_type, period_start),
            INDEX idx_provider (provider_name),
            INDEX idx_period (period_start)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // Provider health
        `CREATE TABLE IF NOT EXISTS provider_health (
            id INT AUTO_INCREMENT PRIMARY KEY,
            provider_name VARCHAR(100) UNIQUE NOT NULL,
            health_score INT DEFAULT 100,
            latency_ms INT DEFAULT 0,
            packet_loss DECIMAL(5,2) DEFAULT 0,
            jitter_ms INT DEFAULT 0,
            active_calls INT DEFAULT 0,
            max_calls INT DEFAULT 0,
            last_success_at TIMESTAMP NULL,
            last_failure_at TIMESTAMP NULL,
            consecutive_failures INT DEFAULT 0,
            is_healthy BOOLEAN DEFAULT TRUE,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_healthy (is_healthy),
            INDEX idx_updated (updated_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // Audit log
        `CREATE TABLE IF NOT EXISTS audit_log (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            event_type VARCHAR(50) NOT NULL,
            entity_type VARCHAR(50) NOT NULL,
            entity_id VARCHAR(100),
            user_id VARCHAR(100),
            ip_address VARCHAR(45),
            action VARCHAR(50) NOT NULL,
            old_value JSON,
            new_value JSON,
            metadata JSON,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_event_type (event_type),
            INDEX idx_entity (entity_type, entity_id),
            INDEX idx_created (created_at),
            INDEX idx_user (user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    }
    
    for _, query := range queries {
        if _, err := db.ExecContext(ctx, query); err != nil {
            return fmt.Errorf("failed to execute query: %w", err)
        }
    }
    
    return nil
}

func createARATables(ctx context.Context, db *sql.DB) error {
    queries := []string{
        // PJSIP transports
        `CREATE TABLE IF NOT EXISTS ps_transports (
            id VARCHAR(40) PRIMARY KEY,
            async_operations INT DEFAULT 1,
            bind VARCHAR(40),
            ca_list_file VARCHAR(200),
            ca_list_path VARCHAR(200),
            cert_file VARCHAR(200),
            cipher VARCHAR(200),
            cos INT DEFAULT 0,
            domain VARCHAR(40),
            external_media_address VARCHAR(40),
            external_signaling_address VARCHAR(40),
            external_signaling_port INT DEFAULT 0,
            local_net VARCHAR(40),
            method VARCHAR(40),
            password VARCHAR(40),
            priv_key_file VARCHAR(200),
            protocol VARCHAR(40),
            require_client_cert VARCHAR(40),
            tos INT DEFAULT 0,
            verify_client VARCHAR(40),
            verify_server VARCHAR(40),
            allow_reload VARCHAR(3) DEFAULT 'yes',
            symmetric_transport VARCHAR(3) DEFAULT 'no'
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // PJSIP systems
        `CREATE TABLE IF NOT EXISTS ps_systems (
            id VARCHAR(40) PRIMARY KEY,
            timer_t1 INT DEFAULT 500,
            timer_b INT DEFAULT 32000,
            compact_headers VARCHAR(3) DEFAULT 'no',
            threadpool_initial_size INT DEFAULT 0,
            threadpool_auto_increment INT DEFAULT 5,
            threadpool_idle_timeout INT DEFAULT 60,
            threadpool_max_size INT DEFAULT 50,
            disable_tcp_switch VARCHAR(3) DEFAULT 'yes',
            follow_early_media_fork VARCHAR(3) DEFAULT 'yes',
            accept_multiple_sdp_answers VARCHAR(3) DEFAULT 'no',
            disable_rport VARCHAR(3) DEFAULT 'no',
            use_callerid_contact VARCHAR(3) DEFAULT 'no'
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // PJSIP endpoints
        `CREATE TABLE IF NOT EXISTS ps_endpoints (
            id VARCHAR(40) PRIMARY KEY,
            transport VARCHAR(40),
            aors VARCHAR(200),
            auth VARCHAR(100),
            context VARCHAR(40) DEFAULT 'default',
            disallow VARCHAR(200) DEFAULT 'all',
            allow VARCHAR(200),
            direct_media VARCHAR(3) DEFAULT 'yes',
            connected_line_method VARCHAR(40) DEFAULT 'invite',
            direct_media_method VARCHAR(40) DEFAULT 'invite',
            direct_media_glare_mitigation VARCHAR(40) DEFAULT 'none',
            disable_direct_media_on_nat VARCHAR(3) DEFAULT 'no',
            dtmf_mode VARCHAR(40) DEFAULT 'rfc4733',
            external_media_address VARCHAR(40),
            force_rport VARCHAR(3) DEFAULT 'yes',
            ice_support VARCHAR(3) DEFAULT 'no',
            identify_by VARCHAR(40) DEFAULT 'username,ip',
            mailboxes VARCHAR(40),
            moh_suggest VARCHAR(40) DEFAULT 'default',
            outbound_auth VARCHAR(40),
            outbound_proxy VARCHAR(40),
            rewrite_contact VARCHAR(3) DEFAULT 'no',
            rtp_ipv6 VARCHAR(3) DEFAULT 'no',
            rtp_symmetric VARCHAR(3) DEFAULT 'no',
            send_diversion VARCHAR(3) DEFAULT 'yes',
            send_pai VARCHAR(3) DEFAULT 'no',
            send_rpid VARCHAR(3) DEFAULT 'no',
            timers_min_se INT DEFAULT 90,
            timers VARCHAR(3) DEFAULT 'yes',
            timers_sess_expires INT DEFAULT 1800,
            callerid VARCHAR(40),
            callerid_privacy VARCHAR(40),
            callerid_tag VARCHAR(40),
            trust_id_inbound VARCHAR(3) DEFAULT 'no',
            trust_id_outbound VARCHAR(3) DEFAULT 'no',
            send_connected_line VARCHAR(3) DEFAULT 'yes',
            accountcode VARCHAR(20),
            language VARCHAR(10) DEFAULT 'en',
            rtp_engine VARCHAR(40) DEFAULT 'asterisk',
            dtls_verify VARCHAR(40),
            dtls_rekey VARCHAR(40),
            dtls_cert_file VARCHAR(200),
            dtls_private_key VARCHAR(200),
            dtls_cipher VARCHAR(200),
            dtls_ca_file VARCHAR(200),
            dtls_ca_path VARCHAR(200),
            dtls_setup VARCHAR(40),
            srtp_tag_32 VARCHAR(3) DEFAULT 'no',
            media_encryption VARCHAR(40) DEFAULT 'no',
            use_avpf VARCHAR(3) DEFAULT 'no',
            force_avp VARCHAR(3) DEFAULT 'no',
            media_use_received_transport VARCHAR(3) DEFAULT 'no',
            rtp_timeout INT DEFAULT 0,
            rtp_timeout_hold INT DEFAULT 0,
            rtp_keepalive INT DEFAULT 0,
            record_on_feature VARCHAR(40),
            record_off_feature VARCHAR(40),
            allow_transfer VARCHAR(3) DEFAULT 'yes',
            user_eq_phone VARCHAR(3) DEFAULT 'no',
            moh_passthrough VARCHAR(3) DEFAULT 'no',
            media_encryption_optimistic VARCHAR(3) DEFAULT 'no',
            rpid_immediate VARCHAR(3) DEFAULT 'no',
            g726_non_standard VARCHAR(3) DEFAULT 'no',
            inband_progress VARCHAR(3) DEFAULT 'no',
            call_group VARCHAR(40),
            pickup_group VARCHAR(40),
            named_call_group VARCHAR(40),
            named_pickup_group VARCHAR(40),
            device_state_busy_at INT DEFAULT 0,
            t38_udptl VARCHAR(3) DEFAULT 'no',
            t38_udptl_ec VARCHAR(40),
            t38_udptl_maxdatagram INT DEFAULT 0,
            fax_detect VARCHAR(3) DEFAULT 'no',
            fax_detect_timeout INT DEFAULT 0,
            t38_udptl_nat VARCHAR(3) DEFAULT 'no',
            t38_udptl_ipv6 VARCHAR(3) DEFAULT 'no',
            rtcp_mux VARCHAR(3) DEFAULT 'no',
            allow_overlap VARCHAR(3) DEFAULT 'yes',
            bundle VARCHAR(3) DEFAULT 'no',
            webrtc VARCHAR(3) DEFAULT 'no',
            dtls_fingerprint VARCHAR(40),
            incoming_mwi_mailbox VARCHAR(40),
            follow_early_media_fork VARCHAR(3) DEFAULT 'yes',
            accept_multiple_sdp_answers VARCHAR(3) DEFAULT 'no',
            suppress_q850_reason_headers VARCHAR(3) DEFAULT 'no',
            trust_connected_line VARCHAR(3) DEFAULT 'yes',
            send_history_info VARCHAR(3) DEFAULT 'no',
            prefer_ipv6 VARCHAR(3) DEFAULT 'no',
            bind_rtp_to_media_address VARCHAR(3) DEFAULT 'no',
            INDEX idx_identify_by (identify_by)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // PJSIP auth
        `CREATE TABLE IF NOT EXISTS ps_auths (
            id VARCHAR(40) PRIMARY KEY,
            auth_type VARCHAR(40) DEFAULT 'userpass',
            nonce_lifetime INT DEFAULT 32,
            md5_cred VARCHAR(40),
            password VARCHAR(80),
            realm VARCHAR(40),
            username VARCHAR(40)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // PJSIP AORs
        `CREATE TABLE IF NOT EXISTS ps_aors (
            id VARCHAR(40) PRIMARY KEY,
            contact VARCHAR(255),
            default_expiration INT DEFAULT 3600,
            mailboxes VARCHAR(80),
            max_contacts INT DEFAULT 1,
            minimum_expiration INT DEFAULT 60,
            remove_existing VARCHAR(3) DEFAULT 'yes',
            qualify_frequency INT DEFAULT 0,
            authenticate_qualify VARCHAR(3) DEFAULT 'no',
            maximum_expiration INT DEFAULT 7200,
            outbound_proxy VARCHAR(40),
            support_path VARCHAR(3) DEFAULT 'no',
            qualify_timeout DECIMAL(5,3) DEFAULT 3.0,
            voicemail_extension VARCHAR(40),
            remove_unavailable VARCHAR(3) DEFAULT 'no'
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // PJSIP endpoint identifiers by IP
        `CREATE TABLE IF NOT EXISTS ps_endpoint_id_ips (
            id VARCHAR(40) PRIMARY KEY,
            endpoint VARCHAR(40),
            ` + "`match`" + ` VARCHAR(80) NOT NULL,
            srv_lookups VARCHAR(3) DEFAULT 'yes',
            match_header VARCHAR(255),
            INDEX idx_endpoint (endpoint),
            INDEX idx_match (` + "`match`" + `)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // PJSIP contacts
        `CREATE TABLE IF NOT EXISTS ps_contacts (
            id VARCHAR(40) PRIMARY KEY,
            uri VARCHAR(255),
            endpoint_name VARCHAR(40),
            aor VARCHAR(40),
            qualify_frequency INT DEFAULT 0,
            user_agent VARCHAR(255)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // PJSIP globals
        `CREATE TABLE IF NOT EXISTS ps_globals (
            id VARCHAR(40) PRIMARY KEY,
            max_forwards INT DEFAULT 70,
            user_agent VARCHAR(255) DEFAULT 'Asterisk PBX',
            default_outbound_endpoint VARCHAR(40),
            debug VARCHAR(3) DEFAULT 'no',
            endpoint_identifier_order VARCHAR(40) DEFAULT 'ip,username,anonymous',
            max_initial_qualify_time INT DEFAULT 0,
            keep_alive_interval INT DEFAULT 30,
            contact_expiration_check_interval INT DEFAULT 30,
            disable_multi_domain VARCHAR(3) DEFAULT 'no',
            unidentified_request_count INT DEFAULT 5,
            unidentified_request_period INT DEFAULT 5,
            unidentified_request_prune_interval INT DEFAULT 30,
            default_from_user VARCHAR(80) DEFAULT 'asterisk',
            default_voicemail_extension VARCHAR(40),
            mwi_tps_queue_high INT DEFAULT 500,
            mwi_tps_queue_low INT DEFAULT -1,
            mwi_disable_initial_unsolicited VARCHAR(3) DEFAULT 'no',
            ignore_uri_user_options VARCHAR(3) DEFAULT 'no',
            send_contact_status_on_update_registration VARCHAR(3) DEFAULT 'no',
            default_realm VARCHAR(40),
            regcontext VARCHAR(80),
            contact_cache_expire INT DEFAULT 0,
            disable_initial_options VARCHAR(3) DEFAULT 'no',
            use_callerid_contact VARCHAR(3) DEFAULT 'no'
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // PJSIP domain aliases
        `CREATE TABLE IF NOT EXISTS ps_domain_aliases (
            id VARCHAR(40) PRIMARY KEY,
            domain VARCHAR(80),
            UNIQUE KEY domain_alias (domain)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // Extensions table for dialplan
        `CREATE TABLE IF NOT EXISTS extensions (
            id INT AUTO_INCREMENT PRIMARY KEY,
            context VARCHAR(40) NOT NULL,
            exten VARCHAR(40) NOT NULL,
            priority INT NOT NULL,
            app VARCHAR(40) NOT NULL,
            appdata VARCHAR(256),
            UNIQUE KEY context_exten_priority (context, exten, priority),
            INDEX idx_context (context),
            INDEX idx_exten (exten)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // CDR table
        `CREATE TABLE IF NOT EXISTS cdr (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            accountcode VARCHAR(20),
            src VARCHAR(80),
            dst VARCHAR(80),
            dcontext VARCHAR(80),
            clid VARCHAR(80),
            channel VARCHAR(80),
            dstchannel VARCHAR(80),
            lastapp VARCHAR(80),
            lastdata VARCHAR(80),
            start DATETIME,
            answer DATETIME,
            end DATETIME,
            duration INT,
            billsec INT,
            disposition VARCHAR(45),
            amaflags INT,
            uniqueid VARCHAR(32),
            userfield VARCHAR(255),
            peeraccount VARCHAR(20),
            linkedid VARCHAR(32),
            sequence INT,
            INDEX idx_start (start),
            INDEX idx_src (src),
            INDEX idx_dst (dst),
            INDEX idx_uniqueid (uniqueid),
            INDEX idx_accountcode (accountcode)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    }
    
    for _, query := range queries {
        if _, err := db.ExecContext(ctx, query); err != nil {
            return fmt.Errorf("failed to create ARA table: %w", err)
        }
    }
    
    return nil
}

func createStoredProcedures(ctx context.Context, db *sql.DB) error {
    procedures := []string{
        `DROP PROCEDURE IF EXISTS GetAvailableDID`,
        `CREATE PROCEDURE GetAvailableDID(
            IN p_provider_name VARCHAR(100),
            IN p_destination VARCHAR(100),
            OUT p_did VARCHAR(20)
        )
        BEGIN
            DECLARE v_did VARCHAR(20) DEFAULT NULL;
            DECLARE exit handler for sqlexception
            BEGIN
                ROLLBACK;
                SET p_did = NULL;
            END;
            
            START TRANSACTION;
            
            SELECT number INTO v_did
            FROM dids
            WHERE in_use = 0 
                AND (p_provider_name IS NULL OR provider_name = p_provider_name)
            ORDER BY IFNULL(last_used_at, '1970-01-01'), RAND()
            LIMIT 1
            FOR UPDATE SKIP LOCKED;
            
            IF v_did IS NOT NULL THEN
                UPDATE dids 
                SET in_use = 1,
                    destination = p_destination,
                    allocation_time = NOW(),
                    usage_count = IFNULL(usage_count, 0) + 1,
                    updated_at = NOW()
                WHERE number = v_did;
                
                COMMIT;
            ELSE
                ROLLBACK;
            END IF;
            
            SET p_did = v_did;
        END`,
        
        `DROP PROCEDURE IF EXISTS ReleaseDID`,
        `CREATE PROCEDURE ReleaseDID(
            IN p_did VARCHAR(20)
        )
        BEGIN
            UPDATE dids 
            SET in_use = 0,
                destination = NULL,
                allocation_time = NULL,
                released_at = NOW(),
                last_used_at = NOW()
            WHERE number = p_did;
        END`,
        
        `DROP PROCEDURE IF EXISTS UpdateProviderStats`,
        `CREATE PROCEDURE UpdateProviderStats(
            IN p_provider_name VARCHAR(100),
            IN p_call_success BOOLEAN,
            IN p_duration INT
        )
        BEGIN
            DECLARE v_current_minute TIMESTAMP;
            DECLARE v_current_hour TIMESTAMP;
            DECLARE v_current_day TIMESTAMP;
            
            SET v_current_minute = DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:00');
            SET v_current_hour = DATE_FORMAT(NOW(), '%Y-%m-%d %H:00:00');
            SET v_current_day = DATE_FORMAT(NOW(), '%Y-%m-%d 00:00:00');
            
            -- Update minute stats
            INSERT INTO provider_stats (
                provider_name, stat_type, period_start, 
                total_calls, completed_calls, failed_calls, total_duration
            ) VALUES (
                p_provider_name, 'minute', v_current_minute,
                1, IF(p_call_success, 1, 0), IF(p_call_success, 0, 1), p_duration
            )
            ON DUPLICATE KEY UPDATE
                total_calls = total_calls + 1,
                completed_calls = completed_calls + IF(p_call_success, 1, 0),
                failed_calls = failed_calls + IF(p_call_success, 0, 1),
                total_duration = total_duration + p_duration,
                asr = (completed_calls / total_calls) * 100,
                acd = IF(completed_calls > 0, total_duration / completed_calls, 0);
        END`,
    }
    
    for _, proc := range procedures {
        if _, err := db.ExecContext(ctx, proc); err != nil {
            if !strings.Contains(err.Error(), "PROCEDURE") || !strings.Contains(err.Error(), "does not exist") {
                return fmt.Errorf("failed to create procedure: %w", err)
            }
        }
    }
    
    return nil
}

func createViews(ctx context.Context, db *sql.DB) error {
    views := []string{
        `CREATE OR REPLACE VIEW v_active_calls AS
        SELECT 
            cr.call_id,
            cr.original_ani,
            cr.original_dnis,
            cr.assigned_did,
            cr.route_name,
            cr.status,
            cr.current_step,
            cr.start_time,
            TIMESTAMPDIFF(SECOND, cr.start_time, NOW()) as duration_seconds,
            cr.inbound_provider,
            cr.intermediate_provider,
            cr.final_provider
        FROM call_records cr
        WHERE cr.status IN ('INITIATED', 'ACTIVE', 'RETURNED_FROM_S3', 'ROUTING_TO_S4')
        ORDER BY cr.start_time DESC`,
        
        `CREATE OR REPLACE VIEW v_provider_summary AS
        SELECT 
            p.name,
            p.type,
            p.active,
            ph.health_score,
            ph.active_calls,
            ph.is_healthy,
            ps.total_calls as calls_today,
            ps.asr as asr_today,
            ps.acd as acd_today
        FROM providers p
        LEFT JOIN provider_health ph ON p.name = ph.provider_name
        LEFT JOIN provider_stats ps ON p.name = ps.provider_name 
            AND ps.stat_type = 'day' 
            AND DATE(ps.period_start) = CURDATE()`,
        
        `CREATE OR REPLACE VIEW v_did_utilization AS
        SELECT 
            provider_name,
            COUNT(*) as total_dids,
            SUM(CASE WHEN in_use = 1 THEN 1 ELSE 0 END) as used_dids,
            SUM(CASE WHEN in_use = 0 THEN 1 ELSE 0 END) as available_dids,
            ROUND((SUM(CASE WHEN in_use = 1 THEN 1 ELSE 0 END) / COUNT(*)) * 100, 2) as utilization_percent
        FROM dids
        GROUP BY provider_name`,
    }
    
    for _, view := range views {
        if _, err := db.ExecContext(ctx, view); err != nil {
            return fmt.Errorf("failed to create view: %w", err)
        }
    }
    
    return nil
}

func insertInitialData(ctx context.Context, db *sql.DB) error {
    // Insert initial PJSIP data
    queries := []string{
        // Create initial ps_globals entry
        `INSERT INTO ps_globals (id, endpoint_identifier_order) VALUES ('global', 'ip,username,anonymous') 
         ON DUPLICATE KEY UPDATE endpoint_identifier_order='ip,username,anonymous'`,
        
        // Create initial ps_systems entry
        `INSERT INTO ps_systems (id) VALUES ('default') ON DUPLICATE KEY UPDATE id='default'`,
        
        // Create initial transports
        `INSERT INTO ps_transports (id, bind, protocol) VALUES 
            ('transport-udp', '0.0.0.0:5060', 'udp'),
            ('transport-tcp', '0.0.0.0:5060', 'tcp'),
            ('transport-tls', '0.0.0.0:5061', 'tls')
        ON DUPLICATE KEY UPDATE id=id`,
    }
    
    for _, query := range queries {
        if _, err := db.ExecContext(ctx, query); err != nil {
            return fmt.Errorf("failed to insert initial data: %w", err)
        }
    }
    
    return nil
}

func createDialplan(ctx context.Context, db *sql.DB) error {
    // Clear existing dialplan for our contexts
    if _, err := db.ExecContext(ctx, `
        DELETE FROM extensions WHERE context IN (
            'from-provider-inbound',
            'from-provider-intermediate', 
            'from-provider-final',
            'router-outbound',
            'router-internal',
            'hangup-handler',
            'sub-recording'
        )`); err != nil {
        return fmt.Errorf("failed to clear existing dialplan: %w", err)
    }
    
    // Execute the complete dialplan SQL
    dialplanSQL := getCompleteDialplanSQL()
    if _, err := db.ExecContext(ctx, dialplanSQL); err != nil {
        return fmt.Errorf("failed to create dialplan: %w", err)
    }
    
    return nil
}

func getCompleteDialplanSQL() string {
    return `
-- INBOUND CONTEXT (from S1 providers)
INSERT INTO extensions (context, exten, priority, app, appdata) VALUES
('from-provider-inbound', '_X.', 1, 'NoOp', 'Incoming call from S1: ${CALLERID(num)} -> ${EXTEN}'),
('from-provider-inbound', '_X.', 2, 'Set', 'CHANNEL(hangup_handler_push)=hangup-handler,s,1'),
('from-provider-inbound', '_X.', 3, 'Set', '__CALLID=${UNIQUEID}'),
('from-provider-inbound', '_X.', 4, 'Set', '__INBOUND_PROVIDER=${CHANNEL(endpoint)}'),
('from-provider-inbound', '_X.', 5, 'Set', '__ORIGINAL_ANI=${CALLERID(num)}'),
('from-provider-inbound', '_X.', 6, 'Set', '__ORIGINAL_DNIS=${EXTEN}'),
('from-provider-inbound', '_X.', 7, 'Set', '__SOURCE_IP=${CHANNEL(pjsip,remote_addr)}'),
('from-provider-inbound', '_X.', 8, 'Set', 'CDR(inbound_provider)=${INBOUND_PROVIDER}'),
('from-provider-inbound', '_X.', 9, 'Set', 'CDR(original_ani)=${ORIGINAL_ANI}'),
('from-provider-inbound', '_X.', 10, 'Set', 'CDR(original_dnis)=${ORIGINAL_DNIS}'),
('from-provider-inbound', '_X.', 11, 'Set', 'CDR(call_type)=inbound'),
('from-provider-inbound', '_X.', 12, 'MixMonitor', '${UNIQUEID}.wav,b,/usr/local/bin/post-recording.sh ${UNIQUEID}'),
('from-provider-inbound', '_X.', 13, 'AGI', 'agi://localhost:4573/processIncoming'),
('from-provider-inbound', '_X.', 14, 'GotoIf', '$["${ROUTER_STATUS}" = "success"]?route:failed'),
('from-provider-inbound', '_X.', 15, 'NoOp', 'Routing failed: ${ROUTER_ERROR}'),
('from-provider-inbound', '_X.', 16, 'Hangup', '21'),
('from-provider-inbound', '_X.', 17, 'NoOp', 'Routing to intermediate: ${INTERMEDIATE_PROVIDER}'),
('from-provider-inbound', '_X.', 18, 'Set', 'CALLERID(num)=${ANI_TO_SEND}'),
('from-provider-inbound', '_X.', 19, 'Set', 'CDR(intermediate_provider)=${INTERMEDIATE_PROVIDER}'),
('from-provider-inbound', '_X.', 20, 'Set', 'CDR(assigned_did)=${DID_ASSIGNED}'),
('from-provider-inbound', '_X.', 21, 'Dial', 'PJSIP/${DNIS_TO_SEND}@${NEXT_HOP},180,U(sub-recording^${UNIQUEID})'),
('from-provider-inbound', '_X.', 22, 'Set', 'CDR(sip_response)=${HANGUPCAUSE}'),
('from-provider-inbound', '_X.', 23, 'GotoIf', '$["${DIALSTATUS}" = "ANSWER"]?end:dial_failed'),
('from-provider-inbound', '_X.', 24, 'NoOp', 'Dial failed: ${DIALSTATUS}'),
('from-provider-inbound', '_X.', 25, 'Hangup', ''),
('from-provider-inbound', '_X.', 26, 'Hangup', ''),

-- INTERMEDIATE CONTEXT (from S3 providers)
('from-provider-intermediate', '_X.', 1, 'NoOp', 'Return call from S3: ${CALLERID(num)} -> ${EXTEN}'),
('from-provider-intermediate', '_X.', 2, 'Set', '__INTERMEDIATE_PROVIDER=${CHANNEL(endpoint)}'),
('from-provider-intermediate', '_X.', 3, 'Set', '__SOURCE_IP=${CHANNEL(pjsip,remote_addr)}'),
('from-provider-intermediate', '_X.', 4, 'Set', 'CDR(intermediate_return)=true'),
('from-provider-intermediate', '_X.', 5, 'AGI', 'agi://localhost:4573/processReturn'),
('from-provider-intermediate', '_X.', 6, 'GotoIf', '$["${ROUTER_STATUS}" = "success"]?route:failed'),
('from-provider-intermediate', '_X.', 7, 'NoOp', 'Return routing failed: ${ROUTER_ERROR}'),
('from-provider-intermediate', '_X.', 8, 'Hangup', '21'),
('from-provider-intermediate', '_X.', 9, 'NoOp', 'Routing to final: ${FINAL_PROVIDER}'),
('from-provider-intermediate', '_X.', 10, 'Set', 'CALLERID(num)=${ANI_TO_SEND}'),
('from-provider-intermediate', '_X.', 11, 'Set', 'CDR(final_provider)=${FINAL_PROVIDER}'),
('from-provider-intermediate', '_X.', 12, 'Dial', 'PJSIP/${DNIS_TO_SEND}@${NEXT_HOP},180'),
('from-provider-intermediate', '_X.', 13, 'Set', 'CDR(final_sip_response)=${HANGUPCAUSE}'),
('from-provider-intermediate', '_X.', 14, 'Hangup', ''),

-- FINAL CONTEXT (from S4 providers)
('from-provider-final', '_X.', 1, 'NoOp', 'Final call from S4: ${CALLERID(num)} -> ${EXTEN}'),
('from-provider-final', '_X.', 2, 'Set', '__FINAL_PROVIDER=${CHANNEL(endpoint)}'),
('from-provider-final', '_X.', 3, 'Set', '__SOURCE_IP=${CHANNEL(pjsip,remote_addr)}'),
('from-provider-final', '_X.', 4, 'Set', 'CDR(final_confirmation)=true'),
('from-provider-final', '_X.', 5, 'AGI', 'agi://localhost:4573/processFinal'),
('from-provider-final', '_X.', 6, 'Congestion', '5'),
('from-provider-final', '_X.', 7, 'Hangup', ''),

-- HANGUP HANDLER CONTEXT
('hangup-handler', 's', 1, 'NoOp', 'Call ended: ${UNIQUEID}'),
('hangup-handler', 's', 2, 'Set', 'CDR(end_time)=${EPOCH}'),
('hangup-handler', 's', 3, 'Set', 'CDR(duration)=${CDR(billsec)}'),
('hangup-handler', 's', 4, 'AGI', 'agi://localhost:4573/hangup'),
('hangup-handler', 's', 5, 'Return', ''),

-- RECORDING SUBROUTINE
('sub-recording', 's', 1, 'NoOp', 'Starting recording on originated channel'),
('sub-recording', 's', 2, 'Set', 'AUDIOHOOK_INHERIT(MixMonitor)=yes'),
('sub-recording', 's', 3, 'MixMonitor', '${ARG1}-out.wav,b'),
('sub-recording', 's', 4, 'Return', '');`
}
package db

import (
    "database/sql"
    "embed"
    "fmt"
    
    "github.com/golang-migrate/migrate/v4"
    "github.com/golang-migrate/migrate/v4/database/mysql"
    "github.com/golang-migrate/migrate/v4/source/iofs"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

func RunDatabaseMigrations(db *sql.DB) error {
    driver, err := mysql.WithInstance(db, &mysql.Config{})
    if err != nil {
        return fmt.Errorf("failed to create migration driver: %w", err)
    }
    
    source, err := iofs.New(migrationsFS, "migrations")
    if err != nil {
        return fmt.Errorf("failed to create migration source: %w", err)
    }
    
    m, err := migrate.NewWithInstance("iofs", source, "mysql", driver)
    if err != nil {
        return fmt.Errorf("failed to create migrator: %w", err)
    }
    
    if err := m.Up(); err != nil && err != migrate.ErrNoChange {
        return fmt.Errorf("migration failed: %w", err)
    }
    
    version, _, _ := m.Version()
    logger.WithField("version", version).Info("Database migrations completed")
    
    return nil
}
package health

import (
    "context"
    "encoding/json"
    "fmt"
    "net/http"
    "sync"
    "time"
    
    "github.com/gorilla/mux"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
)

type HealthService struct {
    mu          sync.RWMutex
    checks      map[string]Checker
    readyChecks map[string]Checker
    server      *http.Server
}

type Checker interface {
    Check(ctx context.Context) error
}

type CheckFunc func(ctx context.Context) error

func (f CheckFunc) Check(ctx context.Context) error {
    return f(ctx)
}

type HealthResponse struct {
    Status     string                 `json:"status"`
    Timestamp  time.Time              `json:"timestamp"`
    Checks     map[string]CheckResult `json:"checks,omitempty"`
    TotalTime  string                 `json:"total_time,omitempty"`
}

type CheckResult struct {
    Status   string `json:"status"`
    Error    string `json:"error,omitempty"`
    Duration string `json:"duration"`
}

func NewHealthService(port int) *HealthService {
    hs := &HealthService{
checks:      make(map[string]Checker),
       readyChecks: make(map[string]Checker),
   }
   
   router := mux.NewRouter()
   router.HandleFunc("/health/live", hs.handleLiveness).Methods("GET")
   router.HandleFunc("/health/ready", hs.handleReadiness).Methods("GET")
   
   hs.server = &http.Server{
       Addr:         fmt.Sprintf(":%d", port),
       Handler:      router,
       ReadTimeout:  10 * time.Second,
       WriteTimeout: 10 * time.Second,
   }
   
   return hs
}

func (hs *HealthService) Start() error {
   logger.WithField("addr", hs.server.Addr).Info("Health service started")
   return hs.server.ListenAndServe()
}

func (hs *HealthService) Stop() error {
   ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
   defer cancel()
   return hs.server.Shutdown(ctx)
}

func (hs *HealthService) RegisterLivenessCheck(name string, check Checker) {
   hs.mu.Lock()
   defer hs.mu.Unlock()
   hs.checks[name] = check
}

func (hs *HealthService) RegisterReadinessCheck(name string, check Checker) {
   hs.mu.Lock()
   defer hs.mu.Unlock()
   hs.readyChecks[name] = check
}

func (hs *HealthService) handleLiveness(w http.ResponseWriter, r *http.Request) {
   hs.handleCheck(w, r, hs.checks)
}

func (hs *HealthService) handleReadiness(w http.ResponseWriter, r *http.Request) {
   hs.handleCheck(w, r, hs.readyChecks)
}

func (hs *HealthService) handleCheck(w http.ResponseWriter, r *http.Request, checks map[string]Checker) {
   ctx := r.Context()
   start := time.Now()
   
   hs.mu.RLock()
   defer hs.mu.RUnlock()
   
   response := HealthResponse{
       Status:    "ok",
       Timestamp: start,
       Checks:    make(map[string]CheckResult),
   }
   
   var wg sync.WaitGroup
   resultChan := make(chan struct {
       name   string
       result CheckResult
   }, len(checks))
   
   for name, check := range checks {
       wg.Add(1)
       go func(n string, c Checker) {
           defer wg.Done()
           
           checkStart := time.Now()
           err := c.Check(ctx)
           duration := time.Since(checkStart)
           
           result := CheckResult{
               Status:   "ok",
               Duration: duration.String(),
           }
           
           if err != nil {
               result.Status = "failed"
               result.Error = err.Error()
               response.Status = "failed"
           }
           
           resultChan <- struct {
               name   string
               result CheckResult
           }{n, result}
       }(name, check)
   }
   
   go func() {
       wg.Wait()
       close(resultChan)
   }()
   
   for res := range resultChan {
       response.Checks[res.name] = res.result
   }
   
   response.TotalTime = time.Since(start).String()
   
   w.Header().Set("Content-Type", "application/json")
   if response.Status != "ok" {
       w.WriteHeader(http.StatusServiceUnavailable)
   }
   
   json.NewEncoder(w).Encode(response)
}
package metrics

import (
    "fmt"
    "net/http"
    
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promhttp"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
)

type PrometheusMetrics struct {
    counters   map[string]*prometheus.CounterVec
    histograms map[string]*prometheus.HistogramVec
    gauges     map[string]*prometheus.GaugeVec
}

func NewPrometheusMetrics() *PrometheusMetrics {
    pm := &PrometheusMetrics{
        counters:   make(map[string]*prometheus.CounterVec),
        histograms: make(map[string]*prometheus.HistogramVec),
        gauges:     make(map[string]*prometheus.GaugeVec),
    }
    
    // Register common metrics
    pm.registerMetrics()
    
    return pm
}

func (pm *PrometheusMetrics) registerMetrics() {
    // Counters
    pm.counters["router_calls_processed"] = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "router_calls_processed_total",
            Help: "Total number of calls processed",
        },
        []string{"stage", "route"},
    )
    
    pm.counters["router_calls_failed"] = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "router_calls_failed_total",
            Help: "Total number of failed calls",
        },
        []string{"reason", "provider", "route"},
    )
    
    pm.counters["agi_connections_total"] = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "agi_connections_total",
            Help: "Total AGI connections",
        },
        []string{},
    )
    
    pm.counters["provider_calls_total"] = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "provider_calls_total",
            Help: "Total calls per provider",
        },
        []string{"provider", "status"},
    )
    
    // Histograms
    pm.histograms["router_call_duration"] = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "router_call_duration_seconds",
            Help:    "Call duration in seconds",
            Buckets: []float64{5, 10, 30, 60, 120, 300, 600, 1800, 3600},
        },
        []string{"route"},
    )
    
    pm.histograms["agi_processing_time"] = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "agi_processing_time_seconds",
            Help:    "AGI request processing time",
            Buckets: []float64{0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1},
        },
        []string{"action"},
    )
    
    pm.histograms["provider_call_duration"] = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "provider_call_duration_seconds",
            Help:    "Call duration per provider",
            Buckets: []float64{5, 10, 30, 60, 120, 300, 600, 1800, 3600},
        },
        []string{"provider"},
    )
    
    // Gauges
    pm.gauges["router_active_calls"] = prometheus.NewGaugeVec(
        prometheus.GaugeOpts{
            Name: "router_active_calls",
            Help: "Current number of active calls",
        },
        []string{},
    )
    
    pm.gauges["provider_active_calls"] = prometheus.NewGaugeVec(
        prometheus.GaugeOpts{
            Name: "provider_active_calls",
            Help: "Active calls per provider",
        },
        []string{"provider"},
    )
    
    pm.gauges["agi_connections_active"] = prometheus.NewGaugeVec(
        prometheus.GaugeOpts{
            Name: "agi_connections_active",
            Help: "Current active AGI connections",
        },
        []string{},
    )
    
    pm.gauges["did_pool_available"] = prometheus.NewGaugeVec(
        prometheus.GaugeOpts{
            Name: "did_pool_available",
            Help: "Available DIDs in pool",
        },
        []string{"provider"},
    )
    
    // Register all metrics
    for _, counter := range pm.counters {
        prometheus.MustRegister(counter)
    }
    for _, histogram := range pm.histograms {
        prometheus.MustRegister(histogram)
    }
    for _, gauge := range pm.gauges {
        prometheus.MustRegister(gauge)
    }
}

func (pm *PrometheusMetrics) IncrementCounter(name string, labels map[string]string) {
    if counter, exists := pm.counters[name]; exists {
        counter.With(prometheus.Labels(labels)).Inc()
    }
}

func (pm *PrometheusMetrics) ObserveHistogram(name string, value float64, labels map[string]string) {
    if histogram, exists := pm.histograms[name]; exists {
        histogram.With(prometheus.Labels(labels)).Observe(value)
    }
}

func (pm *PrometheusMetrics) SetGauge(name string, value float64, labels map[string]string) {
    if gauge, exists := pm.gauges[name]; exists {
        if labels == nil {
            labels = make(map[string]string)
        }
        gauge.With(prometheus.Labels(labels)).Set(value)
    }
}

func (pm *PrometheusMetrics) ServeHTTP(port int) error {
    http.Handle("/metrics", promhttp.Handler())
    addr := fmt.Sprintf(":%d", port)
    logger.WithField("addr", addr).Info("Metrics server started")
    return http.ListenAndServe(addr, nil)
}
package models

import (
//   "database/sql/driver"
    "encoding/json"
    "time"
)

// GroupType defines how providers are grouped
type GroupType string

const (
    GroupTypeManual   GroupType = "manual"    // Manually added providers
    GroupTypeRegex    GroupType = "regex"     // Pattern matching on provider names
    GroupTypeMetadata GroupType = "metadata"  // Match based on metadata fields
    GroupTypeDynamic  GroupType = "dynamic"   // Dynamically evaluated
)

// MatchOperator defines how to match providers
type MatchOperator string

const (
    MatchOperatorEquals     MatchOperator = "equals"
    MatchOperatorContains   MatchOperator = "contains"
    MatchOperatorStartsWith MatchOperator = "starts_with"
    MatchOperatorEndsWith   MatchOperator = "ends_with"
    MatchOperatorRegex      MatchOperator = "regex"
    MatchOperatorIn         MatchOperator = "in"
    MatchOperatorNotIn      MatchOperator = "not_in"
)

// ProviderGroup represents a logical grouping of providers
type ProviderGroup struct {
    ID           int             `json:"id" db:"id"`
    Name         string          `json:"name" db:"name"`
    Description  string          `json:"description" db:"description"`
    GroupType    GroupType       `json:"group_type" db:"group_type"`
    MatchPattern string          `json:"match_pattern,omitempty" db:"match_pattern"`
    MatchField   string          `json:"match_field,omitempty" db:"match_field"`
    MatchOperator MatchOperator  `json:"match_operator,omitempty" db:"match_operator"`
    MatchValue   json.RawMessage `json:"match_value,omitempty" db:"match_value"`
    ProviderType ProviderType    `json:"provider_type,omitempty" db:"provider_type"`
    Enabled      bool            `json:"enabled" db:"enabled"`
    Priority     int             `json:"priority" db:"priority"`
    Metadata     JSON            `json:"metadata,omitempty" db:"metadata"`
    CreatedAt    time.Time       `json:"created_at" db:"created_at"`
    UpdatedAt    time.Time       `json:"updated_at" db:"updated_at"`
    
    // Computed fields
    MemberCount int         `json:"member_count,omitempty" db:"-"`
    Members     []*Provider `json:"members,omitempty" db:"-"`
}

// ProviderGroupMember represents membership in a group
type ProviderGroupMember struct {
    ID              int64     `json:"id" db:"id"`
    GroupID         int       `json:"group_id" db:"group_id"`
    ProviderID      int       `json:"provider_id" db:"provider_id"`
    ProviderName    string    `json:"provider_name" db:"provider_name"`
    AddedManually   bool      `json:"added_manually" db:"added_manually"`
    MatchedByRule   bool      `json:"matched_by_rule" db:"matched_by_rule"`
    PriorityOverride *int     `json:"priority_override,omitempty" db:"priority_override"`
    WeightOverride   *int     `json:"weight_override,omitempty" db:"weight_override"`
    Metadata        JSON      `json:"metadata,omitempty" db:"metadata"`
    CreatedAt       time.Time `json:"created_at" db:"created_at"`
}

// GroupMatchRule defines a matching rule for dynamic groups
type GroupMatchRule struct {
    Field    string      `json:"field"`
    Operator string      `json:"operator"`
    Value    interface{} `json:"value"`
}

// ProviderGroupStats represents group statistics
type ProviderGroupStats struct {
    GroupName      string    `json:"group_name" db:"group_name"`
    TotalCalls     int64     `json:"total_calls" db:"total_calls"`
    CompletedCalls int64     `json:"completed_calls" db:"completed_calls"`
    FailedCalls    int64     `json:"failed_calls" db:"failed_calls"`
    ActiveCalls    int64     `json:"active_calls" db:"active_calls"`
    SuccessRate    float64   `json:"success_rate" db:"success_rate"`
    AvgCallDuration float64  `json:"avg_call_duration" db:"avg_call_duration"`
    LastCallTime   time.Time `json:"last_call_time" db:"last_call_time"`
}
package models

import (
    "database/sql/driver"
    "encoding/json"
    "time"
)

// Provider types
type ProviderType string

const (
    ProviderTypeInbound      ProviderType = "inbound"
    ProviderTypeIntermediate ProviderType = "intermediate"
    ProviderTypeFinal        ProviderType = "final"
)

// Load balance modes
type LoadBalanceMode string

const (
    LoadBalanceModeRoundRobin       LoadBalanceMode = "round_robin"
    LoadBalanceModeWeighted         LoadBalanceMode = "weighted"
    LoadBalanceModePriority         LoadBalanceMode = "priority"
    LoadBalanceModeFailover         LoadBalanceMode = "failover"
    LoadBalanceModeLeastConnections LoadBalanceMode = "least_connections"
    LoadBalanceModeResponseTime     LoadBalanceMode = "response_time"
    LoadBalanceModeHash             LoadBalanceMode = "hash"
)

// Call status
type CallStatus string

const (
    CallStatusInitiated      CallStatus = "INITIATED"
    CallStatusActive         CallStatus = "ACTIVE"
    CallStatusReturnedFromS3 CallStatus = "RETURNED_FROM_S3"
    CallStatusRoutingToS4    CallStatus = "ROUTING_TO_S4"
    CallStatusCompleted      CallStatus = "COMPLETED"
    CallStatusFailed         CallStatus = "FAILED"
    CallStatusAbandoned      CallStatus = "ABANDONED"
    CallStatusTimeout        CallStatus = "TIMEOUT"
)

// JSON field for database storage
type JSON map[string]interface{}

func (j JSON) Value() (driver.Value, error) {
    return json.Marshal(j)
}

func (j *JSON) Scan(value interface{}) error {
    if value == nil {
        *j = make(JSON)
        return nil
    }
    
    bytes, ok := value.([]byte)
    if !ok {
        return nil
    }
    
    return json.Unmarshal(bytes, j)
}

// Provider represents an external server
type Provider struct {
    ID                 int             `json:"id" db:"id"`
    Name               string          `json:"name" db:"name"`
    Type               ProviderType    `json:"type" db:"type"`
    Host               string          `json:"host" db:"host"`
    Port               int             `json:"port" db:"port"`
    Username           string          `json:"username,omitempty" db:"username"`
    Password           string          `json:"password,omitempty" db:"password"`
    AuthType           string          `json:"auth_type" db:"auth_type"`
    Transport          string          `json:"transport" db:"transport"`
    Codecs             []string        `json:"codecs" db:"codecs"`
    MaxChannels        int             `json:"max_channels" db:"max_channels"`
    CurrentChannels    int             `json:"current_channels" db:"current_channels"`
    Priority           int             `json:"priority" db:"priority"`
    Weight             int             `json:"weight" db:"weight"`
    CostPerMinute      float64         `json:"cost_per_minute" db:"cost_per_minute"`
    Active             bool            `json:"active" db:"active"`
    HealthCheckEnabled bool            `json:"health_check_enabled" db:"health_check_enabled"`
    LastHealthCheck    *time.Time      `json:"last_health_check,omitempty" db:"last_health_check"`
    HealthStatus       string          `json:"health_status" db:"health_status"`
    Metadata           JSON            `json:"metadata,omitempty" db:"metadata"`
    CreatedAt          time.Time       `json:"created_at" db:"created_at"`
    UpdatedAt          time.Time       `json:"updated_at" db:"updated_at"`
}

// DID represents a phone number
type DID struct {
    ID            int64      `json:"id" db:"id"`
    Number        string     `json:"number" db:"number"`
    ProviderID    *int       `json:"provider_id,omitempty" db:"provider_id"`
    ProviderName  string     `json:"provider_name" db:"provider_name"`
    InUse         bool       `json:"in_use" db:"in_use"`
    Destination   string     `json:"destination,omitempty" db:"destination"`
    Country       string     `json:"country,omitempty" db:"country"`
    City          string     `json:"city,omitempty" db:"city"`
    RateCenter    string     `json:"rate_center,omitempty" db:"rate_center"`
    MonthlyCost   float64    `json:"monthly_cost" db:"monthly_cost"`
    PerMinuteCost float64    `json:"per_minute_cost" db:"per_minute_cost"`
    AllocatedAt   *time.Time `json:"allocated_at,omitempty" db:"allocated_at"`
    ReleasedAt    *time.Time `json:"released_at,omitempty" db:"released_at"`
    LastUsedAt    *time.Time `json:"last_used_at,omitempty" db:"last_used_at"`
    UsageCount    int64      `json:"usage_count" db:"usage_count"`
    Metadata      JSON       `json:"metadata,omitempty" db:"metadata"`
    CreatedAt     time.Time  `json:"created_at" db:"created_at"`
    UpdatedAt     time.Time  `json:"updated_at" db:"updated_at"`
}

// Update the ProviderRoute struct to include group support fields
type ProviderRoute struct {
    ID                   int             `json:"id" db:"id"`
    Name                 string          `json:"name" db:"name"`
    Description          string          `json:"description,omitempty" db:"description"`
    InboundProvider      string          `json:"inbound_provider" db:"inbound_provider"`
    IntermediateProvider string          `json:"intermediate_provider" db:"intermediate_provider"`
    FinalProvider        string          `json:"final_provider" db:"final_provider"`
    LoadBalanceMode      LoadBalanceMode `json:"load_balance_mode" db:"load_balance_mode"`
    Priority             int             `json:"priority" db:"priority"`
    Weight               int             `json:"weight" db:"weight"`
    MaxConcurrentCalls   int             `json:"max_concurrent_calls" db:"max_concurrent_calls"`
    CurrentCalls         int             `json:"current_calls" db:"current_calls"`
    Enabled              bool            `json:"enabled" db:"enabled"`
    FailoverRoutes       []string        `json:"failover_routes,omitempty" db:"failover_routes"`
    RoutingRules         JSON            `json:"routing_rules,omitempty" db:"routing_rules"`
    Metadata             JSON            `json:"metadata,omitempty" db:"metadata"`
    CreatedAt            time.Time       `json:"created_at" db:"created_at"`
    UpdatedAt            time.Time       `json:"updated_at" db:"updated_at"`
    
    // Group support fields
    InboundIsGroup      bool `json:"inbound_is_group" db:"inbound_is_group"`
    IntermediateIsGroup bool `json:"intermediate_is_group" db:"intermediate_is_group"`
    FinalIsGroup        bool `json:"final_is_group" db:"final_is_group"`
}

// CallRecord tracks call flow
type CallRecord struct {
    ID                   int64      `json:"id" db:"id"`
    CallID               string     `json:"call_id" db:"call_id"`
    OriginalANI          string     `json:"original_ani" db:"original_ani"`
    OriginalDNIS         string     `json:"original_dnis" db:"original_dnis"`
    TransformedANI       string     `json:"transformed_ani,omitempty" db:"transformed_ani"`
    AssignedDID          string     `json:"assigned_did,omitempty" db:"assigned_did"`
    InboundProvider      string     `json:"inbound_provider" db:"inbound_provider"`
    IntermediateProvider string     `json:"intermediate_provider" db:"intermediate_provider"`
    FinalProvider        string     `json:"final_provider" db:"final_provider"`
    RouteName            string     `json:"route_name,omitempty" db:"route_name"`
    Status               CallStatus `json:"status" db:"status"`
    CurrentStep          string     `json:"current_step,omitempty" db:"current_step"`
    FailureReason        string     `json:"failure_reason,omitempty" db:"failure_reason"`
    StartTime            time.Time  `json:"start_time" db:"start_time"`
    AnswerTime           *time.Time `json:"answer_time,omitempty" db:"answer_time"`
    EndTime              *time.Time `json:"end_time,omitempty" db:"end_time"`
    Duration             int        `json:"duration" db:"duration"`
    BillableDuration     int        `json:"billable_duration" db:"billable_duration"`
    RecordingPath        string     `json:"recording_path,omitempty" db:"recording_path"`
    SIPResponseCode      int        `json:"sip_response_code,omitempty" db:"sip_response_code"`
    QualityScore         float64    `json:"quality_score,omitempty" db:"quality_score"`
    Metadata             JSON       `json:"metadata,omitempty" db:"metadata"`
}

// CallVerification for security tracking
type CallVerification struct {
    ID               int64     `json:"id" db:"id"`
    CallID           string    `json:"call_id" db:"call_id"`
    VerificationStep string    `json:"verification_step" db:"verification_step"`
    ExpectedANI      string    `json:"expected_ani,omitempty" db:"expected_ani"`
    ExpectedDNIS     string    `json:"expected_dnis,omitempty" db:"expected_dnis"`
    ReceivedANI      string    `json:"received_ani,omitempty" db:"received_ani"`
    ReceivedDNIS     string    `json:"received_dnis,omitempty" db:"received_dnis"`
    SourceIP         string    `json:"source_ip,omitempty" db:"source_ip"`
    ExpectedIP       string    `json:"expected_ip,omitempty" db:"expected_ip"`
    Verified         bool      `json:"verified" db:"verified"`
    FailureReason    string    `json:"failure_reason,omitempty" db:"failure_reason"`
    CreatedAt        time.Time `json:"created_at" db:"created_at"`
}

// ProviderHealth tracks real-time health
type ProviderHealth struct {
    ID                  int       `json:"id" db:"id"`
    ProviderName        string    `json:"provider_name" db:"provider_name"`
    HealthScore         int       `json:"health_score" db:"health_score"`
    LatencyMs           int       `json:"latency_ms" db:"latency_ms"`
    PacketLoss          float64   `json:"packet_loss" db:"packet_loss"`
    JitterMs            int       `json:"jitter_ms" db:"jitter_ms"`
    ActiveCalls         int       `json:"active_calls" db:"active_calls"`
    MaxCalls            int       `json:"max_calls" db:"max_calls"`
    LastSuccessAt       *time.Time `json:"last_success_at,omitempty" db:"last_success_at"`
    LastFailureAt       *time.Time `json:"last_failure_at,omitempty" db:"last_failure_at"`
    ConsecutiveFailures int       `json:"consecutive_failures" db:"consecutive_failures"`
    IsHealthy           bool      `json:"is_healthy" db:"is_healthy"`
    UpdatedAt           time.Time `json:"updated_at" db:"updated_at"`
}

// AGI Response for call routing
type CallResponse struct {
    Status      string `json:"status"`
    DIDAssigned string `json:"did_assigned,omitempty"`
    NextHop     string `json:"next_hop,omitempty"`
    ANIToSend   string `json:"ani_to_send,omitempty"`
    DNISToSend  string `json:"dnis_to_send,omitempty"`
    Error       string `json:"error,omitempty"`
}

// Provider statistics
type ProviderStats struct {
    ProviderName     string    `json:"provider_name"`
    TotalCalls       int64     `json:"total_calls"`
    CompletedCalls   int64     `json:"completed_calls"`
    FailedCalls      int64     `json:"failed_calls"`
    ActiveCalls      int64     `json:"active_calls"`
    SuccessRate      float64   `json:"success_rate"`
    AvgCallDuration  float64   `json:"avg_call_duration"`
    AvgResponseTime  int       `json:"avg_response_time"`
    LastCallTime     time.Time `json:"last_call_time"`
    IsHealthy        bool      `json:"is_healthy"`
}
package provider

import (
    "context"
    "database/sql"
    "encoding/json"
    "fmt"
    "regexp"
    "strings"
    "time"
    
    "github.com/hamzaKhattat/ara-production-system/internal/models"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
)

// GroupService handles provider group operations
type GroupService struct {
    db    *sql.DB
    cache CacheInterface
}

// NewGroupService creates a new group service
func NewGroupService(db *sql.DB, cache CacheInterface) *GroupService {
    return &GroupService{
        db:    db,
        cache: cache,
    }
}

// CreateGroup creates a new provider group
func (gs *GroupService) CreateGroup(ctx context.Context, group *models.ProviderGroup) error {
    // Validate group
    if err := gs.validateGroup(group); err != nil {
        return err
    }
    
    // Start transaction
    tx, err := gs.db.BeginTx(ctx, nil)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
    }
    defer tx.Rollback()
    
    // Insert group
    matchValue, _ := json.Marshal(group.MatchValue)
    metadata, _ := json.Marshal(group.Metadata)
    
    query := `
        INSERT INTO provider_groups (
            name, description, group_type, match_pattern, match_field,
            match_operator, match_value, provider_type, enabled, priority, metadata
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    
    result, err := tx.ExecContext(ctx, query,
        group.Name, group.Description, group.GroupType, group.MatchPattern,
        group.MatchField, group.MatchOperator, matchValue,
        group.ProviderType, group.Enabled, group.Priority, metadata,
    )
    
    if err != nil {
        if strings.Contains(err.Error(), "Duplicate entry") {
            return errors.New(errors.ErrInternal, "group already exists")
        }
        return errors.Wrap(err, errors.ErrDatabase, "failed to insert group")
    }
    
    groupID, _ := result.LastInsertId()
    group.ID = int(groupID)
    
    // If it's a dynamic group, populate members based on rules
    if group.GroupType != models.GroupTypeManual {
        if err := gs.populateGroupMembers(ctx, tx, group); err != nil {
            return errors.Wrap(err, errors.ErrInternal, "failed to populate group members")
        }
    }
    
    if err := tx.Commit(); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to commit transaction")
    }
    
    // Clear cache
    gs.cache.Delete(ctx, fmt.Sprintf("group:%s", group.Name))
    gs.cache.Delete(ctx, "groups:all")
    
    logger.WithContext(ctx).WithFields(map[string]interface{}{
        "group_id": group.ID,
        "name": group.Name,
        "type": group.GroupType,
    }).Info("Provider group created")
    
    return nil
}

// populateGroupMembers fills group members based on matching rules
func (gs *GroupService) populateGroupMembers(ctx context.Context, tx *sql.Tx, group *models.ProviderGroup) error {
    // Get all providers
    providers, err := gs.getMatchingProviders(ctx, tx, group)
    if err != nil {
        return err
    }
    
    // Insert matching providers as group members
    stmt, err := tx.PrepareContext(ctx, `
        INSERT INTO provider_group_members (
            group_id, provider_id, provider_name, matched_by_rule
        ) VALUES (?, ?, ?, true)
        ON DUPLICATE KEY UPDATE matched_by_rule = true`)
    
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to prepare statement")
    }
    defer stmt.Close()
    
    for _, provider := range providers {
        if _, err := stmt.ExecContext(ctx, group.ID, provider.ID, provider.Name); err != nil {
            logger.WithContext(ctx).WithError(err).Warn("Failed to add provider to group")
        }
    }
    
    return nil
}

// getMatchingProviders returns providers that match the group criteria
func (gs *GroupService) getMatchingProviders(ctx context.Context, tx *sql.Tx, group *models.ProviderGroup) ([]*models.Provider, error) {
    query := "SELECT id, name, type, host, country, region, city, metadata FROM providers WHERE active = 1"
    var args []interface{}
    
    // Filter by provider type if specified
    if group.ProviderType != "" && group.ProviderType != "any" {
        query += " AND type = ?"
        args = append(args, group.ProviderType)
    }
    
    rows, err := tx.QueryContext(ctx, query, args...)
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query providers")
    }
    defer rows.Close()
    
    var matchingProviders []*models.Provider
    
    for rows.Next() {
        var provider models.Provider
        var country, region, city sql.NullString
        var metadataJSON sql.NullString
        
        err := rows.Scan(&provider.ID, &provider.Name, &provider.Type, 
            &provider.Host, &country, &region, &city, &metadataJSON)
        if err != nil {
            continue
        }
        
        // Build provider metadata for matching
        providerData := map[string]interface{}{
            "name": provider.Name,
            "type": string(provider.Type),
            "host": provider.Host,
        }
        
        if country.Valid {
            providerData["country"] = country.String
        }
        if region.Valid {
            providerData["region"] = region.String
        }
        if city.Valid {
            providerData["city"] = city.String
        }
        
        if metadataJSON.Valid {
            var metadata map[string]interface{}
            if err := json.Unmarshal([]byte(metadataJSON.String), &metadata); err == nil {
                for k, v := range metadata {
                    providerData["metadata."+k] = v
                }
            }
        }
        
        // Check if provider matches group criteria
        if gs.providerMatchesGroup(group, providerData) {
            matchingProviders = append(matchingProviders, &provider)
        }
    }
    
    return matchingProviders, nil
}

// providerMatchesGroup checks if a provider matches group criteria
func (gs *GroupService) providerMatchesGroup(group *models.ProviderGroup, providerData map[string]interface{}) bool {
    switch group.GroupType {
    case models.GroupTypeRegex:
        return gs.matchRegex(group.MatchPattern, providerData["name"].(string))
    
    case models.GroupTypeMetadata:
        fieldValue, exists := providerData[group.MatchField]
        if !exists {
            return false
        }
        return gs.matchValue(group.MatchOperator, fieldValue, group.MatchValue)
    
    case models.GroupTypeDynamic:
        // For dynamic groups, parse match rules from metadata
        if group.Metadata != nil {
            if rules, ok := group.Metadata["match_rules"].([]interface{}); ok {
                return gs.matchDynamicRules(rules, providerData)
            }
        }
        return false
    
    default:
        return false
    }
}

// matchRegex checks if a string matches a regex pattern
func (gs *GroupService) matchRegex(pattern, value string) bool {
    matched, err := regexp.MatchString(pattern, value)
    if err != nil {
        logger.WithField("pattern", pattern).WithError(err).Warn("Invalid regex pattern")
        return false
    }
    return matched
}

// matchValue checks if a value matches based on operator
func (gs *GroupService) matchValue(operator models.MatchOperator, fieldValue interface{}, matchValue json.RawMessage) bool {
    fieldStr := fmt.Sprintf("%v", fieldValue)
    
    switch operator {
    case models.MatchOperatorEquals:
        var value string
        if err := json.Unmarshal(matchValue, &value); err == nil {
            return fieldStr == value
        }
    
    case models.MatchOperatorContains:
        var value string
        if err := json.Unmarshal(matchValue, &value); err == nil {
            return strings.Contains(fieldStr, value)
        }
    
    case models.MatchOperatorStartsWith:
        var value string
        if err := json.Unmarshal(matchValue, &value); err == nil {
            return strings.HasPrefix(fieldStr, value)
        }
    
    case models.MatchOperatorEndsWith:
        var value string
        if err := json.Unmarshal(matchValue, &value); err == nil {
            return strings.HasSuffix(fieldStr, value)
        }
    
    case models.MatchOperatorRegex:
        var pattern string
        if err := json.Unmarshal(matchValue, &pattern); err == nil {
            return gs.matchRegex(pattern, fieldStr)
        }
    
    case models.MatchOperatorIn:
        var values []string
        if err := json.Unmarshal(matchValue, &values); err == nil {
            for _, v := range values {
                if fieldStr == v {
                    return true
                }
            }
        }
    
    case models.MatchOperatorNotIn:
        var values []string
        if err := json.Unmarshal(matchValue, &values); err == nil {
            for _, v := range values {
                if fieldStr == v {
                    return false
                }
            }
            return true
        }
    }
    
    return false
}

// matchDynamicRules checks if provider matches dynamic rules
func (gs *GroupService) matchDynamicRules(rules []interface{}, providerData map[string]interface{}) bool {
    // All rules must match (AND logic)
    for _, rule := range rules {
        ruleMap, ok := rule.(map[string]interface{})
        if !ok {
            continue
        }
        
        field, _ := ruleMap["field"].(string)
        operator, _ := ruleMap["operator"].(string)
        value := ruleMap["value"]
        
        fieldValue, exists := providerData[field]
        if !exists {
            return false
        }
        
        valueJSON, _ := json.Marshal(value)
        if !gs.matchValue(models.MatchOperator(operator), fieldValue, valueJSON) {
            return false
        }
    }
    
    return true
}

// AddProviderToGroup manually adds a provider to a group
func (gs *GroupService) AddProviderToGroup(ctx context.Context, groupName, providerName string, overrides map[string]interface{}) error {
    // Get group
    group, err := gs.GetGroup(ctx, groupName)
    if err != nil {
        return err
    }
    
    // Get provider
    var providerID int
    err = gs.db.QueryRowContext(ctx, 
        "SELECT id FROM providers WHERE name = ?", providerName).Scan(&providerID)
    if err != nil {
        return errors.New(errors.ErrProviderNotFound, "provider not found")
    }
    
    // Insert member
    query := `
        INSERT INTO provider_group_members (
            group_id, provider_id, provider_name, added_manually,
            priority_override, weight_override, metadata
        ) VALUES (?, ?, ?, true, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            added_manually = true,
            priority_override = VALUES(priority_override),
            weight_override = VALUES(weight_override),
            metadata = VALUES(metadata)`
    
    var priorityOverride, weightOverride sql.NullInt64
    var metadata []byte
    
    if p, ok := overrides["priority"].(int); ok {
        priorityOverride.Valid = true
        priorityOverride.Int64 = int64(p)
    }
    if w, ok := overrides["weight"].(int); ok {
        weightOverride.Valid = true
        weightOverride.Int64 = int64(w)
    }
    if m, ok := overrides["metadata"]; ok {
        metadata, _ = json.Marshal(m)
    }
    
    _, err = gs.db.ExecContext(ctx, query, 
        group.ID, providerID, providerName, 
        priorityOverride, weightOverride, metadata)
    
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to add provider to group")
    }
    
    // Clear cache
    gs.cache.Delete(ctx, fmt.Sprintf("group:%s:members", groupName))
    
    return nil
}

// RemoveProviderFromGroup removes a provider from a group
func (gs *GroupService) RemoveProviderFromGroup(ctx context.Context, groupName, providerName string) error {
    query := `
        DELETE pgm FROM provider_group_members pgm
        JOIN provider_groups pg ON pgm.group_id = pg.id
        WHERE pg.name = ? AND pgm.provider_name = ?`
    
    result, err := gs.db.ExecContext(ctx, query, groupName, providerName)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to remove provider from group")
    }
    
    rows, _ := result.RowsAffected()
    if rows == 0 {
        return errors.New(errors.ErrInternal, "provider not found in group")
    }
    
    // Clear cache
    gs.cache.Delete(ctx, fmt.Sprintf("group:%s:members", groupName))
    
    return nil
}

// GetGroup retrieves a group by name
func (gs *GroupService) GetGroup(ctx context.Context, name string) (*models.ProviderGroup, error) {
    // Try cache first
    cacheKey := fmt.Sprintf("group:%s", name)
    var group models.ProviderGroup
    
    if err := gs.cache.Get(ctx, cacheKey, &group); err == nil {
        return &group, nil
    }
    
    // Query database
    query := `
        SELECT id, name, description, group_type, match_pattern, match_field,
               match_operator, match_value, provider_type, enabled, priority,
               metadata, created_at, updated_at,
               (SELECT COUNT(*) FROM provider_group_members WHERE group_id = pg.id) as member_count
        FROM provider_groups pg
        WHERE name = ?`
    
    var matchValue, metadata sql.NullString
    var providerType sql.NullString
    
    err := gs.db.QueryRowContext(ctx, query, name).Scan(
        &group.ID, &group.Name, &group.Description, &group.GroupType,
        &group.MatchPattern, &group.MatchField, &group.MatchOperator,
        &matchValue, &providerType, &group.Enabled, &group.Priority,
        &metadata, &group.CreatedAt, &group.UpdatedAt, &group.MemberCount,
    )
    
    if err == sql.ErrNoRows {
        return nil, errors.New(errors.ErrInternal, "group not found")
    }
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query group")
    }
    
    // Parse JSON fields
    if matchValue.Valid {
        group.MatchValue = json.RawMessage(matchValue.String)
    }
    if metadata.Valid {
        json.Unmarshal([]byte(metadata.String), &group.Metadata)
    }
    if providerType.Valid {
        group.ProviderType = models.ProviderType(providerType.String)
    }
    
    // Cache for 5 minutes
    gs.cache.Set(ctx, cacheKey, group, 5*time.Minute)
    
    return &group, nil
}

// GetGroupMembers retrieves all providers in a group
func (gs *GroupService) GetGroupMembers(ctx context.Context, groupName string) ([]*models.Provider, error) {
    // Try cache first
    cacheKey := fmt.Sprintf("group:%s:members", groupName)
    var members []*models.Provider
    
    if err := gs.cache.Get(ctx, cacheKey, &members); err == nil {
        return members, nil
    }
    
    // Query database
    query := `
        SELECT p.id, p.name, p.type, p.host, p.port, p.username, p.password,
               p.auth_type, p.transport, p.codecs, p.max_channels, p.current_channels,
               COALESCE(pgm.priority_override, p.priority) as priority,
               COALESCE(pgm.weight_override, p.weight) as weight,
               p.cost_per_minute, p.active, p.health_check_enabled,
               p.last_health_check, p.health_status, p.metadata,
               p.created_at, p.updated_at
        FROM providers p
        JOIN provider_group_members pgm ON p.id = pgm.provider_id
        JOIN provider_groups pg ON pgm.group_id = pg.id
        WHERE pg.name = ? AND p.active = 1
        ORDER BY priority DESC, p.name`
    
    rows, err := gs.db.QueryContext(ctx, query, groupName)
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query group members")
    }
    defer rows.Close()
    
    members = make([]*models.Provider, 0)
    
    for rows.Next() {
        var provider models.Provider
        var codecsJSON string
        var metadataJSON sql.NullString
        
        err := rows.Scan(
            &provider.ID, &provider.Name, &provider.Type, &provider.Host, &provider.Port,
            &provider.Username, &provider.Password, &provider.AuthType, &provider.Transport,
            &codecsJSON, &provider.MaxChannels, &provider.CurrentChannels,
            &provider.Priority, &provider.Weight, &provider.CostPerMinute,
            &provider.Active, &provider.HealthCheckEnabled, &provider.LastHealthCheck,
            &provider.HealthStatus, &metadataJSON, &provider.CreatedAt, &provider.UpdatedAt,
        )
        
        if err != nil {
            logger.WithContext(ctx).WithError(err).Warn("Failed to scan provider")
            continue
        }
        
        // Parse JSON fields
        if codecsJSON != "" {
            json.Unmarshal([]byte(codecsJSON), &provider.Codecs)
        }
        if metadataJSON.Valid {
            json.Unmarshal([]byte(metadataJSON.String), &provider.Metadata)
        }
        
        members = append(members, &provider)
    }
    
    // Cache for 1 minute
    gs.cache.Set(ctx, cacheKey, members, time.Minute)
    
    return members, nil
}

// ListGroups returns all groups with optional filtering
func (gs *GroupService) ListGroups(ctx context.Context, filter map[string]interface{}) ([]*models.ProviderGroup, error) {
    query := `
        SELECT id, name, description, group_type, match_pattern, match_field,
               match_operator, match_value, provider_type, enabled, priority,
               metadata, created_at, updated_at,
               (SELECT COUNT(*) FROM provider_group_members WHERE group_id = pg.id) as member_count
        FROM provider_groups pg
        WHERE 1=1`
    
    var args []interface{}
    
    if groupType, ok := filter["type"].(string); ok && groupType != "" {
        query += " AND group_type = ?"
        args = append(args, groupType)
    }
    
    if providerType, ok := filter["provider_type"].(string); ok && providerType != "" {
        query += " AND provider_type = ?"
        args = append(args, providerType)
    }
    
    if enabled, ok := filter["enabled"].(bool); ok {
        query += " AND enabled = ?"
        args = append(args, enabled)
    }
    
    query += " ORDER BY priority DESC, name"
    
    rows, err := gs.db.QueryContext(ctx, query, args...)
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query groups")
    }
    defer rows.Close()
    
    var groups []*models.ProviderGroup
    
    for rows.Next() {
        var group models.ProviderGroup
        var matchValue, metadata sql.NullString
        var providerType sql.NullString
        
        err := rows.Scan(
            &group.ID, &group.Name, &group.Description, &group.GroupType,
            &group.MatchPattern, &group.MatchField, &group.MatchOperator,
            &matchValue, &providerType, &group.Enabled, &group.Priority,
            &metadata, &group.CreatedAt, &group.UpdatedAt, &group.MemberCount,
        )
        
        if err != nil {
            logger.WithContext(ctx).WithError(err).Warn("Failed to scan group")
            continue
        }
        
        // Parse JSON fields
        if matchValue.Valid {
            group.MatchValue = json.RawMessage(matchValue.String)
        }
        if metadata.Valid {
            json.Unmarshal([]byte(metadata.String), &group.Metadata)
        }
        if providerType.Valid {
            group.ProviderType = models.ProviderType(providerType.String)
        }
        
        groups = append(groups, &group)
    }
    
    return groups, nil
}

// UpdateGroup updates a provider group
func (gs *GroupService) UpdateGroup(ctx context.Context, name string, updates map[string]interface{}) error {
    // Build update query
    var setClause []string
    var args []interface{}
    
    for key, value := range updates {
        switch key {
        case "description", "match_pattern", "match_field", "match_operator",
             "provider_type", "enabled", "priority":
            setClause = append(setClause, fmt.Sprintf("%s = ?", key))
            args = append(args, value)
        case "match_value", "metadata":
            jsonValue, _ := json.Marshal(value)
            setClause = append(setClause, fmt.Sprintf("%s = ?", key))
            args = append(args, jsonValue)
        }
    }
    
    if len(setClause) == 0 {
        return nil // Nothing to update
    }
    
    // Add updated_at
    setClause = append(setClause, "updated_at = NOW()")
    
    // Add WHERE clause
    args = append(args, name)
    
    query := fmt.Sprintf("UPDATE provider_groups SET %s WHERE name = ?", strings.Join(setClause, ", "))
    
    result, err := gs.db.ExecContext(ctx, query, args...)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to update group")
    }
    
    rows, _ := result.RowsAffected()
    if rows == 0 {
        return errors.New(errors.ErrInternal, "group not found")
    }
    
    // If group rules changed, repopulate members
    if _, hasPattern := updates["match_pattern"]; hasPattern {
        group, err := gs.GetGroup(ctx, name)
        if err != nil {
            return err
        }
        
        if group.GroupType != models.GroupTypeManual {
            tx, err := gs.db.BeginTx(ctx, nil)
            if err != nil {
                return err
            }
            defer tx.Rollback()
            
            // Clear existing auto-matched members
            _, err = tx.ExecContext(ctx, `
                DELETE FROM provider_group_members 
                WHERE group_id = ? AND matched_by_rule = true`, group.ID)
            if err != nil {
                return errors.Wrap(err, errors.ErrDatabase, "failed to clear members")
            }
            
            // Repopulate
            if err := gs.populateGroupMembers(ctx, tx, group); err != nil {
                return err
            }
            
            if err := tx.Commit(); err != nil {
                return errors.Wrap(err, errors.ErrDatabase, "failed to commit")
            }
        }
    }
    
    // Clear cache
    gs.cache.Delete(ctx, fmt.Sprintf("group:%s", name))
    gs.cache.Delete(ctx, fmt.Sprintf("group:%s:members", name))
    
    return nil
}

// DeleteGroup deletes a provider group
func (gs *GroupService) DeleteGroup(ctx context.Context, name string) error {
    // Check if group is in use by routes
    var inUse bool
    err := gs.db.QueryRowContext(ctx, `
        SELECT EXISTS(
            SELECT 1 FROM provider_routes 
            WHERE (inbound_provider = ? AND inbound_is_group = 1)
               OR (intermediate_provider = ? AND intermediate_is_group = 1)
               OR (final_provider = ? AND final_is_group = 1)
        )`, name, name, name).Scan(&inUse)
    
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to check group usage")
    }
    
    if inUse {
        return errors.New(errors.ErrInternal, "group is in use by routes")
    }
    
    // Delete group (members will be cascade deleted)
    result, err := gs.db.ExecContext(ctx, "DELETE FROM provider_groups WHERE name = ?", name)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to delete group")
    }
    
    rows, _ := result.RowsAffected()
    if rows == 0 {
        return errors.New(errors.ErrInternal, "group not found")
    }
    
    // Clear cache
    gs.cache.Delete(ctx, fmt.Sprintf("group:%s", name))
    gs.cache.Delete(ctx, fmt.Sprintf("group:%s:members", name))
    gs.cache.Delete(ctx, "groups:all")
    
    return nil
}

// RefreshGroupMembers refreshes dynamic group members
func (gs *GroupService) RefreshGroupMembers(ctx context.Context, groupName string) error {
    group, err := gs.GetGroup(ctx, groupName)
    if err != nil {
        return err
    }
    
    if group.GroupType == models.GroupTypeManual {
        return errors.New(errors.ErrInternal, "cannot refresh manual group")
    }
    
    tx, err := gs.db.BeginTx(ctx, nil)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
    }
    defer tx.Rollback()
    
    // Clear existing auto-matched members
    _, err = tx.ExecContext(ctx, `
        DELETE FROM provider_group_members 
        WHERE group_id = ? AND matched_by_rule = true`, group.ID)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to clear members")
    }
    
    // Repopulate
    if err := gs.populateGroupMembers(ctx, tx, group); err != nil {
        return err
    }
    
    if err := tx.Commit(); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to commit")
    }
    
    // Clear cache
    gs.cache.Delete(ctx, fmt.Sprintf("group:%s:members", groupName))
    
    logger.WithContext(ctx).WithField("group", groupName).Info("Group members refreshed")
    
    return nil
}

// validateGroup validates group configuration
func (gs *GroupService) validateGroup(group *models.ProviderGroup) error {
    if group.Name == "" {
        return errors.New(errors.ErrInternal, "group name is required")
    }
    
    switch group.GroupType {
    case models.GroupTypeRegex:
        if group.MatchPattern == "" {
            return errors.New(errors.ErrInternal, "match pattern is required for regex groups")
        }
        // Validate regex
        _, err := regexp.Compile(group.MatchPattern)
        if err != nil {
            return errors.New(errors.ErrInternal, "invalid regex pattern")
        }
    
    case models.GroupTypeMetadata:
        if group.MatchField == "" || group.MatchOperator == "" {
            return errors.New(errors.ErrInternal, "match field and operator are required for metadata groups")
        }
    
    case models.GroupTypeDynamic:
        if group.Metadata == nil || group.Metadata["match_rules"] == nil {
            return errors.New(errors.ErrInternal, "match rules are required for dynamic groups")
        }
    }
    
    return nil
}
package provider

import (
    "context"
    "database/sql"
    "encoding/json"
    "fmt"
    "net"
    "strings"
    "time"
    
    "github.com/hamzaKhattat/ara-production-system/internal/ara"
    "github.com/hamzaKhattat/ara-production-system/internal/ami"
    "github.com/hamzaKhattat/ara-production-system/internal/models"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
)

type Service struct {
    db          *sql.DB
    araManager  *ara.Manager
    amiManager  *ami.Manager
    cache       CacheInterface
}

type CacheInterface interface {
    Get(ctx context.Context, key string, dest interface{}) error
    Set(ctx context.Context, key string, value interface{}, expiration time.Duration) error
    Delete(ctx context.Context, keys ...string) error
}

func NewService(db *sql.DB, araManager *ara.Manager, amiManager *ami.Manager, cache CacheInterface) *Service {
    return &Service{
        db:         db,
        araManager: araManager,
        amiManager: amiManager,
        cache:      cache,
    }
}

func (s *Service) CreateProvider(ctx context.Context, provider *models.Provider) error {
    log := logger.WithContext(ctx)
    
    // Validate provider
    if err := s.validateProvider(provider); err != nil {
        return err
    }
    
    // Set defaults
    if provider.Transport == "" {
        provider.Transport = "udp"
    }
    if provider.AuthType == "" {
        provider.AuthType = "ip"
    }
    if provider.Port == 0 {
        provider.Port = 5060
    }
    if provider.Priority == 0 {
        provider.Priority = 10
    }
    if provider.Weight == 0 {
        provider.Weight = 1
    }
    
    // Start transaction
    tx, err := s.db.BeginTx(ctx, nil)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
    }
    defer tx.Rollback()
    
    // Insert provider
    codecsJSON, _ := json.Marshal(provider.Codecs)
    metadataJSON, _ := json.Marshal(provider.Metadata)
    
    query := `
        INSERT INTO providers (
            name, type, host, port, username, password, auth_type,
            transport, codecs, max_channels, priority, weight,
            cost_per_minute, active, health_check_enabled, metadata
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    
    result, err := tx.ExecContext(ctx, query,
        provider.Name, provider.Type, provider.Host, provider.Port,
        provider.Username, provider.Password, provider.AuthType,
        provider.Transport, codecsJSON, provider.MaxChannels,
        provider.Priority, provider.Weight, provider.CostPerMinute,
        provider.Active, provider.HealthCheckEnabled, metadataJSON,
    )
    
    if err != nil {
        if strings.Contains(err.Error(), "Duplicate entry") {
            return errors.New(errors.ErrInternal, "provider already exists")
        }
        return errors.Wrap(err, errors.ErrDatabase, "failed to insert provider")
    }
    
    providerID, _ := result.LastInsertId()
    provider.ID = int(providerID)
    
    // Create ARA endpoint
    if err := s.araManager.CreateEndpoint(ctx, provider); err != nil {
        return errors.Wrap(err, errors.ErrInternal, "failed to create ARA endpoint")
    }
    
    // Commit transaction
    if err := tx.Commit(); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to commit transaction")
    }
    
    // Reload PJSIP
    if s.amiManager != nil {
        if err := s.amiManager.ReloadPJSIP(); err != nil {
            log.WithError(err).Warn("Failed to reload PJSIP via AMI")
        }
    }
    
    // Clear cache
    s.cache.Delete(ctx, fmt.Sprintf("provider:%s", provider.Name))
    s.cache.Delete(ctx, fmt.Sprintf("providers:%s", provider.Type))
    
    log.WithFields(map[string]interface{}{
        "provider_id": provider.ID,
        "name": provider.Name,
        "type": provider.Type,
    }).Info("Provider created successfully")
    
    return nil
}

func (s *Service) UpdateProvider(ctx context.Context, name string, updates map[string]interface{}) error {
    // Get existing provider
    provider, err := s.GetProvider(ctx, name)
    if err != nil {
        return err
    }
    
    // Build update query
    var setClause []string
    var args []interface{}
    
    for key, value := range updates {
        switch key {
        case "host", "port", "username", "password", "auth_type",
             "transport", "max_channels", "priority", "weight",
             "cost_per_minute", "active", "health_check_enabled":
            setClause = append(setClause, fmt.Sprintf("%s = ?", key))
            args = append(args, value)
        case "codecs":
            codecsJSON, _ := json.Marshal(value)
            setClause = append(setClause, "codecs = ?")
            args = append(args, codecsJSON)
        case "metadata":
            metadataJSON, _ := json.Marshal(value)
            setClause = append(setClause, "metadata = ?")
            args = append(args, metadataJSON)
        }
    }
    
    if len(setClause) == 0 {
        return nil // Nothing to update
    }
    
    // Add updated_at
    setClause = append(setClause, "updated_at = NOW()")
    
    // Add WHERE clause
    args = append(args, name)
    
    query := fmt.Sprintf("UPDATE providers SET %s WHERE name = ?", strings.Join(setClause, ", "))
    
    if _, err := s.db.ExecContext(ctx, query, args...); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to update provider")
    }
    
    // Update ARA endpoint if needed
    needsARAUpdate := false
    for key := range updates {
        if key == "host" || key == "port" || key == "username" || 
           key == "password" || key == "auth_type" || key == "codecs" {
            needsARAUpdate = true
            break
        }
    }
    
    if needsARAUpdate {
        // Get updated provider
        updatedProvider, err := s.GetProvider(ctx, name)
        if err != nil {
            return err
        }
        
        if err := s.araManager.CreateEndpoint(ctx, updatedProvider); err != nil {
            return errors.Wrap(err, errors.ErrInternal, "failed to update ARA endpoint")
        }
        
        // Reload PJSIP
        if s.amiManager != nil {
            if err := s.amiManager.ReloadPJSIP(); err != nil {
                logger.WithContext(ctx).WithError(err).Warn("Failed to reload PJSIP")
            }
        }
    }
    
    // Clear cache
    s.cache.Delete(ctx, fmt.Sprintf("provider:%s", name))
    s.cache.Delete(ctx, fmt.Sprintf("providers:%s", provider.Type))
    
    return nil
}

func (s *Service) DeleteProvider(ctx context.Context, name string) error {
    // Check if provider is in use
    var inUse bool
    err := s.db.QueryRowContext(ctx, `
        SELECT EXISTS(
            SELECT 1 FROM provider_routes 
            WHERE inbound_provider = ? OR intermediate_provider = ? OR final_provider = ?
        )`, name, name, name).Scan(&inUse)
    
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to check provider usage")
    }
    
    if inUse {
        return errors.New(errors.ErrInternal, "provider is in use by routes")
    }
    
    // Delete from database
    tx, err := s.db.BeginTx(ctx, nil)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
    }
    defer tx.Rollback()
    
    // Delete provider
    if _, err := tx.ExecContext(ctx, "DELETE FROM providers WHERE name = ?", name); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to delete provider")
    }
    
    // Delete from ARA
    if err := s.araManager.DeleteEndpoint(ctx, name); err != nil {
        logger.WithContext(ctx).WithError(err).Warn("Failed to delete ARA endpoint")
    }
    
    if err := tx.Commit(); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to commit transaction")
    }
    
    // Reload PJSIP
    if s.amiManager != nil {
        if err := s.amiManager.ReloadPJSIP(); err != nil {
            logger.WithContext(ctx).WithError(err).Warn("Failed to reload PJSIP")
        }
    }
    
    // Clear cache
    s.cache.Delete(ctx, fmt.Sprintf("provider:%s", name))
    
    return nil
}

func (s *Service) GetProvider(ctx context.Context, name string) (*models.Provider, error) {
    // Try cache first
    cacheKey := fmt.Sprintf("provider:%s", name)
    var provider models.Provider
    
    if err := s.cache.Get(ctx, cacheKey, &provider); err == nil {
        return &provider, nil
    }
    
    // Query database
    query := `
        SELECT id, name, type, host, port, username, password, auth_type,
               transport, codecs, max_channels, current_channels, priority,
               weight, cost_per_minute, active, health_check_enabled,
               last_health_check, health_status, metadata, created_at, updated_at
        FROM providers
        WHERE name = ?`
    
    var codecsJSON string
    var metadataJSON sql.NullString
    
    err := s.db.QueryRowContext(ctx, query, name).Scan(
        &provider.ID, &provider.Name, &provider.Type, &provider.Host, &provider.Port,
        &provider.Username, &provider.Password, &provider.AuthType, &provider.Transport,
        &codecsJSON, &provider.MaxChannels, &provider.CurrentChannels,
        &provider.Priority, &provider.Weight, &provider.CostPerMinute,
        &provider.Active, &provider.HealthCheckEnabled, &provider.LastHealthCheck,
        &provider.HealthStatus, &metadataJSON, &provider.CreatedAt, &provider.UpdatedAt,
    )
    
    if err == sql.ErrNoRows {
        return nil, errors.New(errors.ErrProviderNotFound, "provider not found")
    }
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query provider")
    }
    
    // Parse JSON fields
    if codecsJSON != "" {
        json.Unmarshal([]byte(codecsJSON), &provider.Codecs)
    }
    if metadataJSON.Valid {
        json.Unmarshal([]byte(metadataJSON.String), &provider.Metadata)
    }
    
    // Cache for 5 minutes
    s.cache.Set(ctx, cacheKey, provider, 5*time.Minute)
    
    return &provider, nil
}

func (s *Service) ListProviders(ctx context.Context, filter map[string]interface{}) ([]*models.Provider, error) {
    query := `
        SELECT id, name, type, host, port, username, password, auth_type,
               transport, codecs, max_channels, current_channels, priority,
               weight, cost_per_minute, active, health_check_enabled,
               last_health_check, health_status, metadata, created_at, updated_at
        FROM providers
        WHERE 1=1`
    
    var args []interface{}
    
    if providerType, ok := filter["type"].(string); ok && providerType != "" {
        query += " AND type = ?"
        args = append(args, providerType)
    }
    
    if active, ok := filter["active"].(bool); ok {
        query += " AND active = ?"
        args = append(args, active)
    }
    
    query += " ORDER BY type, priority DESC, name"
    
    rows, err := s.db.QueryContext(ctx, query, args...)
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query providers")
    }
    defer rows.Close()
    
    var providers []*models.Provider
    
    for rows.Next() {
        var provider models.Provider
        var codecsJSON string
        var metadataJSON sql.NullString
        
        err := rows.Scan(
            &provider.ID, &provider.Name, &provider.Type, &provider.Host, &provider.Port,
            &provider.Username, &provider.Password, &provider.AuthType, &provider.Transport,
            &codecsJSON, &provider.MaxChannels, &provider.CurrentChannels,
            &provider.Priority, &provider.Weight, &provider.CostPerMinute,
            &provider.Active, &provider.HealthCheckEnabled, &provider.LastHealthCheck,
            &provider.HealthStatus, &metadataJSON, &provider.CreatedAt, &provider.UpdatedAt,
        )
        
        if err != nil {
            logger.WithContext(ctx).WithError(err).Warn("Failed to scan provider")
            continue
        }
        
        // Parse JSON fields
        if codecsJSON != "" {
            json.Unmarshal([]byte(codecsJSON), &provider.Codecs)
        }
        if metadataJSON.Valid {
            json.Unmarshal([]byte(metadataJSON.String), &provider.Metadata)
        }
        
        providers = append(providers, &provider)
    }
    
    return providers, nil
}

func (s *Service) validateProvider(provider *models.Provider) error {
    if provider.Name == "" {
        return errors.New(errors.ErrInternal, "provider name is required")
    }
    
    if provider.Type == "" {
        return errors.New(errors.ErrInternal, "provider type is required")
    }
    
    validTypes := map[models.ProviderType]bool{
        models.ProviderTypeInbound:      true,
        models.ProviderTypeIntermediate: true,
        models.ProviderTypeFinal:        true,
    }
    
    if !validTypes[provider.Type] {
        return errors.New(errors.ErrInternal, "invalid provider type")
    }
    
    if provider.Host == "" {
        return errors.New(errors.ErrInternal, "provider host is required")
    }
    
    if provider.AuthType != "" {
        validAuthTypes := map[string]bool{
            "ip":          true,
            "credentials": true,
            "both":        true,
        }
        
        if !validAuthTypes[provider.AuthType] {
            return errors.New(errors.ErrInternal, "invalid auth type")
        }
        
        if provider.AuthType == "credentials" || provider.AuthType == "both" {
            if provider.Username == "" || provider.Password == "" {
                return errors.New(errors.ErrInternal, "username and password required for credential auth")
            }
        }
    }
    
    return nil
}

func (s *Service) TestProvider(ctx context.Context, name string) (*ProviderTestResult, error) {
    provider, err := s.GetProvider(ctx, name)
    if err != nil {
        return nil, err
    }
    
    result := &ProviderTestResult{
        ProviderName: name,
        Timestamp:    time.Now(),
        Tests:        make(map[string]TestResult),
    }
    
    // Test connectivity
    connTest := s.testConnectivity(provider)
    result.Tests["connectivity"] = connTest
    
    // Test OPTIONS if SIP
    if provider.Transport == "udp" || provider.Transport == "tcp" {
        optionsTest := s.testSIPOptions(provider)
        result.Tests["sip_options"] = optionsTest
    }
    
    // Calculate overall result
    result.Success = true
    for _, test := range result.Tests {
        if !test.Success {
            result.Success = false
            break
        }
    }
    
    return result, nil
}

type ProviderTestResult struct {
    ProviderName string                 `json:"provider_name"`
    Timestamp    time.Time              `json:"timestamp"`
    Success      bool                   `json:"success"`
    Tests        map[string]TestResult  `json:"tests"`
}

type TestResult struct {
    Success  bool          `json:"success"`
    Message  string        `json:"message"`
    Duration time.Duration `json:"duration"`
    Details  interface{}   `json:"details,omitempty"`
}

func (s *Service) testConnectivity(provider *models.Provider) TestResult {
    start := time.Now()
    
    conn, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", provider.Host, provider.Port), 5*time.Second)
    duration := time.Since(start)
    
    if err != nil {
        return TestResult{
            Success:  false,
            Message:  fmt.Sprintf("Connection failed: %v", err),
            Duration: duration,
        }
    }
    
    conn.Close()
    
    return TestResult{
        Success:  true,
        Message:  "TCP connection successful",
        Duration: duration,
    }
}

func (s *Service) testSIPOptions(provider *models.Provider) TestResult {
    // This would implement SIP OPTIONS testing
    // For now, return a placeholder
    return TestResult{
        Success: true,
        Message: "SIP OPTIONS test not implemented",
    }
}

// BatchCreateProviders creates multiple providers
func (s *Service) BatchCreateProviders(ctx context.Context, providers []*models.Provider) error {
    tx, err := s.db.BeginTx(ctx, nil)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
    }
    defer tx.Rollback()
    
    for _, provider := range providers {
        if err := s.validateProvider(provider); err != nil {
            return fmt.Errorf("validation failed for provider %s: %w", provider.Name, err)
        }
        
        // Set defaults
        if provider.Transport == "" {
            provider.Transport = "udp"
        }
        if provider.AuthType == "" {
            provider.AuthType = "ip"
        }
        if provider.Port == 0 {
            provider.Port = 5060
        }
        
        codecsJSON, _ := json.Marshal(provider.Codecs)
        metadataJSON, _ := json.Marshal(provider.Metadata)
        
        query := `
            INSERT INTO providers (
                name, type, host, port, username, password, auth_type,
                transport, codecs, max_channels, priority, weight,
                cost_per_minute, active, health_check_enabled, metadata
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
        
        if _, err := tx.ExecContext(ctx, query,
            provider.Name, provider.Type, provider.Host, provider.Port,
            provider.Username, provider.Password, provider.AuthType,
            provider.Transport, codecsJSON, provider.MaxChannels,
            provider.Priority, provider.Weight, provider.CostPerMinute,
            provider.Active, provider.HealthCheckEnabled, metadataJSON,
        ); err != nil {
            return errors.Wrap(err, errors.ErrDatabase, fmt.Sprintf("failed to insert provider %s", provider.Name))
        }
        
        // Create ARA endpoint
        if err := s.araManager.CreateEndpoint(ctx, provider); err != nil {
            return errors.Wrap(err, errors.ErrInternal, fmt.Sprintf("failed to create ARA endpoint for %s", provider.Name))
        }
    }
    
    if err := tx.Commit(); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to commit transaction")
    }
    
    // Reload PJSIP once for all providers
    if s.amiManager != nil {
        if err := s.amiManager.ReloadPJSIP(); err != nil {
            logger.WithContext(ctx).WithError(err).Warn("Failed to reload PJSIP via AMI")
        }
    }
    
    return nil
}

// UpdateProviderHealth updates provider health status
func (s *Service) UpdateProviderHealth(ctx context.Context, name string, healthy bool, score int) error {
    status := "healthy"
    if !healthy {
        status = "unhealthy"
    }
    
    query := `
        UPDATE providers 
        SET health_status = ?, 
            last_health_check = NOW(),
            updated_at = NOW()
        WHERE name = ?`
    
    if _, err := s.db.ExecContext(ctx, query, status, name); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to update provider health")
    }
    
    // Also update provider_health table
    healthQuery := `
        INSERT INTO provider_health (provider_name, health_score, is_healthy, updated_at)
        VALUES (?, ?, ?, NOW())
        ON DUPLICATE KEY UPDATE
            health_score = VALUES(health_score),
            is_healthy = VALUES(is_healthy),
            updated_at = NOW()`
    
    if _, err := s.db.ExecContext(ctx, healthQuery, name, score, healthy); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to update provider health score")
    }
    
    return nil
}

// GetProviderStats returns provider statistics
func (s *Service) GetProviderStats(ctx context.Context, name string, period string) (*models.ProviderStats, error) {
    var stats models.ProviderStats
    stats.ProviderName = name
    
    // Get current active calls and health
    healthQuery := `
        SELECT active_calls, is_healthy
        FROM provider_health
        WHERE provider_name = ?`
    
    var activeCalls int64
    var isHealthy bool
    
    err := s.db.QueryRowContext(ctx, healthQuery, name).Scan(&activeCalls, &isHealthy)
    if err != nil && err != sql.ErrNoRows {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query provider health")
    }
    
    stats.ActiveCalls = activeCalls
    stats.IsHealthy = isHealthy
    
    // Get statistics for the period
    statQuery := `
        SELECT 
            COALESCE(SUM(total_calls), 0) as total_calls,
            COALESCE(SUM(completed_calls), 0) as completed_calls,
            COALESCE(SUM(failed_calls), 0) as failed_calls,
            COALESCE(AVG(asr), 0) as success_rate,
            COALESCE(AVG(acd), 0) as avg_duration,
            COALESCE(AVG(avg_response_time), 0) as avg_response_time
        FROM provider_stats
        WHERE provider_name = ? AND stat_type = ?
        AND period_start >= DATE_SUB(NOW(), INTERVAL 1 ?)`
    
    var totalCalls, completedCalls, failedCalls int64
    var successRate, avgDuration float64
    var avgResponseTime int
    
    err = s.db.QueryRowContext(ctx, statQuery, name, period, period).Scan(
        &totalCalls, &completedCalls, &failedCalls,
        &successRate, &avgDuration, &avgResponseTime,
    )
    
    if err != nil && err != sql.ErrNoRows {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query provider stats")
    }
    
    stats.TotalCalls = totalCalls
    stats.CompletedCalls = completedCalls
    stats.FailedCalls = failedCalls
    stats.SuccessRate = successRate
    stats.AvgCallDuration = avgDuration
    stats.AvgResponseTime = avgResponseTime
    stats.LastCallTime = time.Now() // This should be updated from actual call records
    
    return &stats, nil
}
package router

import (
    "context"
    "database/sql"
    "fmt"
    "sync"
    "time"
    
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
)

// DIDManager handles DID allocation and management
type DIDManager struct {
    db    *sql.DB
    cache CacheInterface
    
    mu         sync.RWMutex
    didToCall  map[string]string // DID -> CallID mapping
}

// NewDIDManager creates a new DID manager
func NewDIDManager(db *sql.DB, cache CacheInterface) *DIDManager {
    return &DIDManager{
        db:        db,
        cache:     cache,
        didToCall: make(map[string]string),
    }
}

// AllocateDID allocates a DID for a call
func (dm *DIDManager) AllocateDID(ctx context.Context, tx *sql.Tx, providerName, destination string) (string, error) {
    // Use distributed lock to prevent race conditions
    lockKey := fmt.Sprintf("did:allocation:%s", providerName)
    unlock, err := dm.cache.Lock(ctx, lockKey, 5*time.Second)
    if err != nil {
        return "", errors.Wrap(err, errors.ErrInternal, "failed to acquire DID lock")
    }
    defer unlock()
    
    // Try to get DID for specific provider first
    query := `
        SELECT number 
        FROM dids 
        WHERE in_use = 0 AND provider_name = ?
        ORDER BY last_used_at ASC, RAND()
        LIMIT 1
        FOR UPDATE`
    
    var did string
    err = tx.QueryRowContext(ctx, query, providerName).Scan(&did)
    
    if err == sql.ErrNoRows {
        // Try any available DID
        err = tx.QueryRowContext(ctx, `
            SELECT number 
            FROM dids 
            WHERE in_use = 0
            ORDER BY last_used_at ASC, RAND()
            LIMIT 1
            FOR UPDATE`).Scan(&did)
    }
    
    if err != nil {
        return "", errors.New(errors.ErrDIDNotAvailable, "no available DIDs")
    }
    
    // Mark DID as in use
    updateQuery := `
        UPDATE dids 
        SET in_use = 1, 
            destination = ?, 
            allocation_time = NOW(),
            usage_count = COALESCE(usage_count, 0) + 1,
            updated_at = NOW()
        WHERE number = ?`
    
    if _, err := tx.ExecContext(ctx, updateQuery, destination, did); err != nil {
        return "", errors.Wrap(err, errors.ErrDatabase, "failed to allocate DID")
    }
    
    // Clear DID cache
    dm.cache.Delete(ctx, fmt.Sprintf("did:%s", did))
    dm.cache.Delete(ctx, "did:stats")
    
    logger.WithContext(ctx).WithFields(map[string]interface{}{
        "did": did,
        "provider": providerName,
        "destination": destination,
    }).Debug("DID allocated")
    
    return did, nil
}

// ReleaseDID releases a DID back to the pool
func (dm *DIDManager) ReleaseDID(ctx context.Context, tx *sql.Tx, did string) error {
    if did == "" {
        return nil
    }
    
    query := `
        UPDATE dids 
        SET in_use = 0, 
            destination = NULL,
            allocation_time = NULL,
            released_at = NOW(),
            last_used_at = NOW(),
            updated_at = NOW()
        WHERE number = ?`
    
    if _, err := tx.ExecContext(ctx, query, did); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to release DID")
    }
    
    // Clear DID cache
    dm.cache.Delete(ctx, fmt.Sprintf("did:%s", did))
    dm.cache.Delete(ctx, "did:stats")
    
    logger.WithContext(ctx).WithField("did", did).Debug("DID released")
    
    return nil
}

// RegisterCallDID registers a DID-to-Call mapping
func (dm *DIDManager) RegisterCallDID(did, callID string) {
    dm.mu.Lock()
    defer dm.mu.Unlock()
    dm.didToCall[did] = callID
}

// UnregisterCallDID removes a DID-to-Call mapping
func (dm *DIDManager) UnregisterCallDID(did string) {
    dm.mu.Lock()
    defer dm.mu.Unlock()
    delete(dm.didToCall, did)
}

// GetCallIDByDID returns the call ID associated with a DID
func (dm *DIDManager) GetCallIDByDID(did string) string {
    dm.mu.RLock()
    defer dm.mu.RUnlock()
    return dm.didToCall[did]
}

// GetStatistics returns DID pool statistics
func (dm *DIDManager) GetStatistics(ctx context.Context) (map[string]interface{}, error) {
    // Try cache first
    cacheKey := "did:stats"
    var stats map[string]interface{}
    if err := dm.cache.Get(ctx, cacheKey, &stats); err == nil {
        return stats, nil
    }
    
    // Query database - Fixed to handle NULL values properly
    var totalDIDs, usedDIDs, availableDIDs sql.NullInt64
    err := dm.db.QueryRowContext(ctx, `
        SELECT 
            COUNT(*) as total,
            COALESCE(SUM(CASE WHEN in_use = 1 THEN 1 ELSE 0 END), 0) as used,
            COALESCE(SUM(CASE WHEN in_use = 0 THEN 1 ELSE 0 END), 0) as available
        FROM dids
    `).Scan(&totalDIDs, &usedDIDs, &availableDIDs)
    
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to get DID statistics")
    }
    
    total := int(totalDIDs.Int64)
    used := int(usedDIDs.Int64)
    available := int(availableDIDs.Int64)
    
    stats = map[string]interface{}{
        "total_dids":      total,
        "used_dids":       used,
        "available_dids":  available,
        "did_utilization": 0.0,
    }
    
    if total > 0 {
        stats["did_utilization"] = float64(used) / float64(total) * 100
    }
    
    // Cache for 30 seconds
    dm.cache.Set(ctx, cacheKey, stats, 30*time.Second)
    
    return stats, nil
}

// GetDIDDetails returns detailed information about a DID
func (dm *DIDManager) GetDIDDetails(ctx context.Context, did string) (map[string]interface{}, error) {
    query := `
        SELECT number, provider_name, in_use, destination,
               allocation_time, last_used_at, usage_count, country, city,
               monthly_cost, per_minute_cost, created_at, updated_at
        FROM dids
        WHERE number = ?`
    
    var details struct {
        Number         string
        ProviderName   string
        InUse          bool
        Destination    sql.NullString
        AllocationTime sql.NullTime
        LastUsedAt     sql.NullTime
        UsageCount     sql.NullInt64
        Country        sql.NullString
        City           sql.NullString
        MonthlyCost    float64
        PerMinuteCost  float64
        CreatedAt      time.Time
        UpdatedAt      time.Time
    }
    
    err := dm.db.QueryRowContext(ctx, query, did).Scan(
        &details.Number, &details.ProviderName, &details.InUse,
        &details.Destination, &details.AllocationTime,
        &details.LastUsedAt, &details.UsageCount, &details.Country,
        &details.City, &details.MonthlyCost, &details.PerMinuteCost,
        &details.CreatedAt, &details.UpdatedAt,
    )
    
    if err == sql.ErrNoRows {
        return nil, errors.New(errors.ErrDIDNotAvailable, "DID not found")
    }
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to get DID details")
    }
    
    result := map[string]interface{}{
        "number":         details.Number,
        "provider_name":  details.ProviderName,
        "in_use":         details.InUse,
        "monthly_cost":   details.MonthlyCost,
        "per_minute_cost": details.PerMinuteCost,
        "created_at":     details.CreatedAt,
        "updated_at":     details.UpdatedAt,
    }
    
    if details.Destination.Valid {
        result["destination"] = details.Destination.String
    }
    if details.AllocationTime.Valid {
        result["allocation_time"] = details.AllocationTime.Time
    }
    if details.LastUsedAt.Valid {
        result["last_used_at"] = details.LastUsedAt.Time
    }
    if details.UsageCount.Valid {
        result["usage_count"] = details.UsageCount.Int64
    }
    if details.Country.Valid {
        result["country"] = details.Country.String
    }
    if details.City.Valid {
        result["city"] = details.City.String
    }
    
    // Get current call if in use
    if details.InUse {
        if callID := dm.GetCallIDByDID(did); callID != "" {
            result["current_call_id"] = callID
        }
    }
    
    return result, nil
}

// GetAvailableDIDCount returns the count of available DIDs
func (dm *DIDManager) GetAvailableDIDCount(ctx context.Context, providerName string) (int, error) {
    var count int
    query := "SELECT COUNT(*) FROM dids WHERE in_use = 0"
    args := []interface{}{}
    
    if providerName != "" {
        query += " AND provider_name = ?"
        args = append(args, providerName)
    }
    
    err := dm.db.QueryRowContext(ctx, query, args...).Scan(&count)
    if err != nil {
        return 0, errors.Wrap(err, errors.ErrDatabase, "failed to count available DIDs")
    }
    
    return count, nil
}

// CleanupStaleDIDs releases DIDs that have been allocated for too long
func (dm *DIDManager) CleanupStaleDIDs(ctx context.Context, timeout time.Duration) error {
    query := `
        UPDATE dids 
        SET in_use = 0, 
            destination = NULL,
            allocation_time = NULL,
            released_at = NOW(),
            last_used_at = NOW(),
            updated_at = NOW()
        WHERE in_use = 1 
        AND allocation_time IS NOT NULL 
        AND allocation_time < DATE_SUB(NOW(), INTERVAL ? SECOND)`
    
    result, err := dm.db.ExecContext(ctx, query, int(timeout.Seconds()))
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to cleanup stale DIDs")
    }
    
    rows, _ := result.RowsAffected()
    if rows > 0 {
        logger.WithContext(ctx).WithField("count", rows).Info("Released stale DIDs")
        dm.cache.Delete(ctx, "did:stats")
    }
    
    return nil
}

// GetProviderDIDUtilization returns DID utilization by provider
func (dm *DIDManager) GetProviderDIDUtilization(ctx context.Context) ([]map[string]interface{}, error) {
    query := `
        SELECT 
            provider_name,
            COUNT(*) as total_dids,
            SUM(CASE WHEN in_use = 1 THEN 1 ELSE 0 END) as used_dids,
            SUM(CASE WHEN in_use = 0 THEN 1 ELSE 0 END) as available_dids,
            ROUND((SUM(CASE WHEN in_use = 1 THEN 1 ELSE 0 END) / COUNT(*)) * 100, 2) as utilization_percent
        FROM dids
        GROUP BY provider_name
        ORDER BY utilization_percent DESC`
    
    rows, err := dm.db.QueryContext(ctx, query)
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to get provider DID utilization")
    }
    defer rows.Close()
    
    var results []map[string]interface{}
    for rows.Next() {
        var provider string
        var total, used, available int
        var utilization float64
        
        if err := rows.Scan(&provider, &total, &used, &available, &utilization); err != nil {
            continue
        }
        
        results = append(results, map[string]interface{}{
            "provider_name":       provider,
            "total_dids":          total,
            "used_dids":           used,
            "available_dids":      available,
            "utilization_percent": utilization,
        })
    }
    
    return results, nil
}


package router

import (
    "context"
    "crypto/md5"
    "database/sql"
    "encoding/binary"
    "encoding/json"  // Added missing import
    "fmt"
    "math/rand"
    "sort"
    "sync"
    "sync/atomic"
    "time"
    
    "github.com/hamzaKhattat/ara-production-system/internal/models"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"  // Added missing import
)

type LoadBalancer struct {
    db      *sql.DB
    cache   CacheInterface
    metrics MetricsInterface
    
    mu sync.RWMutex
    
    // Round-robin counters
    rrCounters map[string]*uint64
    
    // Provider health tracking
    providerHealth map[string]*ProviderHealthInfo
    
    // Response time tracking
    responseTimes map[string]*ResponseTimeTracker
}

type ProviderHealthInfo struct {
    mu                  sync.RWMutex
    ActiveCalls         int64
    TotalCalls          int64
    FailedCalls         int64
    ConsecutiveFailures int
    LastSuccess         time.Time
    LastFailure         time.Time
    HealthScore         int
    IsHealthy           bool
}

type ResponseTimeTracker struct {
    mu           sync.RWMutex
    samples      []float64
    currentIndex int
    sum          float64
    count        int
}

func NewLoadBalancer(db *sql.DB, cache CacheInterface, metrics MetricsInterface) *LoadBalancer {
    lb := &LoadBalancer{
        db:             db,
        cache:          cache,
        metrics:        metrics,
        rrCounters:     make(map[string]*uint64),
        providerHealth: make(map[string]*ProviderHealthInfo),
        responseTimes:  make(map[string]*ResponseTimeTracker),
    }
    
    // Start health monitoring
    go lb.healthMonitor()
    
    return lb
}

func (lb *LoadBalancer) SelectProvider(ctx context.Context, providerSpec string, mode models.LoadBalanceMode) (*models.Provider, error) {
    // Get available providers
    providers, err := lb.getAvailableProviders(ctx, providerSpec)
    if err != nil {
        return nil, err
    }
    
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no available providers")
    }
    
    // Filter healthy providers
    healthyProviders := lb.filterHealthyProviders(providers)
    if len(healthyProviders) == 0 {
        // If no healthy providers, try all providers
        logger.WithContext(ctx).Warn("No healthy providers, using all available")
        healthyProviders = providers
    }
    
    // Select based on mode
    switch mode {
    case models.LoadBalanceModeRoundRobin:
        return lb.selectRoundRobin(providerSpec, healthyProviders)
    case models.LoadBalanceModeWeighted:
        return lb.selectWeighted(healthyProviders)
    case models.LoadBalanceModePriority:
        return lb.selectPriority(healthyProviders)
    case models.LoadBalanceModeFailover:
        return lb.selectFailover(healthyProviders)
    case models.LoadBalanceModeLeastConnections:
        return lb.selectLeastConnections(healthyProviders)
    case models.LoadBalanceModeResponseTime:
        return lb.selectResponseTime(healthyProviders)
    case models.LoadBalanceModeHash:
        // For hash mode, we need additional context (like call ID)
        return lb.selectHash(ctx, healthyProviders)
    default:
        return lb.selectRoundRobin(providerSpec, healthyProviders)
    }
}

func (lb *LoadBalancer) getAvailableProviders(ctx context.Context, providerSpec string) ([]*models.Provider, error) {
    // Try cache first
    cacheKey := fmt.Sprintf("providers:%s", providerSpec)
    var providers []*models.Provider
    
    if err := lb.cache.Get(ctx, cacheKey, &providers); err == nil {
        return providers, nil
    }
    
    // Query database
    query := `
        SELECT id, name, type, host, port, username, password, auth_type,
               transport, codecs, max_channels, current_channels, priority,
               weight, cost_per_minute, active, health_check_enabled,
               last_health_check, health_status, metadata
        FROM providers
        WHERE active = 1 AND (name = ? OR type = ?)
        ORDER BY priority DESC, weight DESC`
    
    rows, err := lb.db.QueryContext(ctx, query, providerSpec, providerSpec)
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query providers")
    }
    defer rows.Close()
    
    providers = make([]*models.Provider, 0)
    for rows.Next() {
        var p models.Provider
        var codecsJSON string
        
        err := rows.Scan(
            &p.ID, &p.Name, &p.Type, &p.Host, &p.Port,
            &p.Username, &p.Password, &p.AuthType, &p.Transport,
            &codecsJSON, &p.MaxChannels, &p.CurrentChannels,
            &p.Priority, &p.Weight, &p.CostPerMinute, &p.Active,
            &p.HealthCheckEnabled, &p.LastHealthCheck, &p.HealthStatus,
            &p.Metadata,
        )
        
        if err != nil {
            logger.WithContext(ctx).WithError(err).Warn("Failed to scan provider")
            continue
        }
        
        // Parse codecs
        if codecsJSON != "" {
            json.Unmarshal([]byte(codecsJSON), &p.Codecs)
        }
        
        providers = append(providers, &p)
    }
    
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers found")
    }
    
    // Cache for 30 seconds
    lb.cache.Set(ctx, cacheKey, providers, 30*time.Second)
    
    return providers, nil
}

func (lb *LoadBalancer) filterHealthyProviders(providers []*models.Provider) []*models.Provider {
    healthy := make([]*models.Provider, 0, len(providers))
    
    for _, p := range providers {
        health := lb.getProviderHealth(p.Name)
        
        // Check if healthy
        if health.IsHealthy {
            // Check channel limits
            if p.MaxChannels == 0 || health.ActiveCalls < int64(p.MaxChannels) {
                healthy = append(healthy, p)
            }
        }
    }
    
    return healthy
}

func (lb *LoadBalancer) selectRoundRobin(key string, providers []*models.Provider) (*models.Provider, error) {
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers available")
    }
    
    // Get or create counter
    counter, exists := lb.rrCounters[key]
    if !exists {
        var c uint64
        counter = &c
        lb.rrCounters[key] = counter
    }
    
    // Increment and select
    index := atomic.AddUint64(counter, 1) % uint64(len(providers))
    return providers[index], nil
}

func (lb *LoadBalancer) selectWeighted(providers []*models.Provider) (*models.Provider, error) {
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers available")
    }
    
    // Calculate total weight
    totalWeight := 0
    for _, p := range providers {
        totalWeight += p.Weight
    }
    
    if totalWeight == 0 {
        // If no weights, fallback to random
        return providers[rand.Intn(len(providers))], nil
    }
    
    // Random weighted selection
    r := rand.Intn(totalWeight)
    for _, p := range providers {
        r -= p.Weight
        if r < 0 {
            return p, nil
        }
    }
    
    return providers[len(providers)-1], nil
}

func (lb *LoadBalancer) selectPriority(providers []*models.Provider) (*models.Provider, error) {
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers available")
    }
    
    // Sort by priority (already sorted in query, but double-check)
    sort.Slice(providers, func(i, j int) bool {
        return providers[i].Priority > providers[j].Priority
    })
    
    // Select highest priority
    return providers[0], nil
}

func (lb *LoadBalancer) selectFailover(providers []*models.Provider) (*models.Provider, error) {
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers available")
    }
    
    // Sort by priority
    sort.Slice(providers, func(i, j int) bool {
        return providers[i].Priority > providers[j].Priority
    })
    
    // Return first healthy provider
    for _, p := range providers {
        health := lb.getProviderHealth(p.Name)
        if health.IsHealthy && health.ConsecutiveFailures == 0 {
            return p, nil
        }
    }
    
    // If no perfect provider, return least failed
    var bestProvider *models.Provider
    minFailures := int(^uint(0) >> 1) // Max int
    
    for _, p := range providers {
        health := lb.getProviderHealth(p.Name)
        if health.ConsecutiveFailures < minFailures {
            minFailures = health.ConsecutiveFailures
            bestProvider = p
        }
    }
    
    return bestProvider, nil
}

func (lb *LoadBalancer) selectLeastConnections(providers []*models.Provider) (*models.Provider, error) {
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers available")
    }
    
    var selectedProvider *models.Provider
    minConnections := int64(^uint64(0) >> 1) // Max int64
    
    for _, p := range providers {
        health := lb.getProviderHealth(p.Name)
        if health.ActiveCalls < minConnections {
            minConnections = health.ActiveCalls
            selectedProvider = p
        }
    }
    
    if selectedProvider == nil {
        return providers[0], nil
    }
    
    return selectedProvider, nil
}

func (lb *LoadBalancer) selectResponseTime(providers []*models.Provider) (*models.Provider, error) {
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers available")
    }
    
    var selectedProvider *models.Provider
    minResponseTime := float64(^uint64(0) >> 1)
    
    for _, p := range providers {
        rt := lb.getAverageResponseTime(p.Name)
        if rt < minResponseTime && rt > 0 {
            minResponseTime = rt
            selectedProvider = p
        }
    }
    
    if selectedProvider == nil {
        // No response time data, fallback to random
        return providers[rand.Intn(len(providers))], nil
    }
    
    return selectedProvider, nil
}

func (lb *LoadBalancer) selectHash(ctx context.Context, providers []*models.Provider) (*models.Provider, error) {
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers available")
    }
    
    // Get hash key from context (e.g., call ID or ANI)
    hashKey := ""
    if callID := ctx.Value("call_id"); callID != nil {
        hashKey = callID.(string)
    }
    
    if hashKey == "" {
        // No hash key, fallback to random
        return providers[rand.Intn(len(providers))], nil
    }
    
    // Calculate hash
    h := md5.Sum([]byte(hashKey))
    hashValue := binary.BigEndian.Uint32(h[:4])
    
    // Select provider based on hash
    index := hashValue % uint32(len(providers))
    return providers[index], nil
}

func (lb *LoadBalancer) getProviderHealth(providerName string) *ProviderHealthInfo {
    lb.mu.Lock()
    defer lb.mu.Unlock()
    
    health, exists := lb.providerHealth[providerName]
    if !exists {
        health = &ProviderHealthInfo{
            IsHealthy:   true,
            HealthScore: 100,
            LastSuccess: time.Now(),
        }
        lb.providerHealth[providerName] = health
    }
    
    return health
}

func (lb *LoadBalancer) getAverageResponseTime(providerName string) float64 {
    lb.mu.RLock()
    defer lb.mu.RUnlock()
    
    tracker, exists := lb.responseTimes[providerName]
    if !exists || tracker.count == 0 {
        return 0
    }
    
    tracker.mu.RLock()
    defer tracker.mu.RUnlock()
    
    return tracker.sum / float64(tracker.count)
}

// Public methods for updating stats

func (lb *LoadBalancer) IncrementActiveCalls(providerName string) {
    health := lb.getProviderHealth(providerName)
    health.mu.Lock()
    health.ActiveCalls++
    health.mu.Unlock()
    
    lb.metrics.SetGauge("provider_active_calls", float64(health.ActiveCalls), map[string]string{
        "provider": providerName,
    })
}

func (lb *LoadBalancer) DecrementActiveCalls(providerName string) {
    health := lb.getProviderHealth(providerName)
    health.mu.Lock()
    if health.ActiveCalls > 0 {
        health.ActiveCalls--
    }
    health.mu.Unlock()
    
    lb.metrics.SetGauge("provider_active_calls", float64(health.ActiveCalls), map[string]string{
        "provider": providerName,
    })
}

func (lb *LoadBalancer) UpdateCallComplete(providerName string, success bool, duration time.Duration) {
    health := lb.getProviderHealth(providerName)
    
    health.mu.Lock()
    health.TotalCalls++
    
    if success {
        health.ConsecutiveFailures = 0
        health.LastSuccess = time.Now()
        
        // Update response time
        lb.updateResponseTime(providerName, duration.Seconds())
    } else {
        health.FailedCalls++
        health.ConsecutiveFailures++
        health.LastFailure = time.Now()
        
        // Update health score
        health.HealthScore = lb.calculateHealthScore(health)
        
        // Mark unhealthy if too many failures
        if health.ConsecutiveFailures >= 5 {
            health.IsHealthy = false
        }
    }
    health.mu.Unlock()
    
    // Update metrics
    lb.metrics.IncrementCounter("provider_calls_total", map[string]string{
        "provider": providerName,
        "status":   map[bool]string{true: "success", false: "failed"}[success],
    })
    
    if success && duration > 0 {
        lb.metrics.ObserveHistogram("provider_call_duration", duration.Seconds(), map[string]string{
            "provider": providerName,
        })
    }
    
    // Update database
    go lb.updateProviderHealthDB(providerName, health)
}

func (lb *LoadBalancer) updateResponseTime(providerName string, responseTime float64) {
    lb.mu.Lock()
    tracker, exists := lb.responseTimes[providerName]
    if !exists {
        tracker = &ResponseTimeTracker{
            samples: make([]float64, 100), // Keep last 100 samples
        }
        lb.responseTimes[providerName] = tracker
    }
    lb.mu.Unlock()
    
    tracker.mu.Lock()
    defer tracker.mu.Unlock()
    
    // Remove old value from sum
    oldValue := tracker.samples[tracker.currentIndex]
    tracker.sum -= oldValue
    
    // Add new value
    tracker.samples[tracker.currentIndex] = responseTime
    tracker.sum += responseTime
    
    // Update count
    if tracker.count < len(tracker.samples) {
        tracker.count++
    }
    
    // Move to next position
    tracker.currentIndex = (tracker.currentIndex + 1) % len(tracker.samples)
}

func (lb *LoadBalancer) calculateHealthScore(health *ProviderHealthInfo) int {
    score := 100
    
    // Deduct for consecutive failures
    score -= health.ConsecutiveFailures * 10
    
    // Deduct for failure rate
    if health.TotalCalls > 0 {
        failureRate := float64(health.FailedCalls) / float64(health.TotalCalls)
        score -= int(failureRate * 50)
    }
    
    // Ensure score is between 0 and 100
    if score < 0 {
        score = 0
    } else if score > 100 {
        score = 100
    }
    
    return score
}

func (lb *LoadBalancer) updateProviderHealthDB(providerName string, health *ProviderHealthInfo) {
    health.mu.RLock()
    defer health.mu.RUnlock()
    
    query := `
        INSERT INTO provider_health (
            provider_name, health_score, active_calls, 
            last_success_at, last_failure_at, consecutive_failures, 
            is_healthy
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            health_score = VALUES(health_score),
            active_calls = VALUES(active_calls),
            last_success_at = VALUES(last_success_at),
            last_failure_at = VALUES(last_failure_at),
            consecutive_failures = VALUES(consecutive_failures),
            is_healthy = VALUES(is_healthy),
            updated_at = NOW()`
    
    lb.db.Exec(query, 
        providerName, health.HealthScore, health.ActiveCalls,
        health.LastSuccess, health.LastFailure, health.ConsecutiveFailures,
        health.IsHealthy,
    )
}

func (lb *LoadBalancer) healthMonitor() {
    ticker := time.NewTicker(30 * time.Second)
    defer ticker.Stop()
    
    for range ticker.C {
        lb.checkProviderHealth()
    }
}

func (lb *LoadBalancer) checkProviderHealth() {
    lb.mu.Lock()
    defer lb.mu.Unlock()
    
    now := time.Now()
    
    for name, health := range lb.providerHealth {
        health.mu.Lock()
        
        // Auto-recover if no failures in last 5 minutes
        if !health.IsHealthy && now.Sub(health.LastFailure) > 5*time.Minute {
            health.IsHealthy = true
            health.ConsecutiveFailures = 0
            health.HealthScore = 100
            logger.WithField("provider", name).Info("Provider auto-recovered")
        }
        
        // Check for stale providers
        if health.ActiveCalls == 0 && now.Sub(health.LastSuccess) > 24*time.Hour {
            // Remove from memory to save space
            delete(lb.providerHealth, name)
        }
        
        health.mu.Unlock()
    }
}

// GetProviderStats returns current stats for monitoring
func (lb *LoadBalancer) GetProviderStats() map[string]*models.ProviderStats {
    lb.mu.RLock()
    defer lb.mu.RUnlock()
    
    stats := make(map[string]*models.ProviderStats)
    
    for name, health := range lb.providerHealth {
        health.mu.RLock()
        
        successRate := float64(0)
        if health.TotalCalls > 0 {
            successRate = float64(health.TotalCalls-health.FailedCalls) / float64(health.TotalCalls) * 100
        }
        
        stats[name] = &models.ProviderStats{
            ProviderName:    name,
            TotalCalls:      health.TotalCalls,
            ActiveCalls:     health.ActiveCalls,
            FailedCalls:     health.FailedCalls,
            SuccessRate:     successRate,
            AvgResponseTime: int(lb.getAverageResponseTime(name) * 1000), // Convert to ms
            LastCallTime:    health.LastSuccess,
            IsHealthy:       health.IsHealthy,
        }
        
        health.mu.RUnlock()
    }
    
    return stats
}
// Add this method to the LoadBalancer struct

// SelectFromProviders selects a provider from a given list using the specified load balance mode
func (lb *LoadBalancer) SelectFromProviders(ctx context.Context, providers []*models.Provider, mode models.LoadBalanceMode) (*models.Provider, error) {
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers available")
    }
    
    // Filter healthy providers
    healthyProviders := lb.filterHealthyProviders(providers)
    if len(healthyProviders) == 0 {
        // If no healthy providers, try all providers
        logger.WithContext(ctx).Warn("No healthy providers in list, using all available")
        healthyProviders = providers
    }
    
    // Select based on mode
    switch mode {
    case models.LoadBalanceModeRoundRobin:
        // For groups, use the group name as the round-robin key
        key := fmt.Sprintf("group:%v", time.Now().UnixNano()) // Unique key for this selection
        return lb.selectRoundRobin(key, healthyProviders)
    case models.LoadBalanceModeWeighted:
        return lb.selectWeighted(healthyProviders)
    case models.LoadBalanceModePriority:
        return lb.selectPriority(healthyProviders)
    case models.LoadBalanceModeFailover:
        return lb.selectFailover(healthyProviders)
    case models.LoadBalanceModeLeastConnections:
        return lb.selectLeastConnections(healthyProviders)
    case models.LoadBalanceModeResponseTime:
        return lb.selectResponseTime(healthyProviders)
    case models.LoadBalanceModeHash:
        return lb.selectHash(ctx, healthyProviders)
    default:
        return lb.selectRoundRobin(fmt.Sprintf("default:%v", time.Now().UnixNano()), healthyProviders)
    }
}
package router

import (
    "context"
    "database/sql"
    "encoding/json"
    "fmt"
    "strings"
    "sync"
    "time"
    
    "github.com/hamzaKhattat/ara-production-system/internal/models"
    "github.com/hamzaKhattat/ara-production-system/internal/provider"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
)

// Router handles call routing logic
type Router struct {
    db           *sql.DB
    cache        CacheInterface
    loadBalancer *LoadBalancer
    metrics      MetricsInterface
    didManager   *DIDManager
    
    mu          sync.RWMutex
    activeCalls map[string]*models.CallRecord
    
    config Config
}

// Config holds router configuration
type Config struct {
    DIDAllocationTimeout time.Duration
    CallCleanupInterval  time.Duration
    StaleCallTimeout     time.Duration
    MaxRetries           int
    VerificationEnabled  bool
    StrictMode           bool
}

// CacheInterface defines cache operations
type CacheInterface interface {
    Get(ctx context.Context, key string, dest interface{}) error
    Set(ctx context.Context, key string, value interface{}, expiration time.Duration) error
    Delete(ctx context.Context, keys ...string) error
    Lock(ctx context.Context, key string, ttl time.Duration) (func(), error)
}

// MetricsInterface defines metrics operations
type MetricsInterface interface {
    IncrementCounter(name string, labels map[string]string)
    ObserveHistogram(name string, value float64, labels map[string]string)
    SetGauge(name string, value float64, labels map[string]string)
}

// NewRouter creates a new router instance
func NewRouter(db *sql.DB, cache CacheInterface, metrics MetricsInterface, config Config) *Router {
    r := &Router{
        db:           db,
        cache:        cache,
        loadBalancer: NewLoadBalancer(db, cache, metrics),
        metrics:      metrics,
        didManager:   NewDIDManager(db, cache),
        activeCalls:  make(map[string]*models.CallRecord),
        config:       config,
    }
    
    // Start cleanup routine
    go r.cleanupRoutine()
    
    return r
}

// ProcessIncomingCall handles incoming calls from S1 (Step 1 in UML)
func (r *Router) ProcessIncomingCall(ctx context.Context, callID, ani, dnis, inboundProvider string) (*models.CallResponse, error) {
    log := logger.WithContext(ctx).WithFields(map[string]interface{}{
        "call_id": callID,
        "ani": ani,
        "dnis": dnis,
        "inbound_provider": inboundProvider,
    })
    
    log.Info("Processing incoming call from S1")
    
    // Start transaction
    tx, err := r.db.BeginTx(ctx, nil)
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
    }
    defer tx.Rollback()
    
    // Get route for this inbound provider (supports groups)
    route, err := r.getRouteForProvider(ctx, tx, inboundProvider)
    if err != nil {
        r.metrics.IncrementCounter("router_calls_failed", map[string]string{
            "reason": "no_route",
            "provider": inboundProvider,
        })
        return nil, err
    }
    
    log.WithField("route", route.Name).Debug("Found route for inbound provider")
    
    // Select intermediate provider (handle group or individual)
    intermediateProvider, err := r.selectProvider(ctx, route.IntermediateProvider, route.IntermediateIsGroup, route.LoadBalanceMode)
    if err != nil {
        r.metrics.IncrementCounter("router_calls_failed", map[string]string{
            "reason": "no_intermediate_provider",
            "route": route.Name,
        })
        return nil, err
    }
    
    // Select final provider (handle group or individual)
    finalProvider, err := r.selectProvider(ctx, route.FinalProvider, route.FinalIsGroup, route.LoadBalanceMode)
    if err != nil {
        r.metrics.IncrementCounter("router_calls_failed", map[string]string{
            "reason": "no_final_provider",
            "route": route.Name,
        })
        return nil, err
    }
    
    // Allocate DID
    did, err := r.didManager.AllocateDID(ctx, tx, intermediateProvider.Name, dnis)
    if err != nil {
        r.metrics.IncrementCounter("router_calls_failed", map[string]string{
            "reason": "no_did_available",
            "provider": intermediateProvider.Name,
        })
        return nil, err
    }
    
    // Create call record
    record := &models.CallRecord{
        CallID:               callID,
        OriginalANI:          ani,
        OriginalDNIS:         dnis,
        TransformedANI:       dnis, // ANI-2 = DNIS-1
        AssignedDID:          did,
        InboundProvider:      inboundProvider,
        IntermediateProvider: intermediateProvider.Name,
        FinalProvider:        finalProvider.Name,
        RouteName:            route.Name,
        Status:               models.CallStatusActive,
        CurrentStep:          "S1_TO_S2",
        StartTime:            time.Now(),
        RecordingPath:        fmt.Sprintf("/var/spool/asterisk/monitor/%s.wav", callID),
    }
    
    // Store call record in database
    if err := r.storeCallRecord(ctx, tx, record); err != nil {
        r.didManager.ReleaseDID(ctx, tx, did)
        return nil, err
    }
    
    // Update route current calls
    if err := r.incrementRouteCalls(ctx, tx, route.ID); err != nil {
        log.WithError(err).Warn("Failed to update route call count")
    }
    
    // Commit transaction
    if err := tx.Commit(); err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to commit transaction")
    }
    
    // Store in memory after successful commit
    r.mu.Lock()
    r.activeCalls[callID] = record
    r.didManager.RegisterCallDID(did, callID)
    r.mu.Unlock()
    
    // Update metrics
    r.updateMetricsForNewCall(route.Name)
    
    // Update load balancer stats
    r.loadBalancer.IncrementActiveCalls(intermediateProvider.Name)
    r.loadBalancer.IncrementActiveCalls(finalProvider.Name)
    
    // Prepare response
    response := &models.CallResponse{
        Status:      "success",
        DIDAssigned: did,
        NextHop:     fmt.Sprintf("endpoint-%s", intermediateProvider.Name),
        ANIToSend:   dnis,  // ANI-2 = DNIS-1
        DNISToSend:  did,   // DID
    }
    
    log.WithFields(map[string]interface{}{
        "did_assigned": did,
        "next_hop": response.NextHop,
        "intermediate": intermediateProvider.Name,
        "final": finalProvider.Name,
    }).Info("Incoming call processed successfully")
    
    return response, nil
}

// ProcessReturnCall handles call returning from S3 (Step 3 in UML)
func (r *Router) ProcessReturnCall(ctx context.Context, ani2, did, provider, sourceIP string) (*models.CallResponse, error) {
    log := logger.WithContext(ctx).WithFields(map[string]interface{}{
        "ani2": ani2,
        "did": did,
        "provider": provider,
        "source_ip": sourceIP,
    })
    
    log.Info("Processing return call from S3")
    
    // Find call by DID
    callID := r.didManager.GetCallIDByDID(did)
    if callID == "" {
        return nil, errors.New(errors.ErrCallNotFound, "no active call for DID").
            WithContext("did", did)
    }
    
    r.mu.RLock()
    record, exists := r.activeCalls[callID]
    r.mu.RUnlock()
    
    if !exists || record == nil {
        return nil, errors.New(errors.ErrCallNotFound, "call record not found")
    }
    
    // Verify if enabled
    if r.config.VerificationEnabled {
        if err := r.verifyReturnCall(ctx, record, ani2, did, provider, sourceIP); err != nil {
            r.metrics.IncrementCounter("router_verification_failed", map[string]string{
                "stage": "return",
                "reason": "verification_failed",
            })
            
            if r.config.StrictMode {
                return nil, err
            }
            log.WithError(err).Warn("Verification failed but continuing (strict mode disabled)")
        }
    }
    
    // Update call state
    r.updateCallState(callID, models.CallStatusReturnedFromS3, "S3_TO_S2")
    
    // Update metrics
    r.metrics.IncrementCounter("router_calls_processed", map[string]string{
        "stage": "return",
        "route": record.RouteName,
    })
    
    // Build response for routing to S4
    response := &models.CallResponse{
        Status:     "success",
        NextHop:    fmt.Sprintf("endpoint-%s", record.FinalProvider),
        ANIToSend:  record.OriginalANI,   // Restore ANI-1
        DNISToSend: record.OriginalDNIS,  // Restore DNIS-1
    }
    
    log.WithFields(map[string]interface{}{
        "call_id": callID,
        "next_hop": response.NextHop,
        "final_provider": record.FinalProvider,
    }).Info("Return call processed successfully")
    
    return response, nil
}

// ProcessFinalCall handles the final call from S4 (Step 5 in UML)
func (r *Router) ProcessFinalCall(ctx context.Context, callID, ani, dnis, provider, sourceIP string) error {
    log := logger.WithContext(ctx).WithFields(map[string]interface{}{
        "call_id": callID,
        "ani": ani,
        "dnis": dnis,
        "provider": provider,
        "source_ip": sourceIP,
    })
    
    log.Info("Processing final call from S4")
    
    // Find call record
    record := r.findCallRecord(callID, ani, dnis)
    if record == nil {
        return errors.New(errors.ErrCallNotFound, "call not found").
            WithContext("call_id", callID).
            WithContext("ani", ani).
            WithContext("dnis", dnis)
    }
    
    // Get actual call ID (in case we found by ANI/DNIS)
    actualCallID := r.getActualCallID(callID, record)
    
    // Verify if enabled
    if r.config.VerificationEnabled {
        if err := r.verifyFinalCall(ctx, record, ani, dnis, provider, sourceIP); err != nil {
            r.metrics.IncrementCounter("router_verification_failed", map[string]string{
                "stage": "final",
                "reason": "verification_failed",
            })
            
            if r.config.StrictMode {
                return err
            }
            log.WithError(err).Warn("Verification failed but continuing")
        }
    }
    
    // Complete the call
    return r.completeCall(ctx, actualCallID, record)
}

// ProcessHangup handles call hangup from AGI
func (r *Router) ProcessHangup(ctx context.Context, callID string) error {
    log := logger.WithContext(ctx).WithField("call_id", callID)
    
    r.mu.RLock()
    record, exists := r.activeCalls[callID]
    r.mu.RUnlock()
    
    if !exists {
        // Already cleaned up
        return nil
    }
    
    log.WithField("status", record.Status).Info("Processing hangup")
    
    // Only process if not already completed
    if record.Status != models.CallStatusCompleted {
        r.handleIncompleteCall(ctx, callID, record)
    }
    
    return nil
}

// Helper methods

func (r *Router) getRouteForProvider(ctx context.Context, tx *sql.Tx, inboundProvider string) (*models.ProviderRoute, error) {
    // Try cache first
    cacheKey := fmt.Sprintf("route:inbound:%s", inboundProvider)
    var route models.ProviderRoute
    
    if err := r.cache.Get(ctx, cacheKey, &route); err == nil {
        return &route, nil
    }
    
    // Query database for both direct and group matches
    query := `
        SELECT pr.id, pr.name, pr.description, pr.inbound_provider, pr.intermediate_provider, 
               pr.final_provider, pr.load_balance_mode, pr.priority, pr.weight,
               pr.max_concurrent_calls, pr.current_calls, pr.enabled,
               pr.failover_routes, pr.routing_rules, pr.metadata,
               pr.inbound_is_group, pr.intermediate_is_group, pr.final_is_group
        FROM provider_routes pr
        WHERE pr.enabled = 1 AND (
            (pr.inbound_provider = ? AND pr.inbound_is_group = 0) OR
            (pr.inbound_is_group = 1 AND EXISTS (
                SELECT 1 FROM provider_group_members pgm
                JOIN provider_groups pg ON pgm.group_id = pg.id
                WHERE pg.name = pr.inbound_provider AND pgm.provider_name = ?
            ))
        )
        ORDER BY pr.priority DESC, pr.weight DESC
        LIMIT 1`
    
    var inboundIsGroup, intermediateIsGroup, finalIsGroup sql.NullBool
    
    err := tx.QueryRowContext(ctx, query, inboundProvider, inboundProvider).Scan(
        &route.ID, &route.Name, &route.Description,
        &route.InboundProvider, &route.IntermediateProvider, &route.FinalProvider,
        &route.LoadBalanceMode, &route.Priority, &route.Weight,
        &route.MaxConcurrentCalls, &route.CurrentCalls, &route.Enabled,
        &route.FailoverRoutes, &route.RoutingRules, &route.Metadata,
        &inboundIsGroup, &intermediateIsGroup, &finalIsGroup,
    )
    
    if err == sql.ErrNoRows {
        return nil, errors.New(errors.ErrRouteNotFound, "no route for provider").
            WithContext("provider", inboundProvider)
    }
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query route")
    }
    
    // Set boolean flags
    route.InboundIsGroup = inboundIsGroup.Valid && inboundIsGroup.Bool
    route.IntermediateIsGroup = intermediateIsGroup.Valid && intermediateIsGroup.Bool
    route.FinalIsGroup = finalIsGroup.Valid && finalIsGroup.Bool
    
    // Check concurrent call limit
    if route.MaxConcurrentCalls > 0 && route.CurrentCalls >= route.MaxConcurrentCalls {
        return nil, errors.New(errors.ErrQuotaExceeded, "route at maximum capacity")
    }
    
    // Cache for 1 minute
    r.cache.Set(ctx, cacheKey, route, time.Minute)
    
    return &route, nil
}

func (r *Router) selectProvider(ctx context.Context, providerSpec string, isGroup bool, mode models.LoadBalanceMode) (*models.Provider, error) {
    if isGroup {
        return r.selectProviderFromGroup(ctx, providerSpec, mode)
    }
    return r.loadBalancer.SelectProvider(ctx, providerSpec, mode)
}

func (r *Router) selectProviderFromGroup(ctx context.Context, groupName string, mode models.LoadBalanceMode) (*models.Provider, error) {
    groupService := provider.NewGroupService(r.db, r.cache)
    members, err := groupService.GetGroupMembers(ctx, groupName)
    if err != nil {
        return nil, err
    }
    
    if len(members) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers in group")
    }
    
    return r.loadBalancer.SelectFromProviders(ctx, members, mode)
}

func (r *Router) storeCallRecord(ctx context.Context, tx *sql.Tx, record *models.CallRecord) error {
    query := `
        INSERT INTO call_records (
            call_id, original_ani, original_dnis, transformed_ani, assigned_did,
            inbound_provider, intermediate_provider, final_provider, route_name,
            status, current_step, start_time, recording_path, metadata
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    
    metadata, _ := json.Marshal(record.Metadata)
    
    _, err := tx.ExecContext(ctx, query,
        record.CallID, record.OriginalANI, record.OriginalDNIS,
        record.TransformedANI, record.AssignedDID,
        record.InboundProvider, record.IntermediateProvider, record.FinalProvider,
        record.RouteName, record.Status, record.CurrentStep,
        record.StartTime, record.RecordingPath, metadata,
    )
    
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to store call record")
    }
    
    return nil
}

func (r *Router) updateCallRecord(ctx context.Context, tx *sql.Tx, record *models.CallRecord) error {
    query := `
        UPDATE call_records 
        SET status = ?, current_step = ?, failure_reason = ?,
            answer_time = ?, end_time = ?, duration = ?,
            billable_duration = ?, sip_response_code = ?,
            quality_score = ?, metadata = ?
        WHERE call_id = ?`
    
    metadata, _ := json.Marshal(record.Metadata)
    
    _, err := tx.ExecContext(ctx, query,
        record.Status, record.CurrentStep, record.FailureReason,
        record.AnswerTime, record.EndTime, record.Duration,
        record.BillableDuration, record.SIPResponseCode,
        record.QualityScore, metadata, record.CallID,
    )
    
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to update call record")
    }
    
    return nil
}

func (r *Router) incrementRouteCalls(ctx context.Context, tx *sql.Tx, routeID int) error {
    _, err := tx.ExecContext(ctx, 
        "UPDATE provider_routes SET current_calls = current_calls + 1 WHERE id = ?", 
        routeID)
    return err
}

func (r *Router) decrementRouteCalls(ctx context.Context, tx *sql.Tx, routeName string) error {
    _, err := tx.ExecContext(ctx,
        "UPDATE provider_routes SET current_calls = GREATEST(current_calls - 1, 0) WHERE name = ?",
        routeName)
    return err
}

func (r *Router) updateCallState(callID string, status models.CallStatus, step string) {
    r.mu.Lock()
    defer r.mu.Unlock()
    
    if record, exists := r.activeCalls[callID]; exists {
        record.Status = status
        record.CurrentStep = step
    }
}

func (r *Router) findCallRecord(callID, ani, dnis string) *models.CallRecord {
    r.mu.RLock()
    defer r.mu.RUnlock()
    
    // Try direct lookup first
    if record, exists := r.activeCalls[callID]; exists {
        return record
    }
    
    // Try to find by ANI/DNIS combination
    for _, rec := range r.activeCalls {
        if rec.OriginalANI == ani && rec.OriginalDNIS == dnis {
            return rec
        }
    }
    
    return nil
}

func (r *Router) getActualCallID(providedID string, record *models.CallRecord) string {
    r.mu.RLock()
    defer r.mu.RUnlock()
    
    // If we have the record with provided ID, use it
    if _, exists := r.activeCalls[providedID]; exists {
        return providedID
    }
    
    // Otherwise find the actual ID
    for id, rec := range r.activeCalls {
        if rec == record {
            return id
        }
    }
    
    return providedID
}

func (r *Router) completeCall(ctx context.Context, callID string, record *models.CallRecord) error {
    // Calculate duration
    duration := time.Since(record.StartTime)
    
    // Start transaction for cleanup
    tx, err := r.db.BeginTx(ctx, nil)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
    }
    defer tx.Rollback()
    
    // Update call record
    now := time.Now()
    record.Status = models.CallStatusCompleted
    record.CurrentStep = "COMPLETED"
    record.EndTime = &now
    record.Duration = int(duration.Seconds())
    record.BillableDuration = record.Duration
    
    if err := r.updateCallRecord(ctx, tx, record); err != nil {
        logger.WithContext(ctx).WithError(err).Error("Failed to update call record")
    }
    
    // Release DID
    if err := r.didManager.ReleaseDID(ctx, tx, record.AssignedDID); err != nil {
        logger.WithContext(ctx).WithError(err).Error("Failed to release DID")
    }
    
    // Update route current calls
    if err := r.decrementRouteCalls(ctx, tx, record.RouteName); err != nil {
        logger.WithContext(ctx).WithError(err).Warn("Failed to update route call count")
    }
    
    // Commit transaction
    if err := tx.Commit(); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to commit transaction")
    }
    
    // Update load balancer stats
    r.loadBalancer.UpdateCallComplete(record.IntermediateProvider, true, duration)
    r.loadBalancer.UpdateCallComplete(record.FinalProvider, true, duration)
    r.loadBalancer.DecrementActiveCalls(record.IntermediateProvider)
    r.loadBalancer.DecrementActiveCalls(record.FinalProvider)
    
    // Clean up memory
    r.mu.Lock()
    delete(r.activeCalls, callID)
    r.didManager.UnregisterCallDID(record.AssignedDID)
    r.mu.Unlock()
    
    // Update metrics
    r.updateMetricsForCompletedCall(record, duration)
    
    logger.WithContext(ctx).WithFields(map[string]interface{}{
        "call_id": callID,
        "duration": duration.Seconds(),
        "billable": record.BillableDuration,
    }).Info("Call completed successfully")
    
    return nil
}

func (r *Router) handleIncompleteCall(ctx context.Context, callID string, record *models.CallRecord) {
    // Determine final status
    status := models.CallStatusAbandoned
    if record.Status == models.CallStatusActive {
        status = models.CallStatusFailed
    }
    
    // Update call state
    r.mu.Lock()
    record.Status = status
    record.CurrentStep = "HANGUP"
    now := time.Now()
    record.EndTime = &now
    record.Duration = int(now.Sub(record.StartTime).Seconds())
    r.mu.Unlock()
    
    // Update in database
    tx, err := r.db.BeginTx(ctx, nil)
    if err == nil {
        r.updateCallRecord(ctx, tx, record)
        r.didManager.ReleaseDID(ctx, tx, record.AssignedDID)
        r.decrementRouteCalls(ctx, tx, record.RouteName)
        tx.Commit()
    }
    
    // Update stats
    r.loadBalancer.UpdateCallComplete(record.IntermediateProvider, false, 0)
    r.loadBalancer.UpdateCallComplete(record.FinalProvider, false, 0)
    r.loadBalancer.DecrementActiveCalls(record.IntermediateProvider)
    r.loadBalancer.DecrementActiveCalls(record.FinalProvider)
    
    // Clean up
    r.mu.Lock()
    delete(r.activeCalls, callID)
    r.didManager.UnregisterCallDID(record.AssignedDID)
    r.mu.Unlock()
    
    r.metrics.IncrementCounter("router_calls_failed", map[string]string{
        "route": record.RouteName,
        "reason": string(status),
    })
}

func (r *Router) updateMetricsForNewCall(routeName string) {
    r.metrics.IncrementCounter("router_calls_processed", map[string]string{
        "stage": "incoming",
        "route": routeName,
    })
    
    r.mu.RLock()
    activeCount := len(r.activeCalls)
    r.mu.RUnlock()
    
    r.metrics.SetGauge("router_active_calls", float64(activeCount), nil)
}

func (r *Router) updateMetricsForCompletedCall(record *models.CallRecord, duration time.Duration) {
    r.metrics.IncrementCounter("router_calls_completed", map[string]string{
        "route": record.RouteName,
        "intermediate": record.IntermediateProvider,
        "final": record.FinalProvider,
    })
    
    r.metrics.ObserveHistogram("router_call_duration", duration.Seconds(), map[string]string{
        "route": record.RouteName,
    })
    
    r.mu.RLock()
    activeCount := len(r.activeCalls)
    r.mu.RUnlock()
    
    r.metrics.SetGauge("router_active_calls", float64(activeCount), nil)
}

// Verification methods

func (r *Router) verifyReturnCall(ctx context.Context, record *models.CallRecord, ani2, did, provider, sourceIP string) error {
    verification := &models.CallVerification{
        CallID:           record.CallID,
        VerificationStep: "S3_TO_S2",
        ExpectedANI:      record.OriginalDNIS, // ANI-2 should be DNIS-1
        ExpectedDNIS:     did,
        ReceivedANI:      ani2,
        ReceivedDNIS:     did,
        SourceIP:         sourceIP,
    }
    
    // Verify ANI transformation
    if ani2 != record.OriginalDNIS {
        verification.Verified = false
        verification.FailureReason = fmt.Sprintf("ANI mismatch: expected %s, got %s", record.OriginalDNIS, ani2)
        r.storeVerification(ctx, verification)
        return errors.New(errors.ErrAuthFailed, "ANI verification failed").
            WithContext("expected", record.OriginalDNIS).
            WithContext("received", ani2)
    }
    
    // Verify provider
    if provider != record.IntermediateProvider {
        verification.Verified = false
        verification.FailureReason = fmt.Sprintf("Provider mismatch: expected %s, got %s", record.IntermediateProvider, provider)
        r.storeVerification(ctx, verification)
        return errors.New(errors.ErrAuthFailed, "Provider verification failed")
    }
    
    // Verify source IP if available
    if sourceIP != "" {
        if err := r.verifySourceIP(ctx, sourceIP, record.IntermediateProvider, verification); err != nil {
            return err
        }
    }
    
    verification.Verified = true
    r.storeVerification(ctx, verification)
    return nil
}

func (r *Router) verifyFinalCall(ctx context.Context, record *models.CallRecord, ani, dnis, provider, sourceIP string) error {
    verification := &models.CallVerification{
        CallID:           record.CallID,
        VerificationStep: "S4_TO_S2",
        ExpectedANI:      record.OriginalANI,
        ExpectedDNIS:     record.OriginalDNIS,
        ReceivedANI:      ani,
        ReceivedDNIS:     dnis,
        SourceIP:         sourceIP,
    }
    
    // Verify ANI/DNIS restoration
    if ani != record.OriginalANI || dnis != record.OriginalDNIS {
        verification.Verified = false
        verification.FailureReason = fmt.Sprintf("ANI/DNIS mismatch: expected %s/%s, got %s/%s",
            record.OriginalANI, record.OriginalDNIS, ani, dnis)
        r.storeVerification(ctx, verification)
        return errors.New(errors.ErrAuthFailed, "ANI/DNIS verification failed")
    }
    
    // Verify provider
    if provider != record.FinalProvider {
        verification.Verified = false
        verification.FailureReason = fmt.Sprintf("Provider mismatch: expected %s, got %s", record.FinalProvider, provider)
        r.storeVerification(ctx, verification)
        return errors.New(errors.ErrAuthFailed, "Provider verification failed")
    }
    
    // Verify source IP
    if sourceIP != "" {
        if err := r.verifySourceIP(ctx, sourceIP, record.FinalProvider, verification); err != nil {
            return err
        }
    }
    
    verification.Verified = true
    r.storeVerification(ctx, verification)
    return nil
}

func (r *Router) verifySourceIP(ctx context.Context, sourceIP, providerName string, verification *models.CallVerification) error {
    expectedIP, err := r.getProviderIP(ctx, providerName)
    if err == nil && expectedIP != "" {
        verification.ExpectedIP = expectedIP
        if !r.verifyIP(sourceIP, expectedIP) {
            verification.Verified = false
            verification.FailureReason = fmt.Sprintf("IP mismatch: expected %s, got %s", expectedIP, sourceIP)
            r.storeVerification(ctx, verification)
            return errors.New(errors.ErrInvalidIP, "IP verification failed")
        }
    }
    return nil
}

func (r *Router) storeVerification(ctx context.Context, verification *models.CallVerification) {
    query := `
        INSERT INTO call_verifications (
            call_id, verification_step, expected_ani, expected_dnis,
            received_ani, received_dnis, source_ip, expected_ip,
            verified, failure_reason
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    
    if _, err := r.db.ExecContext(ctx, query,
        verification.CallID, verification.VerificationStep,
        verification.ExpectedANI, verification.ExpectedDNIS,
        verification.ReceivedANI, verification.ReceivedDNIS,
        verification.SourceIP, verification.ExpectedIP,
        verification.Verified, verification.FailureReason,
    ); err != nil {
        logger.WithContext(ctx).WithError(err).Warn("Failed to store verification record")
    }
}

func (r *Router) getProviderIP(ctx context.Context, providerName string) (string, error) {
    var host string
    err := r.db.QueryRowContext(ctx,
        "SELECT host FROM providers WHERE name = ?",
        providerName).Scan(&host)
    
    if err != nil {
        return "", err
    }
    
    return host, nil
}

func (r *Router) verifyIP(sourceIP, expectedIP string) bool {
    // Extract IP without port
    if idx := strings.LastIndex(sourceIP, ":"); idx != -1 {
        sourceIP = sourceIP[:idx]
    }
    
    return sourceIP == expectedIP
}

// Cleanup methods

func (r *Router) cleanupRoutine() {
    ticker := time.NewTicker(r.config.CallCleanupInterval)
    defer ticker.Stop()
    
    for range ticker.C {
        ctx := context.Background()
        r.cleanupStaleCalls(ctx)
        r.didManager.CleanupStaleDIDs(ctx, r.config.StaleCallTimeout)
    }
}

func (r *Router) cleanupStaleCalls(ctx context.Context) {
    log := logger.WithContext(ctx)
    
    r.mu.Lock()
    defer r.mu.Unlock()
    
    now := time.Now()
    cleaned := 0
    
    for callID, record := range r.activeCalls {
        if now.Sub(record.StartTime) > r.config.StaleCallTimeout {
            log.WithField("call_id", callID).Warn("Cleaning up stale call")
            
            // Mark as timeout
            record.Status = models.CallStatusTimeout
            record.CurrentStep = "CLEANUP"
            record.EndTime = &now
            record.Duration = int(now.Sub(record.StartTime).Seconds())
            
            // Update in database
            tx, err := r.db.BeginTx(ctx, nil)
            if err == nil {
                r.updateCallRecord(ctx, tx, record)
                r.didManager.ReleaseDID(ctx, tx, record.AssignedDID)
                r.decrementRouteCalls(ctx, tx, record.RouteName)
                tx.Commit()
            }
            
            // Update stats
            r.loadBalancer.UpdateCallComplete(record.IntermediateProvider, false, 0)
            r.loadBalancer.UpdateCallComplete(record.FinalProvider, false, 0)
            r.loadBalancer.DecrementActiveCalls(record.IntermediateProvider)
            r.loadBalancer.DecrementActiveCalls(record.FinalProvider)
            
            // Remove from memory
            delete(r.activeCalls, callID)
            r.didManager.UnregisterCallDID(record.AssignedDID)
            
            cleaned++
        }
    }
    
    if cleaned > 0 {
        log.WithField("count", cleaned).Info("Cleaned up stale calls")
        r.metrics.IncrementCounter("router_calls_timeout", map[string]string{
            "count": fmt.Sprintf("%d", cleaned),
        })
    }
}

// Public API methods

// GetStatistics returns current router statistics
func (r *Router) GetStatistics(ctx context.Context) (map[string]interface{}, error) {
    r.mu.RLock()
    activeCalls := len(r.activeCalls)
    r.mu.RUnlock()
    
    stats := map[string]interface{}{
        "active_calls": activeCalls,
    }
    
    // Get DID statistics
    didStats, err := r.didManager.GetStatistics(ctx)
    if err != nil {
        logger.WithContext(ctx).WithError(err).Warn("Failed to get DID stats")
    } else {
        for k, v := range didStats {
            stats[k] = v
        }
    }
    
    // Get route statistics
    rows, err := r.db.QueryContext(ctx, `
        SELECT name, current_calls, max_concurrent_calls
        FROM provider_routes
        WHERE enabled = 1
    `)
    
    if err == nil {
        defer rows.Close()
        
        routes := make([]map[string]interface{}, 0)
        for rows.Next() {
            var name string
            var current, max int
            if err := rows.Scan(&name, &current, &max); err == nil {
                utilization := 0.0
                if max > 0 {
                    utilization = float64(current) / float64(max) * 100
                }
                routes = append(routes, map[string]interface{}{
                    "name":        name,
                    "current":     current,
                    "max":         max,
                    "utilization": utilization,
                })
            }
        }
        stats["routes"] = routes
    }
    
    return stats, nil
}

// GetActiveCall returns details of an active call
func (r *Router) GetActiveCall(ctx context.Context, callID string) (*models.CallRecord, error) {
    r.mu.RLock()
    defer r.mu.RUnlock()
    
    record, exists := r.activeCalls[callID]
    if !exists {
        return nil, errors.New(errors.ErrCallNotFound, "call not found")
    }
    
    return record, nil
}

// GetActiveCalls returns all active calls
func (r *Router) GetActiveCalls(ctx context.Context) ([]*models.CallRecord, error) {
    r.mu.RLock()
    defer r.mu.RUnlock()
    
    calls := make([]*models.CallRecord, 0, len(r.activeCalls))
    for _, record := range r.activeCalls {
        calls = append(calls, record)
    }
    
    return calls, nil
}

// GetLoadBalancer returns the load balancer instance
func (r *Router) GetLoadBalancer() *LoadBalancer {
    return r.loadBalancer
}

// GetDIDManager returns the DID manager instance
func (r *Router) GetDIDManager() *DIDManager {
    return r.didManager
}
package errors

import (
    "fmt"
    "runtime"
    "strings"
)

type ErrorCode string

const (
    // System errors
    ErrInternal         ErrorCode = "INTERNAL_ERROR"
    ErrDatabase         ErrorCode = "DATABASE_ERROR"
    ErrRedis            ErrorCode = "REDIS_ERROR"
    ErrConfiguration    ErrorCode = "CONFIG_ERROR"
    
    // Business logic errors
    ErrProviderNotFound ErrorCode = "PROVIDER_NOT_FOUND"
    ErrDIDNotAvailable  ErrorCode = "DID_NOT_AVAILABLE"
    ErrRouteNotFound    ErrorCode = "ROUTE_NOT_FOUND"
    ErrCallNotFound     ErrorCode = "CALL_NOT_FOUND"
    ErrInvalidIP        ErrorCode = "INVALID_IP"
    ErrAuthFailed       ErrorCode = "AUTH_FAILED"
    ErrQuotaExceeded    ErrorCode = "QUOTA_EXCEEDED"
    
    // AGI errors
    ErrAGITimeout       ErrorCode = "AGI_TIMEOUT"
    ErrAGIInvalidCmd    ErrorCode = "AGI_INVALID_COMMAND"
    ErrAGIConnection    ErrorCode = "AGI_CONNECTION_ERROR"
)

type AppError struct {
    Code       ErrorCode
    Message    string
    Err        error
    StatusCode int
    Context    map[string]interface{}
    Stack      string
}

func New(code ErrorCode, message string) *AppError {
    return &AppError{
        Code:       code,
        Message:    message,
        StatusCode: 500,
        Context:    make(map[string]interface{}),
        Stack:      getStack(),
    }
}

func Wrap(err error, code ErrorCode, message string) *AppError {
    if err == nil {
        return nil
    }
    
    // If already an AppError, enhance it
    if appErr, ok := err.(*AppError); ok {
        appErr.Message = fmt.Sprintf("%s: %s", message, appErr.Message)
        return appErr
    }
    
    return &AppError{
        Code:       code,
        Message:    message,
        Err:        err,
        StatusCode: 500,
        Context:    make(map[string]interface{}),
        Stack:      getStack(),
    }
}

func (e *AppError) Error() string {
    if e.Err != nil {
        return fmt.Sprintf("[%s] %s: %v", e.Code, e.Message, e.Err)
    }
    return fmt.Sprintf("[%s] %s", e.Code, e.Message)
}

func (e *AppError) Unwrap() error {
    return e.Err
}

func (e *AppError) WithContext(key string, value interface{}) *AppError {
    e.Context[key] = value
    return e
}

func (e *AppError) WithStatusCode(code int) *AppError {
    e.StatusCode = code
    return e
}

func (e *AppError) IsRetryable() bool {
    switch e.Code {
    case ErrDatabase, ErrRedis, ErrAGITimeout, ErrAGIConnection:
        return true
    default:
        return false
    }
}

func getStack() string {
    var pcs [32]uintptr
    n := runtime.Callers(3, pcs[:])
    
    var builder strings.Builder
    frames := runtime.CallersFrames(pcs[:n])
    
    for {
        frame, more := frames.Next()
        if !strings.Contains(frame.File, "runtime/") {
            builder.WriteString(fmt.Sprintf("%s:%d %s\n", frame.File, frame.Line, frame.Function))
        }
        if !more {
            break
        }
    }
    
    return builder.String()
}

// Error checking helpers
func Is(err error, code ErrorCode) bool {
    if err == nil {
        return false
    }
    
    appErr, ok := err.(*AppError)
    if !ok {
        return false
    }
    
    return appErr.Code == code
} 
// Add this function at the end of the file

// GetCode extracts the error code from an error
func GetCode(err error) string {
    if err == nil {
        return ""
    }
    
    if appErr, ok := err.(*AppError); ok {
        return string(appErr.Code)
    }
    
    return "UNKNOWN_ERROR"
}
package logger

import (
    "context"
    "fmt"
    "os"
    "time"
    
    "github.com/sirupsen/logrus"
    "gopkg.in/natefinch/lumberjack.v2"
)

type Logger struct {
    *logrus.Logger
    fields logrus.Fields
}

var (
    defaultLogger *Logger
)

type Config struct {
    Level      string
    Format     string
    Output     string
    File       FileConfig
    Fields     map[string]interface{}
}

type FileConfig struct {
    Enabled    bool
    Path       string
    MaxSize    int
    MaxBackups int
    MaxAge     int
    Compress   bool
}

func Init(cfg Config) error {
    log := logrus.New()
    
    // Set log level
    level, err := logrus.ParseLevel(cfg.Level)
    if err != nil {
        return fmt.Errorf("invalid log level: %w", err)
    }
    log.SetLevel(level)
    
    // Set formatter
    switch cfg.Format {
    case "json":
        log.SetFormatter(&logrus.JSONFormatter{
            TimestampFormat: time.RFC3339Nano,
            FieldMap: logrus.FieldMap{
                logrus.FieldKeyTime:  "@timestamp",
                logrus.FieldKeyLevel: "level",
                logrus.FieldKeyMsg:   "message",
            },
        })
    default:
        log.SetFormatter(&logrus.TextFormatter{
            FullTimestamp:   true,
            TimestampFormat: "2006-01-02 15:04:05.000",
        })
    }
    
    // Set output
    if cfg.File.Enabled {
        log.SetOutput(&lumberjack.Logger{
            Filename:   cfg.File.Path,
            MaxSize:    cfg.File.MaxSize,
            MaxBackups: cfg.File.MaxBackups,
            MaxAge:     cfg.File.MaxAge,
            Compress:   cfg.File.Compress,
        })
    } else {
        log.SetOutput(os.Stdout)
    }
    
    // Set default fields
    fields := logrus.Fields{
        "app":     "asterisk-ara-router",
        "version": "2.0.0",
        "pid":     os.Getpid(),
    }
    
    for k, v := range cfg.Fields {
        fields[k] = v
    }
    
    defaultLogger = &Logger{
        Logger: log,
        fields: fields,
    }
    
    return nil
}

func WithContext(ctx context.Context) *Logger {
    if defaultLogger == nil {
        panic("logger not initialized")
    }
    
    fields := logrus.Fields{}
    
    // Extract common fields from context
    if reqID := ctx.Value("request_id"); reqID != nil {
        fields["request_id"] = reqID
    }
    if callID := ctx.Value("call_id"); callID != nil {
        fields["call_id"] = callID
    }
    if userID := ctx.Value("user_id"); userID != nil {
        fields["user_id"] = userID
    }
    
    return defaultLogger.WithFields(fields)
}

func (l *Logger) WithFields(fields map[string]interface{}) *Logger {
    newFields := make(logrus.Fields)
    for k, v := range l.fields {
        newFields[k] = v
    }
    for k, v := range fields {
        newFields[k] = v
    }
    
    entry := l.Logger.WithFields(newFields)
    return &Logger{
        Logger: entry.Logger,
        fields: newFields,
    }
}

func (l *Logger) WithField(key string, value interface{}) *Logger {
    return l.WithFields(map[string]interface{}{key: value})
}

func (l *Logger) WithError(err error) *Logger {
    return l.WithFields(map[string]interface{}{
        "error":      err.Error(),
        "error_type": fmt.Sprintf("%T", err),
    })
}

// Log methods that use the logger fields
func (l *Logger) Debug(args ...interface{}) {
    l.Logger.WithFields(l.fields).Debug(args...)
}

func (l *Logger) Info(args ...interface{}) {
    l.Logger.WithFields(l.fields).Info(args...)
}

func (l *Logger) Warn(args ...interface{}) {
    l.Logger.WithFields(l.fields).Warn(args...)
}

func (l *Logger) Error(args ...interface{}) {
    l.Logger.WithFields(l.fields).Error(args...)
}

func (l *Logger) Fatal(args ...interface{}) {
    l.Logger.WithFields(l.fields).Fatal(args...)
}

// Convenience functions
func Debug(args ...interface{}) {
    if defaultLogger != nil {
        defaultLogger.WithFields(defaultLogger.fields).Debug(args...)
    }
}

func Info(args ...interface{}) {
    if defaultLogger != nil {
        defaultLogger.WithFields(defaultLogger.fields).Info(args...)
    }
}

func Warn(args ...interface{}) {
    if defaultLogger != nil {
        defaultLogger.WithFields(defaultLogger.fields).Warn(args...)
    }
}

func Error(args ...interface{}) {
    if defaultLogger != nil {
        defaultLogger.WithFields(defaultLogger.fields).Error(args...)
    }
}

func Fatal(args ...interface{}) {
    if defaultLogger != nil {
        defaultLogger.WithFields(defaultLogger.fields).Fatal(args...)
    }
}

func WithField(key string, value interface{}) *Logger {
    if defaultLogger != nil {
        return defaultLogger.WithField(key, value)
    }
    return &Logger{Logger: logrus.New(), fields: make(logrus.Fields)}
}

func WithError(err error) *Logger {
    if defaultLogger != nil {
        return defaultLogger.WithError(err)
    }
    return &Logger{Logger: logrus.New(), fields: make(logrus.Fields)}
}
.
├── add_provider_groups.sql
├── asterisk_ara_backup_20250605_171456.sql
├── backup_20250605_172231.sql
├── backup_asterisk_ara_20250605_185151.sql
├── backup_asterisk_ara_20250605_185324.sql
├── backup_asterisk_ara_20250605_185559.sql
├── backup_asterisk_ara_20250605_185604.sql
├── bin
│   └── router
├── cmd
│   └── router
│       ├── commands.go
│       ├── config.go
│       ├── group_commands.go
│       └── main.go
├── configs
│   └── production.yaml
├── d
├── docker-compose.yml
├── Dockerfile
├── docs
├── fix_schema.sql
├── fix.sql
├── go.mod
├── go.sum
├── i
├── internal
│   ├── agi
│   │   └── server.go
│   ├── ami
│   │   └── manager.go
│   ├── ara
│   │   └── manager.go
│   ├── config
│   │   └── config.go
│   ├── db
│   │   ├── cache.go
│   │   ├── connection.go
│   │   ├── initializer.go
│   │   ├── migrate.go
│   │   └── migrations
│   │       └── 001_initial_schema.up.sql
│   ├── health
│   │   └── health.go
│   ├── metrics
│   │   └── prometheus.go
│   ├── models
│   │   ├── groups.go
│   │   └── models.go
│   ├── provider
│   │   ├── group_service.go
│   │   └── service.go
│   └── router
│       ├── did_manager.go
│       ├── loadbalancer.go
│       └── router.go
├── ma
├── Makefile
├── migrations
│   └── 001_initial_schema.up.sql
├── pkg
│   ├── errors
│   │   └── errors.go
│   ├── logger
│   │   └── logger.go
│   └── utils
├── README.md
├── scripts
├── setup_database.sh
├── setup_db.sql
├── t
├── test_ami.go
└── tests

25 directories, 49 files
