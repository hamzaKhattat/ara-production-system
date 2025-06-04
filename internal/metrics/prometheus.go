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
