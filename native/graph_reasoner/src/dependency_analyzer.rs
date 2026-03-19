use crate::*;
use petgraph::prelude::*;
use petgraph::algo::{kosaraju_scc, toposort, has_path_connecting};
use std::collections::{HashMap, HashSet, VecDeque};
use rayon::prelude::*;
use serde_json::Value;

pub struct DependencyAnalyzer {
    cycle_detection_enabled: bool,
    impact_analysis_enabled: bool,
    criticality_analysis_enabled: bool,
    max_depth: usize,
    weight_threshold: f64,
}

pub struct DependencyAnalysisResult {
    pub nodes: Vec<GraphNode>,
    pub edges: Vec<GraphEdge>,
    pub critical_paths: Vec<Vec<String>>,
    pub cycles: Vec<SubgraphResult>,
    pub analysis_steps: Vec<String>,
    pub reliability_score: f64,
    pub metadata: HashMap<String, serde_json::Value>,
}

#[derive(Debug, Clone)]
pub struct DependencyMetrics {
    pub depth: usize,
    pub fan_in: usize,
    pub fan_out: usize,
    pub criticality_score: f64,
    pub stability: f64,
    pub coupling: f64,
    pub cohesion: f64,
}

#[derive(Debug, Clone)]
pub struct CycleInfo {
    pub nodes: Vec<String>,
    pub edges: Vec<String>,
    pub severity: f64,
    pub cycle_type: String,
    pub impact_score: f64,
}

impl DependencyAnalyzer {
    pub fn new(options: &HashMap<String, Value>) -> Result<Self, RustlerError> {
        let cycle_detection_enabled = options.get("cycle_detection")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);
        
        let impact_analysis_enabled = options.get("impact_analysis")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);
        
        let criticality_analysis_enabled = options.get("criticality_analysis")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);
        
        let max_depth = options.get("max_depth")
            .and_then(|v| v.as_u64())
            .map(|v| v as usize)
            .unwrap_or(50);
        
        let weight_threshold = options.get("weight_threshold")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.1);

        Ok(Self {
            cycle_detection_enabled,
            impact_analysis_enabled,
            criticality_analysis_enabled,
            max_depth,
            weight_threshold,
        })
    }

    pub fn analyze_dependencies(
        &self,
        dependencies: Vec<(String, Vec<String>)>
    ) -> Result<DependencyAnalysisResult, RustlerError> {
        let mut analysis_steps = Vec::new();
        analysis_steps.push("Starting dependency analysis".to_string());

        // Build dependency graph
        let (graph, node_map) = self.build_dependency_graph(dependencies)?;
        analysis_steps.push(format!("Built dependency graph with {} nodes and {} edges", 
                                   graph.node_count(), graph.edge_count()));

        // Analyze graph structure
        let mut nodes = self.extract_nodes_with_metrics(&graph, &node_map)?;
        let edges = self.extract_edges_with_metrics(&graph, &node_map)?;
        
        // Detect cycles if enabled
        let mut cycles = Vec::new();
        if self.cycle_detection_enabled {
            cycles = self.detect_dependency_cycles(&graph, &node_map)?;
            analysis_steps.push(format!("Detected {} dependency cycles", cycles.len()));
        }

        // Find critical paths
        let critical_paths = if self.criticality_analysis_enabled {
            let paths = self.find_critical_paths(&graph, &node_map)?;
            analysis_steps.push(format!("Identified {} critical paths", paths.len()));
            paths
        } else {
            Vec::new()
        };

        // Perform impact analysis
        if self.impact_analysis_enabled {
            self.perform_impact_analysis(&mut nodes, &graph, &node_map)?;
            analysis_steps.push("Completed impact analysis".to_string());
        }

        // Calculate reliability score
        let reliability_score = self.calculate_reliability_score(&cycles, &critical_paths, &nodes);
        analysis_steps.push(format!("Calculated reliability score: {:.3}", reliability_score));

        // Build metadata
        let mut metadata = HashMap::new();
        metadata.insert("total_nodes".to_string(), Value::Number(graph.node_count().into()));
        metadata.insert("total_edges".to_string(), Value::Number(graph.edge_count().into()));
        metadata.insert("cycles_detected".to_string(), Value::Number(cycles.len().into()));
        metadata.insert("critical_paths".to_string(), Value::Number(critical_paths.len().into()));
        metadata.insert("analysis_depth".to_string(), Value::Number(self.max_depth.into()));

        Ok(DependencyAnalysisResult {
            nodes,
            edges,
            critical_paths,
            cycles,
            analysis_steps,
            reliability_score,
            metadata,
        })
    }

    fn build_dependency_graph(
        &self,
        dependencies: Vec<(String, Vec<String>)>
    ) -> Result<(Graph<GraphNode, GraphEdge, Directed>, HashMap<String, NodeIndex>), RustlerError> {
        let mut graph = Graph::new();
        let mut node_map = HashMap::new();
        let mut node_counter = 0;

        // Create all nodes first
        let mut all_nodes = HashSet::new();
        for (source, targets) in &dependencies {
            all_nodes.insert(source.clone());
            for target in targets {
                all_nodes.insert(target.clone());
            }
        }

        // Add nodes to graph
        for node_id in all_nodes {
            node_counter += 1;
            let node = GraphNode {
                id: node_id.clone(),
                node_type: "dependency".to_string(),
                label: node_id.clone(),
                properties: HashMap::new(),
                weight: 1.0,
                centrality_scores: HashMap::new(),
                community_id: None,
                semantic_embedding: None,
                metadata: HashMap::new(),
            };
            
            let node_index = graph.add_node(node);
            node_map.insert(node_id, node_index);
        }

        // Add edges
        let mut edge_counter = 0;
        for (source, targets) in dependencies {
            if let Some(&source_idx) = node_map.get(&source) {
                for target in targets {
                    if let Some(&target_idx) = node_map.get(&target) {
                        edge_counter += 1;
                        let edge = GraphEdge {
                            id: format!("dep_edge_{}", edge_counter),
                            source: source.clone(),
                            target: target.clone(),
                            edge_type: "depends_on".to_string(),
                            label: "depends on".to_string(),
                            weight: 1.0,
                            confidence: 1.0,
                            properties: HashMap::new(),
                            bidirectional: false,
                            semantic_strength: 1.0,
                            metadata: HashMap::new(),
                        };
                        
                        graph.add_edge(source_idx, target_idx, edge);
                    }
                }
            }
        }

        Ok((graph, node_map))
    }

    fn extract_nodes_with_metrics(
        &self,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        node_map: &HashMap<String, NodeIndex>
    ) -> Result<Vec<GraphNode>, RustlerError> {
        let mut nodes = Vec::new();

        for (node_id, &node_idx) in node_map {
            if let Some(mut node) = graph.node_weight(node_idx).cloned() {
                // Calculate dependency metrics
                let metrics = self.calculate_dependency_metrics(graph, node_idx)?;
                
                // Update node with calculated metrics
                node.centrality_scores.insert("depth".to_string(), metrics.depth as f64);
                node.centrality_scores.insert("fan_in".to_string(), metrics.fan_in as f64);
                node.centrality_scores.insert("fan_out".to_string(), metrics.fan_out as f64);
                node.centrality_scores.insert("criticality".to_string(), metrics.criticality_score);
                node.centrality_scores.insert("stability".to_string(), metrics.stability);
                node.centrality_scores.insert("coupling".to_string(), metrics.coupling);
                node.centrality_scores.insert("cohesion".to_string(), metrics.cohesion);
                
                // Set node weight based on criticality
                node.weight = metrics.criticality_score;
                
                // Add metadata
                node.metadata.insert("dependency_type".to_string(), 
                                   self.classify_dependency_type(&metrics));
                node.metadata.insert("risk_level".to_string(), 
                                   self.assess_risk_level(&metrics));
                
                nodes.push(node);
            }
        }

        Ok(nodes)
    }

    fn extract_edges_with_metrics(
        &self,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        node_map: &HashMap<String, NodeIndex>
    ) -> Result<Vec<GraphEdge>, RustlerError> {
        let mut edges = Vec::new();

        for edge_ref in graph.edge_references() {
            let mut edge = edge_ref.weight().clone();
            
            // Calculate edge criticality
            let source_metrics = self.calculate_dependency_metrics(graph, edge_ref.source())?;
            let target_metrics = self.calculate_dependency_metrics(graph, edge_ref.target())?;
            
            let edge_criticality = (source_metrics.criticality_score + target_metrics.criticality_score) / 2.0;
            edge.weight = edge_criticality;
            edge.confidence = self.calculate_edge_confidence(&source_metrics, &target_metrics);
            
            // Add edge metadata
            edge.metadata.insert("source_stability".to_string(), 
                               source_metrics.stability.to_string());
            edge.metadata.insert("target_stability".to_string(), 
                               target_metrics.stability.to_string());
            edge.metadata.insert("coupling_strength".to_string(), 
                               (source_metrics.coupling * target_metrics.coupling).to_string());
            
            edges.push(edge);
        }

        Ok(edges)
    }

    fn calculate_dependency_metrics(
        &self,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        node_idx: NodeIndex
    ) -> Result<DependencyMetrics, RustlerError> {
        let fan_in = graph.edges_directed(node_idx, Direction::Incoming).count();
        let fan_out = graph.edges_directed(node_idx, Direction::Outgoing).count();
        
        // Calculate depth using DFS
        let depth = self.calculate_node_depth(graph, node_idx);
        
        // Calculate stability (fan_out / (fan_in + fan_out))
        let total_connections = fan_in + fan_out;
        let stability = if total_connections > 0 {
            fan_out as f64 / total_connections as f64
        } else {
            0.5 // Neutral stability for isolated nodes
        };
        
        // Calculate coupling (normalized by graph size)
        let coupling = total_connections as f64 / graph.node_count().max(1) as f64;
        
        // Calculate cohesion (based on clustering of dependencies)
        let cohesion = self.calculate_cohesion(graph, node_idx);
        
        // Calculate criticality score
        let criticality_score = self.calculate_criticality_score(
            depth, fan_in, fan_out, stability, coupling, cohesion
        );

        Ok(DependencyMetrics {
            depth,
            fan_in,
            fan_out,
            criticality_score,
            stability,
            coupling,
            cohesion,
        })
    }

    fn calculate_node_depth(&self, graph: &Graph<GraphNode, GraphEdge, Directed>, start: NodeIndex) -> usize {
        let mut visited = HashSet::new();
        let mut queue = VecDeque::new();
        let mut max_depth = 0;
        
        queue.push_back((start, 0));
        visited.insert(start);
        
        while let Some((node, depth)) = queue.pop_front() {
            if depth > self.max_depth {
                break;
            }
            
            max_depth = max_depth.max(depth);
            
            for edge in graph.edges_directed(node, Direction::Outgoing) {
                let target = edge.target();
                if !visited.contains(&target) {
                    visited.insert(target);
                    queue.push_back((target, depth + 1));
                }
            }
        }
        
        max_depth
    }

    fn calculate_cohesion(&self, graph: &Graph<GraphNode, GraphEdge, Directed>, node_idx: NodeIndex) -> f64 {
        let neighbors: HashSet<NodeIndex> = graph.edges(node_idx)
            .map(|edge| edge.target())
            .collect();
        
        if neighbors.len() <= 1 {
            return 1.0;
        }
        
        let mut internal_connections = 0;
        let mut total_possible_connections = 0;
        
        for &neighbor1 in &neighbors {
            for &neighbor2 in &neighbors {
                if neighbor1 != neighbor2 {
                    total_possible_connections += 1;
                    if has_path_connecting(graph, neighbor1, neighbor2, None) {
                        internal_connections += 1;
                    }
                }
            }
        }
        
        if total_possible_connections > 0 {
            internal_connections as f64 / total_possible_connections as f64
        } else {
            1.0
        }
    }

    fn calculate_criticality_score(
        &self,
        depth: usize,
        fan_in: usize,
        fan_out: usize,
        stability: f64,
        coupling: f64,
        cohesion: f64
    ) -> f64 {
        // Weighted combination of various factors
        let depth_score = (depth as f64 / self.max_depth as f64).min(1.0);
        let connectivity_score = (fan_in + fan_out) as f64 / 20.0; // Normalize to typical range
        let instability_penalty = 1.0 - (stability - 0.5).abs() * 2.0; // Penalty for extreme stability
        let coupling_score = coupling.min(1.0);
        let cohesion_score = cohesion;
        
        // Weighted average
        let weights = [0.2, 0.3, 0.15, 0.2, 0.15]; // depth, connectivity, stability, coupling, cohesion
        let scores = [depth_score, connectivity_score, instability_penalty, coupling_score, cohesion_score];
        
        weights.iter()
            .zip(scores.iter())
            .map(|(w, s)| w * s)
            .sum::<f64>()
            .max(0.0)
            .min(1.0)
    }

    fn calculate_edge_confidence(&self, source_metrics: &DependencyMetrics, target_metrics: &DependencyMetrics) -> f64 {
        // Edge confidence based on stability of both endpoints
        let avg_stability = (source_metrics.stability + target_metrics.stability) / 2.0;
        let stability_factor = 1.0 - (avg_stability - 0.5).abs() * 2.0;
        
        // Factor in coupling strength
        let coupling_factor = (source_metrics.coupling * target_metrics.coupling).sqrt();
        
        // Combined confidence score
        (stability_factor * 0.7 + coupling_factor * 0.3).max(0.1).min(1.0)
    }

    fn classify_dependency_type(&self, metrics: &DependencyMetrics) -> String {
        match (metrics.fan_in, metrics.fan_out, metrics.stability) {
            (0, 0, _) => "isolated".to_string(),
            (0, _, _) => "source".to_string(),
            (_, 0, _) => "sink".to_string(),
            (_, _, s) if s > 0.8 => "stable_hub".to_string(),
            (_, _, s) if s < 0.2 => "unstable_hub".to_string(),
            _ => "intermediate".to_string(),
        }
    }

    fn assess_risk_level(&self, metrics: &DependencyMetrics) -> String {
        let risk_score = metrics.criticality_score * (1.0 - metrics.stability) * metrics.coupling;
        
        if risk_score > 0.7 {
            "high".to_string()
        } else if risk_score > 0.4 {
            "medium".to_string()
        } else {
            "low".to_string()
        }
    }

    fn detect_dependency_cycles(
        &self,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        node_map: &HashMap<String, NodeIndex>
    ) -> Result<Vec<SubgraphResult>, RustlerError> {
        let mut cycles = Vec::new();
        
        // Use Kosaraju's algorithm to find strongly connected components
        let sccs = kosaraju_scc(graph);
        
        let mut cycle_id = 0;
        for scc in sccs {
            if scc.len() > 1 {
                // This is a cycle
                cycle_id += 1;
                
                let cycle_nodes: Vec<String> = scc.iter()
                    .filter_map(|&node_idx| graph.node_weight(node_idx))
                    .map(|node| node.id.clone())
                    .collect();
                
                let cycle_edges: Vec<String> = scc.iter()
                    .flat_map(|&node_idx| {
                        graph.edges_directed(node_idx, Direction::Outgoing)
                            .filter(|edge| scc.contains(&edge.target()))
                            .map(|edge| edge.weight().id.clone())
                    })
                    .collect();
                
                // Calculate cycle severity
                let avg_criticality: f64 = scc.iter()
                    .filter_map(|&node_idx| {
                        self.calculate_dependency_metrics(graph, node_idx).ok()
                    })
                    .map(|metrics| metrics.criticality_score)
                    .sum::<f64>() / scc.len() as f64;
                
                let cycle_severity = avg_criticality * (scc.len() as f64 / graph.node_count() as f64);
                
                let mut properties = HashMap::new();
                properties.insert("cycle_length".to_string(), Value::Number(scc.len().into()));
                properties.insert("avg_criticality".to_string(), 
                                Value::Number(serde_json::Number::from_f64(avg_criticality).unwrap_or(serde_json::Number::from(0))));
                properties.insert("cycle_type".to_string(), 
                                Value::String(if scc.len() == 2 { "mutual".to_string() } else { "complex".to_string() }));
                
                cycles.push(SubgraphResult {
                    id: format!("cycle_{}", cycle_id),
                    nodes: cycle_nodes,
                    edges: cycle_edges,
                    pattern_type: "dependency_cycle".to_string(),
                    significance_score: cycle_severity,
                    properties,
                });
            }
        }
        
        Ok(cycles)
    }

    fn find_critical_paths(
        &self,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        node_map: &HashMap<String, NodeIndex>
    ) -> Result<Vec<Vec<String>>, RustlerError> {
        let mut critical_paths = Vec::new();
        
        // Find source nodes (no incoming edges)
        let source_nodes: Vec<NodeIndex> = graph.node_indices()
            .filter(|&node| graph.edges_directed(node, Direction::Incoming).count() == 0)
            .collect();
        
        // Find sink nodes (no outgoing edges)
        let sink_nodes: Vec<NodeIndex> = graph.node_indices()
            .filter(|&node| graph.edges_directed(node, Direction::Outgoing).count() == 0)
            .collect();
        
        // Find paths from each source to each sink
        for &source in &source_nodes {
            for &sink in &sink_nodes {
                if let Some(path) = self.find_longest_path(graph, source, sink) {
                    let path_nodes: Vec<String> = path.iter()
                        .filter_map(|&node_idx| graph.node_weight(node_idx))
                        .map(|node| node.id.clone())
                        .collect();
                    
                    if path_nodes.len() > 2 { // Only include non-trivial paths
                        critical_paths.push(path_nodes);
                    }
                }
            }
        }
        
        // Sort by path length and criticality
        critical_paths.sort_by(|a, b| b.len().cmp(&a.len()));
        
        // Return top critical paths
        Ok(critical_paths.into_iter().take(10).collect())
    }

    fn find_longest_path(
        &self,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        start: NodeIndex,
        end: NodeIndex
    ) -> Option<Vec<NodeIndex>> {
        let mut visited = HashSet::new();
        let mut path = Vec::new();
        
        if self.dfs_longest_path(graph, start, end, &mut visited, &mut path, 0) {
            Some(path)
        } else {
            None
        }
    }

    fn dfs_longest_path(
        &self,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        current: NodeIndex,
        target: NodeIndex,
        visited: &mut HashSet<NodeIndex>,
        path: &mut Vec<NodeIndex>,
        depth: usize
    ) -> bool {
        if depth > self.max_depth {
            return false;
        }
        
        visited.insert(current);
        path.push(current);
        
        if current == target {
            return true;
        }
        
        for edge in graph.edges_directed(current, Direction::Outgoing) {
            let next = edge.target();
            if !visited.contains(&next) {
                if self.dfs_longest_path(graph, next, target, visited, path, depth + 1) {
                    return true;
                }
            }
        }
        
        visited.remove(&current);
        path.pop();
        false
    }

    fn perform_impact_analysis(
        &self,
        nodes: &mut Vec<GraphNode>,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        node_map: &HashMap<String, NodeIndex>
    ) -> Result<(), RustlerError> {
        for node in nodes.iter_mut() {
            if let Some(&node_idx) = node_map.get(&node.id) {
                // Calculate impact metrics
                let downstream_count = self.count_downstream_nodes(graph, node_idx);
                let upstream_count = self.count_upstream_nodes(graph, node_idx);
                
                let impact_score = (downstream_count + upstream_count) as f64 / graph.node_count() as f64;
                
                // Add impact metrics to centrality scores
                node.centrality_scores.insert("impact_score".to_string(), impact_score);
                node.centrality_scores.insert("downstream_count".to_string(), downstream_count as f64);
                node.centrality_scores.insert("upstream_count".to_string(), upstream_count as f64);
                
                // Update metadata
                node.metadata.insert("impact_classification".to_string(), 
                                   self.classify_impact_level(impact_score));
            }
        }
        
        Ok(())
    }

    fn count_downstream_nodes(&self, graph: &Graph<GraphNode, GraphEdge, Directed>, start: NodeIndex) -> usize {
        let mut visited = HashSet::new();
        let mut queue = VecDeque::new();
        
        queue.push_back(start);
        visited.insert(start);
        
        while let Some(node) = queue.pop_front() {
            for edge in graph.edges_directed(node, Direction::Outgoing) {
                let target = edge.target();
                if !visited.contains(&target) {
                    visited.insert(target);
                    queue.push_back(target);
                }
            }
        }
        
        visited.len() - 1 // Subtract 1 to exclude the start node itself
    }

    fn count_upstream_nodes(&self, graph: &Graph<GraphNode, GraphEdge, Directed>, start: NodeIndex) -> usize {
        let mut visited = HashSet::new();
        let mut queue = VecDeque::new();
        
        queue.push_back(start);
        visited.insert(start);
        
        while let Some(node) = queue.pop_front() {
            for edge in graph.edges_directed(node, Direction::Incoming) {
                let source = edge.source();
                if !visited.contains(&source) {
                    visited.insert(source);
                    queue.push_back(source);
                }
            }
        }
        
        visited.len() - 1 // Subtract 1 to exclude the start node itself
    }

    fn classify_impact_level(&self, impact_score: f64) -> String {
        if impact_score > 0.5 {
            "high_impact".to_string()
        } else if impact_score > 0.2 {
            "medium_impact".to_string()
        } else {
            "low_impact".to_string()
        }
    }

    fn calculate_reliability_score(
        &self,
        cycles: &[SubgraphResult],
        critical_paths: &[Vec<String>],
        nodes: &[GraphNode]
    ) -> f64 {
        if nodes.is_empty() {
            return 0.0;
        }
        
        // Base reliability starts at 1.0
        let mut reliability = 1.0;
        
        // Penalty for cycles
        let cycle_penalty = cycles.iter()
            .map(|cycle| cycle.significance_score * 0.1)
            .sum::<f64>();
        reliability -= cycle_penalty.min(0.5);
        
        // Consider critical path lengths
        let avg_path_length = if !critical_paths.is_empty() {
            critical_paths.iter().map(|path| path.len()).sum::<usize>() as f64 / critical_paths.len() as f64
        } else {
            1.0
        };
        
        let path_complexity_penalty = (avg_path_length / nodes.len() as f64 * 0.2).min(0.3);
        reliability -= path_complexity_penalty;
        
        // Consider overall system coupling
        let avg_coupling = nodes.iter()
            .filter_map(|node| node.centrality_scores.get("coupling"))
            .sum::<f64>() / nodes.len() as f64;
        
        let coupling_penalty = (avg_coupling * 0.1).min(0.2);
        reliability -= coupling_penalty;
        
        reliability.max(0.0).min(1.0)
    }
}