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
   "github.com/fatih/color"
   "github.com/olekukonko/tablewriter"
   "github.com/spf13/cobra"
   "github.com/hamzaKhattat/ara-production-system/internal/models"
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
               Name:         args[0],
               Type:         models.ProviderType(providerType),
               Host:         host,
               Port:         port,
               Username:     username,
               Password:     password,
               AuthType:     authType,
               Codecs:       codecs,
               MaxChannels:  maxChannels,
               Priority:     priority,
               Weight:       weight,
               Active:       true,
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
           
           providers, err:= providerSvc.ListProviders(ctx, filter)
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
   )
   
   cmd := &cobra.Command{
       Use:   "add <name> <inbound> <intermediate> <final>",
       Short: "Add a new route",
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
           
           if err := createRoute(ctx, route); err != nil {
               return fmt.Errorf("failed to create route: %v", err)
           }
           
           fmt.Printf("%s Route '%s' created successfully\n", green("✓"), args[0])
           return nil
       },
   }
   
   cmd.Flags().StringVar(&mode, "mode", "round_robin", "Load balance mode")
   cmd.Flags().IntVar(&priority, "priority", 10, "Route priority")
   cmd.Flags().IntVar(&weight, "weight", 1, "Route weight")
   cmd.Flags().IntVar(&maxCalls, "max-calls", 0, "Maximum concurrent calls")
   cmd.Flags().StringVarP(&description, "description", "d", "", "Route description")
   
   return cmd
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
               
               table.Append([]string{
                   r.Name,
                   r.InboundProvider,
                   r.IntermediateProvider,
                   r.FinalProvider,
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
           fmt.Printf("Inbound Provider:   %s\n", route.InboundProvider)
           fmt.Printf("Intermediate:       %s\n", route.IntermediateProvider)
           fmt.Printf("Final Provider:     %s\n", route.FinalProvider)
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
                   
               case <-
cmd.Context().Done():
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
           final_provider, load_balance_mode, priority, weight,
           max_concurrent_calls, enabled
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
   
   _, err := database.ExecContext(ctx, query,
       route.Name, route.Description, route.InboundProvider,
       route.IntermediateProvider, route.FinalProvider,
       route.LoadBalanceMode, route.Priority, route.Weight,
       route.MaxConcurrentCalls, route.Enabled)
   
   return err
}

func listRoutes(ctx context.Context) ([]*models.ProviderRoute, error) {
   query := `
       SELECT id, name, description, inbound_provider, intermediate_provider,
              final_provider, load_balance_mode, priority, weight,
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
       var description sql.NullString
       
       err := rows.Scan(
           &route.ID, &route.Name, &description,
           &route.InboundProvider, &route.IntermediateProvider,
           &route.FinalProvider, &route.LoadBalanceMode,
           &route.Priority, &route.Weight,
           &route.MaxConcurrentCalls, &route.CurrentCalls,
           &route.Enabled, &route.CreatedAt, &route.UpdatedAt,
       )
       
       if err != nil {
           continue
       }
       
       if description.Valid {
           route.Description = description.String
       }
       
       routes = append(routes, &route)
   }
   
   return routes, nil
}

func getRoute(ctx context.Context, name string) (*models.ProviderRoute, error) {
   var route models.ProviderRoute
   var description sql.NullString
   
   query := `
       SELECT id, name, description, inbound_provider, intermediate_provider,
              final_provider, load_balance_mode, priority, weight,
              max_concurrent_calls, current_calls, enabled,
              failover_routes, routing_rules, metadata,
              created_at, updated_at
       FROM provider_routes
       WHERE name = ?`
   
   err := database.QueryRowContext(ctx, query, name).Scan(
       &route.ID, &route.Name, &description,
       &route.InboundProvider, &route.IntermediateProvider,
       &route.FinalProvider, &route.LoadBalanceMode,
       &route.Priority, &route.Weight,
       &route.MaxConcurrentCalls, &route.CurrentCalls,
       &route.Enabled, &route.FailoverRoutes,
       &route.RoutingRules, &route.Metadata,
       &route.CreatedAt, &route.UpdatedAt,
   )
   
   if err != nil {
       return nil, err
   }
   
   if description.Valid {
       route.Description = description.String
   }
   
   return &route, nil
}

func deleteRoute(ctx context.Context, name string) error {
   _, err := database.ExecContext(ctx, "DELETE FROM provider_routes WHERE name = ?", name)
   return err
}

func getActiveCalls(ctx context.Context) ([]*models.CallRecord, error) {
   query := `
       SELECT call_id, original_ani, original_dnis, transformed_ani,
              assigned_did, inbound_provider, intermediate_provider,
              final_provider, route_name, status, current_step,
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
       var transformedANI, assignedDID, routeName, currentStep sql.NullString
       
       err := rows.Scan(
           &call.CallID, &call.OriginalANI, &call.OriginalDNIS,
           &transformedANI, &assignedDID,
           &call.InboundProvider, &call.IntermediateProvider,
           &call.FinalProvider, &routeName,
           &call.Status, &currentStep,
           &call.StartTime, &call.AnswerTime,
       )
       
       if err != nil {
           continue
       }
       
       if transformedANI.Valid {
           call.TransformedANI = transformedANI.String
       }
       if assignedDID.Valid {
           call.AssignedDID = assignedDID.String
       }
       if routeName.Valid {
           call.RouteName = routeName.String
       }
       if currentStep.Valid {
           call.CurrentStep = currentStep.String
       }
       
       calls = append(calls, &call)
   }
   
   return calls, nil
}
