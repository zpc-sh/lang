// native/lang_parser/src/performance.rs - Performance monitoring and optimization

use std::time::{Duration, Instant};
use std::collections::HashMap;
use serde::{Serialize, Deserialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceMetrics {
    pub parse_time_ms: u64,
    pub memory_usage_bytes: usize,
    pub cpu_usage_percent: f32,
    pub throughput_chars_per_ms: f64,
    pub cache_hit_rate: f32,
    pub operations: HashMap<String, OperationMetrics>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OperationMetrics {
    pub name: String,
    pub duration_ms: u64,
    pub memory_delta_bytes: i64,
    pub call_count: u32,
    pub error_count: u32,
}

pub struct PerformanceMonitor {
    start_time: Instant,
    operations: HashMap<String, Vec<OperationMetrics>>,
    memory_baseline: usize,
}

impl PerformanceMonitor {
    pub fn new() -> Self {
        Self {
            start_time: Instant::now(),
            operations: HashMap::new(),
            memory_baseline: get_memory_usage(),
        }
    }

    pub fn start_operation(&mut self, name: &str) -> OperationTimer {
        OperationTimer::new(name.to_string())
    }

    pub fn record_operation(&mut self, metrics: OperationMetrics) {
        self.operations
            .entry(metrics.name.clone())
            .or_insert_with(Vec::new)
            .push(metrics);
    }

    pub fn get_metrics(&self, content_size: usize) -> PerformanceMetrics {
        let elapsed = self.start_time.elapsed();
        let current_memory = get_memory_usage();
        
        let total_operations: u32 = self.operations
            .values()
            .map(|ops| ops.len() as u32)
            .sum();

        let total_errors: u32 = self.operations
            .values()
            .flat_map(|ops| ops.iter())
            .map(|op| op.error_count)
            .sum();

        let throughput = if elapsed.as_millis() > 0 {
            content_size as f64 / elapsed.as_millis() as f64
        } else {
            0.0
        };

        let cache_hit_rate = calculate_cache_hit_rate(&self.operations);

        let aggregated_operations = self.operations
            .iter()
            .map(|(name, ops)| {
                let total_duration: u64 = ops.iter().map(|op| op.duration_ms).sum();
                let total_memory_delta: i64 = ops.iter().map(|op| op.memory_delta_bytes).sum();
                let total_calls = ops.len() as u32;
                let total_op_errors: u32 = ops.iter().map(|op| op.error_count).sum();

                (
                    name.clone(),
                    OperationMetrics {
                        name: name.clone(),
                        duration_ms: total_duration,
                        memory_delta_bytes: total_memory_delta,
                        call_count: total_calls,
                        error_count: total_op_errors,
                    },
                )
            })
            .collect();

        PerformanceMetrics {
            parse_time_ms: elapsed.as_millis() as u64,
            memory_usage_bytes: current_memory,
            cpu_usage_percent: get_cpu_usage(),
            throughput_chars_per_ms: throughput,
            cache_hit_rate,
            operations: aggregated_operations,
        }
    }

    pub fn reset(&mut self) {
        self.start_time = Instant::now();
        self.operations.clear();
        self.memory_baseline = get_memory_usage();
    }
}

pub struct OperationTimer {
    name: String,
    start_time: Instant,
    memory_start: usize,
    error_count: u32,
}

impl OperationTimer {
    pub fn new(name: String) -> Self {
        Self {
            name,
            start_time: Instant::now(),
            memory_start: get_memory_usage(),
            error_count: 0,
        }
    }

    pub fn record_error(&mut self) {
        self.error_count += 1;
    }

    pub fn finish(self) -> OperationMetrics {
        let duration = self.start_time.elapsed();
        let memory_end = get_memory_usage();
        
        OperationMetrics {
            name: self.name,
            duration_ms: duration.as_millis() as u64,
            memory_delta_bytes: memory_end as i64 - self.memory_start as i64,
            call_count: 1,
            error_count: self.error_count,
        }
    }
}

// Platform-specific memory usage functions
#[cfg(target_os = "macos")]
fn get_memory_usage() -> usize {
    // Simplified memory usage for macOS - in a real implementation,
    // you would use system APIs like mach_task_basic_info
    use std::process;
    let pid = process::id();
    
    // This is a placeholder - real implementation would use system calls
    // For now, return a dummy value
    0
}

#[cfg(target_os = "linux")]
fn get_memory_usage() -> usize {
    // Read from /proc/self/status on Linux
    if let Ok(status) = std::fs::read_to_string("/proc/self/status") {
        for line in status.lines() {
            if line.starts_with("VmRSS:") {
                if let Some(kb_str) = line.split_whitespace().nth(1) {
                    if let Ok(kb) = kb_str.parse::<usize>() {
                        return kb * 1024; // Convert KB to bytes
                    }
                }
            }
        }
    }
    0
}

#[cfg(target_os = "windows")]
fn get_memory_usage() -> usize {
    // Windows implementation would use GetProcessMemoryInfo
    // Placeholder for now
    0
}

#[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
fn get_memory_usage() -> usize {
    // Fallback for other platforms
    0
}

fn get_cpu_usage() -> f32 {
    // Simplified CPU usage calculation
    // In a real implementation, this would track CPU time over intervals
    0.0
}

fn calculate_cache_hit_rate(operations: &HashMap<String, Vec<OperationMetrics>>) -> f32 {
    // Calculate cache hit rate based on operation patterns
    // This is a simplified implementation
    let total_ops: usize = operations.values().map(|ops| ops.len()).sum();
    if total_ops == 0 {
        return 0.0;
    }

    // Assume operations with very short durations are cache hits
    let fast_ops: usize = operations
        .values()
        .flat_map(|ops| ops.iter())
        .filter(|op| op.duration_ms < 10) // Less than 10ms considered a cache hit
        .count();

    fast_ops as f32 / total_ops as f32
}

pub fn optimize_for_size(content_size: usize) -> OptimizationHints {
    OptimizationHints {
        use_streaming: content_size > 1_000_000, // > 1MB
        buffer_size: calculate_optimal_buffer_size(content_size),
        parallel_processing: content_size > 100_000, // > 100KB
        cache_results: content_size < 10_000_000, // < 10MB
        compression_threshold: content_size > 50_000, // > 50KB
    }
}

#[derive(Debug, Clone)]
pub struct OptimizationHints {
    pub use_streaming: bool,
    pub buffer_size: usize,
    pub parallel_processing: bool,
    pub cache_results: bool,
    pub compression_threshold: bool,
}

fn calculate_optimal_buffer_size(content_size: usize) -> usize {
    match content_size {
        0..=1_000 => 512,           // 512 bytes for small content
        1_001..=10_000 => 2_048,    // 2KB for medium content
        10_001..=100_000 => 8_192,  // 8KB for large content
        100_001..=1_000_000 => 32_768, // 32KB for very large content
        _ => 65_536,                // 64KB for huge content
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_performance_monitor_creation() {
        let monitor = PerformanceMonitor::new();
        let metrics = monitor.get_metrics(1000);
        
        assert_eq!(metrics.operations.len(), 0);
        assert!(metrics.parse_time_ms >= 0);
    }

    #[test]
    fn test_operation_timer() {
        let timer = OperationTimer::new("test_operation".to_string());
        std::thread::sleep(Duration::from_millis(1));
        let metrics = timer.finish();
        
        assert_eq!(metrics.name, "test_operation");
        assert!(metrics.duration_ms >= 1);
        assert_eq!(metrics.call_count, 1);
    }

    #[test]
    fn test_optimization_hints() {
        let small_hints = optimize_for_size(500);
        assert!(!small_hints.use_streaming);
        assert!(!small_hints.parallel_processing);
        
        let large_hints = optimize_for_size(2_000_000);
        assert!(large_hints.use_streaming);
        assert!(large_hints.parallel_processing);
    }

    #[test]
    fn test_buffer_size_calculation() {
        assert_eq!(calculate_optimal_buffer_size(500), 512);
        assert_eq!(calculate_optimal_buffer_size(5_000), 2_048);
        assert_eq!(calculate_optimal_buffer_size(50_000), 8_192);
        assert_eq!(calculate_optimal_buffer_size(500_000), 32_768);
        assert_eq!(calculate_optimal_buffer_size(5_000_000), 65_536);
    }
}