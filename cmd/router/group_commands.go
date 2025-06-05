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
