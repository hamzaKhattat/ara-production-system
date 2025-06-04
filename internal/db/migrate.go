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
