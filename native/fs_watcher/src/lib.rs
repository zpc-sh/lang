// native/fs_watcher/src/lib.rs - Critical filesystem watching implementation

#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

use rustler::{Atom, Env, NifResult, Term, ResourceArc};
use notify::{Watcher, RecursiveMode, Result as NotifyResult, Event, EventKind};
use std::sync::{Arc, RwLock, Mutex};
use std::collections::HashMap;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use std::path::{Path, PathBuf};
use crossbeam_channel::{Receiver, Sender, unbounded};
use dashmap::DashMap;
use globset::{Glob, GlobMatcher};
use walkdir::WalkDir;
use rayon::prelude::*;
use serde::{Serialize, Deserialize};
use once_cell::sync::Lazy;
use ahash::AHashMap;

// ============================================================================
// RUSTLER MODULE INITIALIZATION
// ============================================================================

rustler::init!(
    "Elixir.Lang.Native.FsWatcher",
    [
        create_fs_watcher,
        destroy_watcher,
        add_watch_path,
        remove_watch_path,
        set_architectural_rules,
        get_events,
        get_statistics,
        coalesce_events,
        batch_validate_rules,
        scan_directory_tree,
        get_file_metadata_batch,
        setup_real_time_monitoring,
        check_architecture_violations
    ],
    load = on_load
);

fn on_load(env: Env, _info: Term) -> bool {
    rustler::resource!(FsWatcherResource, env);
    true
}

// Atoms for Elixir communication
rustler::atoms! {
    ok,
    error,
    created,
    modified,
    deleted,
    renamed,
    moved,
    rule_violation,
    permission_denied,
    not_found,
    invalid_path,
    watcher_not_found
}

// Global caches and registries
static WATCHER_REGISTRY: Lazy<DashMap<String, Arc<FsWatcherResource>>> = Lazy::new(DashMap::new);
static GLOB_CACHE: Lazy<DashMap<String, GlobMatcher>> = Lazy::new(DashMap::new);

// ============================================================================
// CRITICAL: EVENT COALESCING FOR HIGH-FREQUENCY CHANGES
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
struct CoalescedEvent {
    path: String,
    kind: String,
    timestamp: u64,
    metadata: Option<FileMetadata>,
    rule_violations: Vec<ArchViolation>,
}

#[derive(Debug, Clone, Copy)]
enum FsEventKind {
    Created,
    Modified,
    Deleted,
    Renamed { from_hash: u64 },
    MetadataChanged,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct FileMetadata {
    size: u64,
    modified: u64,
    file_type: String,
    permissions: u32,
    content_hash: Option<u64>,
}

// PERFORMANCE CRITICAL: Event coalescer prevents spam from rapid file changes
struct EventCoalescer {
    pending_events: DashMap<PathBuf, CoalescedEvent>,
    coalesce_duration: Duration,
    last_flush: Mutex<Instant>,
    batch_sender: Sender<Vec<CoalescedEvent>>,
}

impl EventCoalescer {
    fn new(coalesce_ms: u64, sender: Sender<Vec<CoalescedEvent>>) -> Self {
        Self {
            pending_events: DashMap::new(),
            coalesce_duration: Duration::from_millis(coalesce_ms),
            last_flush: Mutex::new(Instant::now()),
            batch_sender: sender,
        }
    }
    
    // CRITICAL: This processes every filesystem event
    fn add_event(&self, path: PathBuf, kind: FsEventKind, metadata: Option<FileMetadata>) {
        let now = Instant::now();
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_micros() as u64;
        
        let event = CoalescedEvent {
            path: path.to_string_lossy().to_string(),
            kind: self.kind_to_string(&kind),
            timestamp,
            metadata,
            rule_violations: Vec::new(),
        };
        
        // IMPORTANT: Coalesce rapid changes to same path
        match self.pending_events.entry(path.clone()) {
            dashmap::mapref::entry::Entry::Occupied(mut entry) => {
                let existing = entry.get();
                
                // OPTIMIZATION: Merge compatible events
                if self.can_merge_events(&existing.kind, &event.kind) {
                    entry.insert(event);
                } else {
                    // Conflicting events - flush existing and add new
                    let old_event = entry.insert(event);
                    self.send_immediate(old_event);
                }
            }
            dashmap::mapref::entry::Entry::Vacant(entry) => {
                entry.insert(event);
            }
        }
        
        // CRITICAL: Flush events periodically to prevent unbounded accumulation
        if let Ok(mut last_flush) = self.last_flush.try_lock() {
            if now.duration_since(*last_flush) > self.coalesce_duration {
                self.flush_events();
                *last_flush = now;
            }
        }
    }
    
    fn kind_to_string(&self, kind: &FsEventKind) -> String {
        match kind {
            FsEventKind::Created => "created".to_string(),
            FsEventKind::Modified => "modified".to_string(),
            FsEventKind::Deleted => "deleted".to_string(),
            FsEventKind::Renamed { .. } => "renamed".to_string(),
            FsEventKind::MetadataChanged => "metadata_changed".to_string(),
        }
    }
    
    fn can_merge_events(&self, existing: &str, new: &str) -> bool {
        match (existing, new) {
            ("modified", "modified") => true,
            ("metadata_changed", "metadata_changed") => true,
            ("created", "modified") => true,
            ("modified", "metadata_changed") => true,
            _ => false,
        }
    }
    
    fn send_immediate(&self, event: CoalescedEvent) {
        if let Err(_) = self.batch_sender.try_send(vec![event]) {
            eprintln!("Warning: Filesystem event channel full, dropping immediate event");
        }
    }
    
    fn flush_events(&self) {
        let mut events = Vec::new();
        
        // PERFORMANCE: Drain all pending events at once
        self.pending_events.retain(|_path, event| {
            events.push(event.clone());
            false // Remove from map
        });
        
        if !events.is_empty() {
            // IMPORTANT: Sort by timestamp for deterministic processing
            events.sort_by_key(|e| e.timestamp);
            
            if let Err(_) = self.batch_sender.try_send(events) {
                eprintln!("Warning: Filesystem event channel full, dropping events");
            }
        }
    }
    
    fn flush_expired_events(&self) -> Vec<CoalescedEvent> {
        let now = Instant::now();
        let mut expired_events = Vec::new();
        
        self.pending_events.retain(|_, event| {
            let event_time = UNIX_EPOCH + Duration::from_micros(event.timestamp);
            if let Ok(event_instant) = event_time.duration_since(UNIX_EPOCH) {
                let event_instant = Instant::now() - (SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default() - event_instant);
                if now.duration_since(event_instant) >= self.coalesce_duration {
                    expired_events.push(event.clone());
                    false // Remove from pending
                } else {
                    true // Keep in pending
                }
            } else {
                false // Remove invalid timestamps
            }
        });
        
        expired_events.sort_by_key(|e| e.timestamp);
        expired_events
    }
}

// ============================================================================
// CRITICAL: CROSS-PLATFORM FILESYSTEM WATCHER
// ============================================================================

#[derive(Clone)]
struct FsWatcherResource {
    id: String,
    watcher: Arc<Mutex<Option<notify::RecommendedWatcher>>>,
    event_receiver: Receiver<Vec<CoalescedEvent>>,
    coalescer: Arc<EventCoalescer>,
    watched_paths: Arc<RwLock<HashMap<PathBuf, WatchConfig>>>,
    statistics: Arc<RwLock<WatcherStatistics>>,
    architectural_rules: Arc<RwLock<Vec<ArchRule>>>,
}





#[derive(Debug, Clone)]
struct WatchConfig {
    recursive: bool,
    ignore_patterns: Vec<String>,
    include_content_hash: bool,
}

#[derive(Debug, Clone)]
struct ArchRule {
    id: String,
    pattern: String,
    rule_type: ArchRuleType,
    severity: Severity,
    message: String,
}

#[derive(Debug, Clone, Copy)]
enum ArchRuleType {
    ForbiddenPath,
    RequiredStructure,
    NamingConvention,
    LayerViolation,
}

#[derive(Debug, Clone, Copy)]
enum Severity {
    Error,
    Warning,
    Info,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ArchViolation {
    rule_id: String,
    path: String,
    rule_type: String,
    severity: String,
    message: String,
    suggested_fix: Option<String>,
}

#[derive(Debug, Clone)]
struct WatcherStatistics {
    total_events: u64,
    events_by_type: std::collections::HashMap<String, u64>,
    rule_violations: u64,
    files_processed: u64,
    directories_watched: u64,
    average_processing_time_us: f64,
    peak_memory_usage_mb: f64,
    start_time: Instant,
}

impl Default for WatcherStatistics {
    fn default() -> Self {
        Self {
            total_events: 0,
            events_by_type: std::collections::HashMap::new(),
            rule_violations: 0,
            files_processed: 0,
            directories_watched: 0,
            average_processing_time_us: 0.0,
            peak_memory_usage_mb: 0.0,
            start_time: Instant::now(),
        }
    }
}

// ============================================================================
// MAIN NIF FUNCTIONS
// ============================================================================

#[rustler::nif]
fn create_fs_watcher(
    id: String,
    recursive: bool,
    patterns: Vec<String>,
    enable_rules: bool,
) -> NifResult<ResourceArc<FsWatcherResource>> {
    let (event_sender, event_receiver) = unbounded();
    let coalescer = Arc::new(EventCoalescer::new(100, event_sender.clone()));
    
    let config = WatchConfig {
        recursive,
        ignore_patterns: patterns,
        include_content_hash: true,
    };
    
    let coalescer_clone = coalescer.clone();
    let statistics = Arc::new(RwLock::new(WatcherStatistics {
        start_time: Instant::now(),
        ..Default::default()
    }));
    let stats_clone = statistics.clone();
    
    let watcher = notify::recommended_watcher(move |res: NotifyResult<Event>| {
        match res {
            Ok(event) => {
                let mut stats = stats_clone.write().unwrap();
                stats.total_events += 1;
                
                for path in event.paths {
                    let kind = match event.kind {
                        EventKind::Create(_) => FsEventKind::Created,
                        EventKind::Modify(_) => FsEventKind::Modified,
                        EventKind::Remove(_) => FsEventKind::Deleted,
                        _ => continue,
                    };
                    
                    *stats.events_by_type.entry(format!("{:?}", kind)).or_insert(0) += 1;
                    
                    let metadata = gather_file_metadata(&path);
                    coalescer_clone.add_event(path, kind, metadata);
                }
            }
            Err(e) => {
                eprintln!("Filesystem watch error: {:?}", e);
            }
        }
    }).map_err(|_| rustler::Error::BadArg)?;
    
    let resource = FsWatcherResource {
        id: id.clone(),
        watcher: Arc::new(Mutex::new(Some(watcher))),
        event_receiver,
        coalescer,
        watched_paths: Arc::new(RwLock::new(HashMap::new())),
        statistics,
        architectural_rules: Arc::new(RwLock::new(Vec::new())),
    };
    
    let resource_arc = ResourceArc::new(resource);
    WATCHER_REGISTRY.insert(id, Arc::new((*resource_arc).clone()));
    
    Ok(resource_arc)
}

#[rustler::nif]
fn destroy_watcher(watcher: ResourceArc<FsWatcherResource>) -> NifResult<Atom> {
    WATCHER_REGISTRY.remove(&watcher.id);
    Ok(ok())
}

#[rustler::nif]
fn add_watch_path(watcher: ResourceArc<FsWatcherResource>, path: String) -> NifResult<Atom> {
    let path_buf = PathBuf::from(&path);
    
    if let Ok(mut watcher_guard) = watcher.watcher.try_lock() {
        if let Some(ref mut w) = *watcher_guard {
            let mode = RecursiveMode::Recursive;
            match w.watch(&path_buf, mode) {
                Ok(_) => {
                    let config = WatchConfig {
                        recursive: true,
                        ignore_patterns: vec![
                            "**/.git/**".to_string(),
                            "**/node_modules/**".to_string(),
                            "**/target/**".to_string(),
                            "**/.next/**".to_string(),
                        ],
                        include_content_hash: true,
                    };
                    
                    watcher.watched_paths.write().unwrap().insert(path_buf, config);
                    
                    // Update statistics
                    watcher.statistics.write().unwrap().directories_watched += 1;
                    
                    Ok(ok())
                }
                Err(_) => Ok(error()),
            }
        } else {
            Ok(error())
        }
    } else {
        Ok(error())
    }
}

#[rustler::nif]
fn remove_watch_path(watcher: ResourceArc<FsWatcherResource>, path: String) -> NifResult<Atom> {
    let path_buf = PathBuf::from(&path);
    
    if let Ok(mut watcher_guard) = watcher.watcher.try_lock() {
        if let Some(ref mut w) = *watcher_guard {
            match w.unwatch(&path_buf) {
                Ok(_) => {
                    watcher.watched_paths.write().unwrap().remove(&path_buf);
                    watcher.statistics.write().unwrap().directories_watched = 
                        watcher.statistics.read().unwrap().directories_watched.saturating_sub(1);
                    Ok(ok())
                }
                Err(_) => Ok(error()),
            }
        } else {
            Ok(error())
        }
    } else {
        Ok(error())
    }
}

#[rustler::nif]
fn set_architectural_rules(rules_json: String) -> NifResult<Atom> {
    #[derive(Deserialize)]
    struct RuleSpec {
        id: String,
        pattern: String,
        rule_type: String,
        severity: String,
        message: String,
    }
    
    match serde_json::from_str::<Vec<RuleSpec>>(&rules_json) {
        Ok(rule_specs) => {
            let rules: Vec<ArchRule> = rule_specs
                .into_iter()
                .map(|spec| ArchRule {
                    id: spec.id,
                    pattern: spec.pattern,
                    rule_type: match spec.rule_type.as_str() {
                        "forbidden_path" => ArchRuleType::ForbiddenPath,
                        "required_structure" => ArchRuleType::RequiredStructure,
                        "naming_convention" => ArchRuleType::NamingConvention,
                        "layer_violation" => ArchRuleType::LayerViolation,
                        _ => ArchRuleType::ForbiddenPath,
                    },
                    severity: match spec.severity.as_str() {
                        "error" => Severity::Error,
                        "warning" => Severity::Warning,
                        "info" => Severity::Info,
                        _ => Severity::Warning,
                    },
                    message: spec.message,
                })
                .collect();
            
            // Store rules globally - in real implementation, associate with specific watchers
            GLOBAL_RULES.write().unwrap().extend(rules);
            Ok(ok())
        }
        Err(_) => Ok(error()),
    }
}

static GLOBAL_RULES: Lazy<Arc<RwLock<Vec<ArchRule>>>> = Lazy::new(|| Arc::new(RwLock::new(Vec::new())));

#[rustler::nif]
fn get_events(watcher: ResourceArc<FsWatcherResource>, max_events: u32) -> NifResult<Vec<String>> {
    let mut events = Vec::new();
    let mut count = 0;
    
    // Get events from receiver
    while count < max_events {
        match watcher.event_receiver.try_recv() {
            Ok(event_batch) => {
                for event in event_batch {
                    if count >= max_events {
                        break;
                    }
                    
                    // Check architectural rules
                    let mut event_with_violations = event;
                    event_with_violations.rule_violations = check_event_against_rules(&event_with_violations);
                    
                    if let Ok(json) = serde_json::to_string(&event_with_violations) {
                        events.push(json);
                    }
                    count += 1;
                }
            }
            Err(_) => break,
        }
    }
    
    // Also get expired coalesced events
    let expired_events = watcher.coalescer.flush_expired_events();
    for event in expired_events {
        if events.len() >= max_events as usize {
            break;
        }
        
        let mut event_with_violations = event;
        event_with_violations.rule_violations = check_event_against_rules(&event_with_violations);
        
        if let Ok(json) = serde_json::to_string(&event_with_violations) {
            events.push(json);
        }
    }
    
    Ok(events)
}

#[rustler::nif]
fn get_statistics(watcher: ResourceArc<FsWatcherResource>) -> NifResult<String> {
    let stats = watcher.statistics.read().unwrap();
    let uptime_seconds = stats.start_time.elapsed().as_secs();
    
    let stats_map = serde_json::json!({
        "total_events": stats.total_events,
        "events_by_type": stats.events_by_type,
        "rule_violations": stats.rule_violations,
        "files_processed": stats.files_processed,
        "directories_watched": stats.directories_watched,
        "average_processing_time_us": stats.average_processing_time_us,
        "peak_memory_usage_mb": stats.peak_memory_usage_mb,
        "uptime_seconds": uptime_seconds
    });
    
    match serde_json::to_string(&stats_map) {
        Ok(json) => Ok(json),
        Err(_) => Err(rustler::Error::Term(Box::new("Failed to serialize statistics"))),
    }
}

#[rustler::nif]
fn coalesce_events(events_json: Vec<String>, window_ms: u64) -> NifResult<Vec<String>> {
    let mut events: Vec<CoalescedEvent> = Vec::new();
    
    for event_json in events_json {
        if let Ok(event) = serde_json::from_str::<CoalescedEvent>(&event_json) {
            events.push(event);
        }
    }
    
    // Group by path and coalesce within time window
    let mut coalesced_map: AHashMap<String, CoalescedEvent> = AHashMap::new();
    
    for event in events {
        let key = event.path.clone();
        match coalesced_map.get_mut(&key) {
            Some(existing) => {
                if event.timestamp.saturating_sub(existing.timestamp) < window_ms * 1000 {
                    *existing = event; // Replace with newer event
                }
            }
            None => {
                coalesced_map.insert(key, event);
            }
        }
    }
    
    let results: Vec<String> = coalesced_map
        .into_values()
        .filter_map(|event| serde_json::to_string(&event).ok())
        .collect();
    
    Ok(results)
}

#[rustler::nif]
fn batch_validate_rules(file_paths: Vec<String>) -> NifResult<Vec<String>> {
    let violations: Vec<ArchViolation> = file_paths
        .par_iter()
        .flat_map(|path| {
            let event = CoalescedEvent {
                path: path.clone(),
                kind: "validation".to_string(),
                timestamp: SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_micros() as u64,
                metadata: gather_file_metadata(&PathBuf::from(path)),
                rule_violations: Vec::new(),
            };
            check_event_against_rules(&event)
        })
        .collect();
    
    let results: Vec<String> = violations
        .into_iter()
        .filter_map(|violation| serde_json::to_string(&violation).ok())
        .collect();
    
    Ok(results)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct FileNode {
    path: String,
    name: String,
    file_type: String,
    size: u64,
    modified: u64,
    children: Vec<FileNode>,
}

#[rustler::nif]
fn scan_directory_tree(root_path: String, max_depth: u32) -> NifResult<Vec<String>> {
    let mut file_paths = Vec::new();
    
    for entry in WalkDir::new(&root_path)
        .max_depth(max_depth as usize)
        .follow_links(false)
    {
        if let Ok(entry) = entry {
            if entry.file_type().is_file() {
                file_paths.push(entry.path().to_string_lossy().to_string());
            }
        }
    }
    
    Ok(file_paths)
}

#[rustler::nif]
fn get_file_metadata_batch(file_paths: Vec<String>) -> NifResult<Vec<String>> {
    let metadata_results: Vec<String> = file_paths
        .par_iter()
        .filter_map(|path| {
            gather_file_metadata(&PathBuf::from(path))
                .and_then(|metadata| serde_json::to_string(&metadata).ok())
        })
        .collect();
    
    Ok(metadata_results)
}

#[rustler::nif]
fn setup_real_time_monitoring(watcher: ResourceArc<FsWatcherResource>) -> NifResult<Atom> {
    // This would start background monitoring tasks
    // For now, just return ok
    Ok(ok())
}

#[rustler::nif]
fn check_architecture_violations(events_json: Vec<String>) -> NifResult<Vec<String>> {
    let mut all_violations = Vec::new();
    
    for event_json in events_json {
        if let Ok(event) = serde_json::from_str::<CoalescedEvent>(&event_json) {
            let violations = check_event_against_rules(&event);
            all_violations.extend(violations);
        }
    }
    
    let results: Vec<String> = all_violations
        .into_iter()
        .filter_map(|violation| serde_json::to_string(&violation).ok())
        .collect();
    
    Ok(results)
}

// ============================================================================
// CRITICAL: SMART METADATA GATHERING
// ============================================================================

fn gather_file_metadata(path: &Path) -> Option<FileMetadata> {
    let metadata = std::fs::metadata(path).ok()?;
    
    let file_type = if metadata.is_file() {
        "file"
    } else if metadata.is_dir() {
        "directory"
    } else {
        "unknown"
    }.to_string();
    
    let content_hash = if metadata.is_file() && metadata.len() < 64 * 1024 {
        hash_file_content(path)
    } else {
        None
    };
    
    Some(FileMetadata {
        size: metadata.len(),
        modified: metadata
            .modified()
            .ok()?
            .duration_since(UNIX_EPOCH)
            .ok()?
            .as_secs(),
        file_type,
        permissions: get_permissions(&metadata),
        content_hash,
    })
}

#[cfg(unix)]
fn get_permissions(metadata: &std::fs::Metadata) -> u32 {
    use std::os::unix::fs::PermissionsExt;
    metadata.permissions().mode()
}

#[cfg(windows)]
fn get_permissions(metadata: &std::fs::Metadata) -> u32 {
    if metadata.permissions().readonly() {
        0o444
    } else {
        0o644
    }
}

fn hash_file_content(path: &Path) -> Option<u64> {
    use std::fs::File;
    use std::io::Read;
    
    let mut file = File::open(path).ok()?;
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer).ok()?;
    
    Some(xxhash_rust::xxh64::xxh64(&buffer, 0))
}

// ============================================================================
// CRITICAL: ARCHITECTURAL RULE CHECKING
// ============================================================================

fn check_event_against_rules(event: &CoalescedEvent) -> Vec<ArchViolation> {
    let mut violations = Vec::new();
    let rules = GLOBAL_RULES.read().unwrap();
    
    for rule in rules.iter() {
        match rule.rule_type {
            ArchRuleType::ForbiddenPath => {
                if path_matches_pattern(&event.path, &rule.pattern) {
                    violations.push(ArchViolation {
                        rule_id: rule.id.clone(),
                        path: event.path.clone(),
                        rule_type: "forbidden_path".to_string(),
                        severity: format!("{:?}", rule.severity).to_lowercase(),
                        message: rule.message.clone(),
                        suggested_fix: Some("Move file to appropriate location".to_string()),
                    });
                }
            }
            
            ArchRuleType::NamingConvention => {
                if !path_matches_pattern(&event.path, &rule.pattern) {
                    violations.push(ArchViolation {
                        rule_id: rule.id.clone(),
                        path: event.path.clone(),
                        rule_type: "naming_convention".to_string(),
                        severity: format!("{:?}", rule.severity).to_lowercase(),
                        message: rule.message.clone(),
                        suggested_fix: Some("Rename file to match convention".to_string()),
                    });
                }
            }
            
            ArchRuleType::LayerViolation => {
                // Basic layer violation checking
                if event.path.contains("/controllers/") && event.path.contains("/models/") {
                    violations.push(ArchViolation {
                        rule_id: rule.id.clone(),
                        path: event.path.clone(),
                        rule_type: "layer_violation".to_string(),
                        severity: "error".to_string(),
                        message: "Controller found in models directory".to_string(),
                        suggested_fix: Some("Move to appropriate controllers directory".to_string()),
                    });
                }
            }
            
            ArchRuleType::RequiredStructure => {
                // Implementation depends on specific project requirements
            }
        }
    }
    
    violations
}

fn path_matches_pattern(path: &str, pattern: &str) -> bool {
    // Check cache first
    if let Some(matcher) = GLOB_CACHE.get(pattern) {
        return matcher.is_match(path);
    }
    
    // Compile and cache pattern
    if let Ok(glob) = Glob::new(pattern) {
        let matcher = glob.compile_matcher();
        let is_match = matcher.is_match(path);
        GLOB_CACHE.insert(pattern.to_string(), matcher);
        is_match
    } else {
        false
    }
}