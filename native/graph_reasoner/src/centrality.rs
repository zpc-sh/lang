use crate::*;
use petgraph::prelude::*;
use petgraph::algo::dijkstra;
use std::collections::{HashMap, BinaryHeap};
use std::cmp::Ordering;
use rayon::prelude::*;
use ndarray::{Array2, Array1};
use statrs::distribution::{Normal, ContinuousCDF};
use statrs::statistics::{Statistics, OrderStatistics};

pub struct CentralityAnalysisResult {
    pub scores: HashMap<String, f64>,
    pub top_nodes: Vec<(String, f64)>,
    pub stats: CentralityStats,
}

#[derive(Clone, Debug)]
struct NodeScore {
    node_id: String,
    score: f64,
}

impl Eq for NodeScore {}

impl PartialEq for NodeScore {
    fn eq(&self, other: &Self) -> bool {
        self.score == other.score
    }
}

impl Ord for NodeScore {
    fn cmp(&self, other: &Self) -> Ordering {
        self.score.partial_cmp(&other.score).unwrap_or(Ordering::Equal)
    }
}

impl PartialOrd for NodeScore {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

pub fn calculate_pagerank(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    options: &HashMap<String, serde_json::Value>
) -> Result<CentralityAnalysisResult, RustlerError> {
    let damping_factor = options.get("damping_factor")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.85);
    
    let max_iterations = options.get("max_iterations")
        .and_then(|v| v.as_u64())
        .map(|v| v as usize)
        .unwrap_or(100);
    
    let tolerance = options.get("tolerance")
        .and_then(|v| v.as_f64())
        .unwrap_or(1e-6);

    let node_count = graph.node_count();
    if node_count == 0 {
        return Ok(CentralityAnalysisResult {
            scores: HashMap::new(),
            top_nodes: Vec::new(),
            stats: CentralityStats {
                mean: 0.0,
                median: 0.0,
                std_dev: 0.0,
                min: 0.0,
                max: 0.0,
                percentile_95: 0.0,
            },
        });
    }

    // Initialize PageRank values
    let initial_value = 1.0 / node_count as f64;
    let mut pagerank = vec![initial_value; node_count];
    let mut new_pagerank = vec![0.0; node_count];
    
    // Create node index mapping
    let node_indices: Vec<_> = graph.node_indices().collect();
    let index_to_node: HashMap<NodeIndex, usize> = node_indices.iter()
        .enumerate()
        .map(|(i, &idx)| (idx, i))
        .collect();

    // Calculate out-degrees
    let mut out_degrees = vec![0; node_count];
    for (i, &node_idx) in node_indices.iter().enumerate() {
        out_degrees[i] = graph.edges_directed(node_idx, Direction::Outgoing).count();
    }

    // Iterative PageRank calculation
    for iteration in 0..max_iterations {
        new_pagerank.fill(0.0);
        
        // Distribute PageRank values
        for (i, &node_idx) in node_indices.iter().enumerate() {
            if out_degrees[i] > 0 {
                let contribution = pagerank[i] / out_degrees[i] as f64;
                for edge in graph.edges_directed(node_idx, Direction::Outgoing) {
                    if let Some(&target_i) = index_to_node.get(&edge.target()) {
                        new_pagerank[target_i] += damping_factor * contribution;
                    }
                }
            }
        }
        
        // Add random jump probability
        let random_jump = (1.0 - damping_factor) / node_count as f64;
        for value in &mut new_pagerank {
            *value += random_jump;
        }
        
        // Handle dangling nodes (nodes with no outgoing edges)
        let dangling_sum: f64 = node_indices.iter()
            .enumerate()
            .filter(|(i, _)| out_degrees[*i] == 0)
            .map(|(i, _)| pagerank[i])
            .sum();
        
        let dangling_contribution = damping_factor * dangling_sum / node_count as f64;
        for value in &mut new_pagerank {
            *value += dangling_contribution;
        }
        
        // Check for convergence
        let diff: f64 = pagerank.iter()
            .zip(new_pagerank.iter())
            .map(|(old, new)| (old - new).abs())
            .sum();
        
        std::mem::swap(&mut pagerank, &mut new_pagerank);
        
        if diff < tolerance {
            break;
        }
    }

    // Create result mapping
    let mut scores = HashMap::new();
    for (i, &node_idx) in node_indices.iter().enumerate() {
        if let Some(node) = graph.node_weight(node_idx) {
            scores.insert(node.id.clone(), pagerank[i]);
        }
    }

    let stats = calculate_centrality_stats(&pagerank);
    let top_nodes = get_top_nodes(&scores, 10);

    Ok(CentralityAnalysisResult {
        scores,
        top_nodes,
        stats,
    })
}

pub fn calculate_betweenness_centrality(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    options: &HashMap<String, serde_json::Value>
) -> Result<CentralityAnalysisResult, RustlerError> {
    let normalized = options.get("normalized")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    
    let endpoints = options.get("endpoints")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    let node_count = graph.node_count();
    if node_count == 0 {
        return Ok(empty_centrality_result());
    }

    let node_indices: Vec<_> = graph.node_indices().collect();
    let mut betweenness = vec![0.0; node_count];
    let index_to_position: HashMap<NodeIndex, usize> = node_indices.iter()
        .enumerate()
        .map(|(i, &idx)| (idx, i))
        .collect();

    // Brandes' algorithm for betweenness centrality
    for (s_pos, &s) in node_indices.iter().enumerate() {
        let mut stack = Vec::new();
        let mut predecessors = vec![Vec::new(); node_count];
        let mut sigma = vec![0.0; node_count];
        let mut distance = vec![-1.0; node_count];
        let mut delta = vec![0.0; node_count];
        
        sigma[s_pos] = 1.0;
        distance[s_pos] = 0.0;
        let mut queue = VecDeque::new();
        queue.push_back(s);
        
        // Single-source shortest-path problem
        while let Some(v) = queue.pop_front() {
            if let Some(&v_pos) = index_to_position.get(&v) {
                stack.push(v);
                
                for edge in graph.edges_directed(v, Direction::Outgoing) {
                    let w = edge.target();
                    if let Some(&w_pos) = index_to_position.get(&w) {
                        // First time we see w?
                        if distance[w_pos] < 0.0 {
                            queue.push_back(w);
                            distance[w_pos] = distance[v_pos] + 1.0;
                        }
                        // Shortest path to w via v?
                        if distance[w_pos] == distance[v_pos] + 1.0 {
                            sigma[w_pos] += sigma[v_pos];
                            predecessors[w_pos].push(v_pos);
                        }
                    }
                }
            }
        }
        
        // Accumulation
        while let Some(w) = stack.pop() {
            if let Some(&w_pos) = index_to_position.get(&w) {
                for &v_pos in &predecessors[w_pos] {
                    if sigma[w_pos] != 0.0 {
                        delta[v_pos] += (sigma[v_pos] / sigma[w_pos]) * (1.0 + delta[w_pos]);
                    }
                }
                if w != s {
                    betweenness[w_pos] += delta[w_pos];
                }
            }
        }
    }

    // Normalization
    if normalized && node_count > 2 {
        let normalization_factor = if graph.is_directed() {
            (node_count - 1) * (node_count - 2)
        } else {
            (node_count - 1) * (node_count - 2) / 2
        } as f64;
        
        for score in &mut betweenness {
            *score /= normalization_factor;
        }
    }

    // Handle endpoints
    if endpoints {
        for score in &mut betweenness {
            *score += 1.0;
        }
    }

    // Create result mapping
    let mut scores = HashMap::new();
    for (i, &node_idx) in node_indices.iter().enumerate() {
        if let Some(node) = graph.node_weight(node_idx) {
            scores.insert(node.id.clone(), betweenness[i]);
        }
    }

    let stats = calculate_centrality_stats(&betweenness);
    let top_nodes = get_top_nodes(&scores, 10);

    Ok(CentralityAnalysisResult {
        scores,
        top_nodes,
        stats,
    })
}

pub fn calculate_closeness_centrality(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    options: &HashMap<String, serde_json::Value>
) -> Result<CentralityAnalysisResult, RustlerError> {
    let normalized = options.get("normalized")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    
    let use_weights = options.get("use_weights")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    let node_count = graph.node_count();
    if node_count == 0 {
        return Ok(empty_centrality_result());
    }

    let node_indices: Vec<_> = graph.node_indices().collect();
    let mut closeness = Vec::new();

    for &source in &node_indices {
        let distances = if use_weights {
            dijkstra(graph, source, None, |edge| edge.weight().weight)
        } else {
            dijkstra(graph, source, None, |_| 1.0)
        };
        
        let reachable_distances: Vec<f64> = distances.values()
            .filter(|&&d| d > 0.0 && d.is_finite())
            .copied()
            .collect();
        
        let closeness_score = if reachable_distances.is_empty() {
            0.0
        } else {
            let sum_distances: f64 = reachable_distances.iter().sum();
            let reachable_count = reachable_distances.len() as f64;
            
            if sum_distances > 0.0 {
                let raw_closeness = reachable_count / sum_distances;
                if normalized && node_count > 1 {
                    raw_closeness * reachable_count / (node_count - 1) as f64
                } else {
                    raw_closeness
                }
            } else {
                0.0
            }
        };
        
        closeness.push(closeness_score);
    }

    // Create result mapping
    let mut scores = HashMap::new();
    for (i, &node_idx) in node_indices.iter().enumerate() {
        if let Some(node) = graph.node_weight(node_idx) {
            scores.insert(node.id.clone(), closeness[i]);
        }
    }

    let stats = calculate_centrality_stats(&closeness);
    let top_nodes = get_top_nodes(&scores, 10);

    Ok(CentralityAnalysisResult {
        scores,
        top_nodes,
        stats,
    })
}

pub fn calculate_eigenvector_centrality(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    options: &HashMap<String, serde_json::Value>
) -> Result<CentralityAnalysisResult, RustlerError> {
    let max_iterations = options.get("max_iterations")
        .and_then(|v| v.as_u64())
        .map(|v| v as usize)
        .unwrap_or(100);
    
    let tolerance = options.get("tolerance")
        .and_then(|v| v.as_f64())
        .unwrap_or(1e-6);

    let node_count = graph.node_count();
    if node_count == 0 {
        return Ok(empty_centrality_result());
    }

    let node_indices: Vec<_> = graph.node_indices().collect();
    let index_to_position: HashMap<NodeIndex, usize> = node_indices.iter()
        .enumerate()
        .map(|(i, &idx)| (idx, i))
        .collect();

    // Build adjacency matrix
    let mut adj_matrix = Array2::<f64>::zeros((node_count, node_count));
    for edge in graph.edge_references() {
        if let (Some(&i), Some(&j)) = (index_to_position.get(&edge.source()), 
                                       index_to_position.get(&edge.target())) {
            adj_matrix[[i, j]] = edge.weight().weight;
            if !graph.is_directed() {
                adj_matrix[[j, i]] = edge.weight().weight;
            }
        }
    }

    // Power iteration method
    let mut eigenvector = Array1::<f64>::ones(node_count) / (node_count as f64).sqrt();
    let mut prev_eigenvector = eigenvector.clone();

    for _ in 0..max_iterations {
        prev_eigenvector.assign(&eigenvector);
        eigenvector = adj_matrix.dot(&eigenvector);
        
        // Normalize
        let norm = eigenvector.iter().map(|x| x * x).sum::<f64>().sqrt();
        if norm > 0.0 {
            eigenvector /= norm;
        }
        
        // Check convergence
        let diff = eigenvector.iter()
            .zip(prev_eigenvector.iter())
            .map(|(a, b)| (a - b).abs())
            .sum::<f64>();
        
        if diff < tolerance {
            break;
        }
    }

    // Ensure positive values
    if eigenvector.iter().sum::<f64>() < 0.0 {
        eigenvector *= -1.0;
    }

    // Create result mapping
    let mut scores = HashMap::new();
    for (i, &node_idx) in node_indices.iter().enumerate() {
        if let Some(node) = graph.node_weight(node_idx) {
            scores.insert(node.id.clone(), eigenvector[i]);
        }
    }

    let eigenvector_vec: Vec<f64> = eigenvector.to_vec();
    let stats = calculate_centrality_stats(&eigenvector_vec);
    let top_nodes = get_top_nodes(&scores, 10);

    Ok(CentralityAnalysisResult {
        scores,
        top_nodes,
        stats,
    })
}

pub fn calculate_degree_centrality(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    options: &HashMap<String, serde_json::Value>
) -> Result<CentralityAnalysisResult, RustlerError> {
    let mode = options.get("mode")
        .and_then(|v| v.as_str())
        .unwrap_or("total"); // "in", "out", or "total"
    
    let normalized = options.get("normalized")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    let node_count = graph.node_count();
    if node_count == 0 {
        return Ok(empty_centrality_result());
    }

    let node_indices: Vec<_> = graph.node_indices().collect();
    let mut degrees = Vec::new();

    for &node_idx in &node_indices {
        let degree = match mode {
            "in" => graph.edges_directed(node_idx, Direction::Incoming).count(),
            "out" => graph.edges_directed(node_idx, Direction::Outgoing).count(),
            "total" => {
                graph.edges_directed(node_idx, Direction::Incoming).count() +
                graph.edges_directed(node_idx, Direction::Outgoing).count()
            },
            _ => graph.edges_directed(node_idx, Direction::Outgoing).count(),
        } as f64;
        
        let normalized_degree = if normalized && node_count > 1 {
            let max_possible = match mode {
                "total" if !graph.is_directed() => (node_count - 1) as f64,
                "total" => 2.0 * (node_count - 1) as f64,
                _ => (node_count - 1) as f64,
            };
            degree / max_possible
        } else {
            degree
        };
        
        degrees.push(normalized_degree);
    }

    // Create result mapping
    let mut scores = HashMap::new();
    for (i, &node_idx) in node_indices.iter().enumerate() {
        if let Some(node) = graph.node_weight(node_idx) {
            scores.insert(node.id.clone(), degrees[i]);
        }
    }

    let stats = calculate_centrality_stats(&degrees);
    let top_nodes = get_top_nodes(&scores, 10);

    Ok(CentralityAnalysisResult {
        scores,
        top_nodes,
        stats,
    })
}

pub fn calculate_katz_centrality(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    options: &HashMap<String, serde_json::Value>
) -> Result<CentralityAnalysisResult, RustlerError> {
    let alpha = options.get("alpha")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.1);
    
    let beta = options.get("beta")
        .and_then(|v| v.as_f64())
        .unwrap_or(1.0);
    
    let max_iterations = options.get("max_iterations")
        .and_then(|v| v.as_u64())
        .map(|v| v as usize)
        .unwrap_or(100);
    
    let tolerance = options.get("tolerance")
        .and_then(|v| v.as_f64())
        .unwrap_or(1e-6);

    let node_count = graph.node_count();
    if node_count == 0 {
        return Ok(empty_centrality_result());
    }

    let node_indices: Vec<_> = graph.node_indices().collect();
    let index_to_position: HashMap<NodeIndex, usize> = node_indices.iter()
        .enumerate()
        .map(|(i, &idx)| (idx, i))
        .collect();

    let mut katz_scores = vec![beta; node_count];
    let mut new_scores = vec![0.0; node_count];

    for _ in 0..max_iterations {
        new_scores.fill(beta);
        
        for (i, &node_idx) in node_indices.iter().enumerate() {
            for edge in graph.edges_directed(node_idx, Direction::Incoming) {
                if let Some(&source_pos) = index_to_position.get(&edge.source()) {
                    new_scores[i] += alpha * katz_scores[source_pos] * edge.weight().weight;
                }
            }
        }
        
        // Check convergence
        let diff: f64 = katz_scores.iter()
            .zip(new_scores.iter())
            .map(|(old, new)| (old - new).abs())
            .sum();
        
        std::mem::swap(&mut katz_scores, &mut new_scores);
        
        if diff < tolerance {
            break;
        }
    }

    // Create result mapping
    let mut scores = HashMap::new();
    for (i, &node_idx) in node_indices.iter().enumerate() {
        if let Some(node) = graph.node_weight(node_idx) {
            scores.insert(node.id.clone(), katz_scores[i]);
        }
    }

    let stats = calculate_centrality_stats(&katz_scores);
    let top_nodes = get_top_nodes(&scores, 10);

    Ok(CentralityAnalysisResult {
        scores,
        top_nodes,
        stats,
    })
}

fn calculate_centrality_stats(values: &[f64]) -> CentralityStats {
    if values.is_empty() {
        return CentralityStats {
            mean: 0.0,
            median: 0.0,
            std_dev: 0.0,
            min: 0.0,
            max: 0.0,
            percentile_95: 0.0,
        };
    }

    let mut sorted_values = values.to_vec();
    sorted_values.sort_by(|a, b| a.partial_cmp(b).unwrap_or(Ordering::Equal));

    let mean = values.iter().sum::<f64>() / values.len() as f64;
    let variance = values.iter()
        .map(|x| (x - mean).powi(2))
        .sum::<f64>() / values.len() as f64;
    let std_dev = variance.sqrt();
    
    let median = if sorted_values.len() % 2 == 0 {
        let mid = sorted_values.len() / 2;
        (sorted_values[mid - 1] + sorted_values[mid]) / 2.0
    } else {
        sorted_values[sorted_values.len() / 2]
    };
    
    let percentile_95_idx = ((sorted_values.len() as f64 * 0.95) as usize).min(sorted_values.len() - 1);
    let percentile_95 = sorted_values[percentile_95_idx];

    CentralityStats {
        mean,
        median,
        std_dev,
        min: sorted_values[0],
        max: sorted_values[sorted_values.len() - 1],
        percentile_95,
    }
}

fn get_top_nodes(scores: &HashMap<String, f64>, k: usize) -> Vec<(String, f64)> {
    let mut heap = BinaryHeap::new();
    
    for (node_id, &score) in scores {
        heap.push(NodeScore {
            node_id: node_id.clone(),
            score,
        });
    }
    
    let mut top_nodes = Vec::new();
    for _ in 0..k.min(heap.len()) {
        if let Some(node_score) = heap.pop() {
            top_nodes.push((node_score.node_id, node_score.score));
        }
    }
    
    top_nodes
}

fn empty_centrality_result() -> CentralityAnalysisResult {
    CentralityAnalysisResult {
        scores: HashMap::new(),
        top_nodes: Vec::new(),
        stats: CentralityStats {
            mean: 0.0,
            median: 0.0,
            std_dev: 0.0,
            min: 0.0,
            max: 0.0,
            percentile_95: 0.0,
        },
    }
}

// Parallel implementations for large graphs
pub fn calculate_betweenness_centrality_parallel(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    options: &HashMap<String, serde_json::Value>
) -> Result<CentralityAnalysisResult, RustlerError> {
    let normalized = options.get("normalized")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    let node_count = graph.node_count();
    if node_count == 0 {
        return Ok(empty_centrality_result());
    }

    let node_indices: Vec<_> = graph.node_indices().collect();
    let index_to_position: HashMap<NodeIndex, usize> = node_indices.iter()
        .enumerate()
        .map(|(i, &idx)| (idx, i))
        .collect();

    // Parallel computation of betweenness centrality
    let betweenness: Vec<f64> = node_indices.par_iter()
        .map(|&source| {
            calculate_single_source_betweenness(graph, source, &index_to_position, &node_indices)
        })
        .reduce(|| vec![0.0; node_count], |mut acc, partial| {
            for (i, &value) in partial.iter().enumerate() {
                acc[i] += value;
            }
            acc
        });

    // Apply normalization
    let final_betweenness = if normalized && node_count > 2 {
        let normalization_factor = if graph.is_directed() {
            (node_count - 1) * (node_count - 2)
        } else {
            (node_count - 1) * (node_count - 2) / 2
        } as f64;
        
        betweenness.into_iter()
            .map(|score| score / normalization_factor)
            .collect()
    } else {
        betweenness
    };

    // Create result mapping
    let mut scores = HashMap::new();
    for (i, &node_idx) in node_indices.iter().enumerate() {
        if let Some(node) = graph.node_weight(node_idx) {
            scores.insert(node.id.clone(), final_betweenness[i]);
        }
    }

    let stats = calculate_centrality_stats(&final_betweenness);
    let top_nodes = get_top_nodes(&scores, 10);

    Ok(CentralityAnalysisResult {
        scores,
        top_nodes,
        stats,
    })
}

fn calculate_single_source_betweenness(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    source: NodeIndex,
    index_to_position: &HashMap<NodeIndex, usize>,
    node_indices: &[NodeIndex]
) -> Vec<f64> {
    let node_count = node_indices.len();
    let mut betweenness = vec![0.0; node_count];
    
    if let Some(&s_pos) = index_to_position.get(&source) {
        let mut stack = Vec::new();
        let mut predecessors = vec![Vec::new(); node_count];
        let mut sigma = vec![0.0; node_count];
        let mut distance = vec![-1.0; node_count];
        let mut delta = vec![0.0; node_count];
        
        sigma[s_pos] = 1.0;
        distance[s_pos] = 0.0;
        let mut queue = VecDeque::new();
        queue.push_back(source);
        
        // Single-source shortest-path
        while let Some(v) = queue.pop_front() {
            if let Some(&v_pos) = index_to_position.get(&v) {
                stack.push(v);
                
                for edge in graph.edges_directed(v, Direction::Outgoing) {
                    let w = edge.target();
                    if let Some(&w_pos) = index_to_position.get(&w) {
                        if distance[w_pos] < 0.0 {
                            queue.push_back(w);
                            distance[w_pos] = distance[v_pos] + 1.0;
                        }
                        if distance[w_pos] == distance[v_pos] + 1.0 {
                            sigma[w_pos] += sigma[v_pos];
                            predecessors[w_pos].push(v_pos);
                        }
                    }
                }
            }
        }
        
        // Accumulation
        while let Some(w) = stack.pop() {
            if let Some(&w_pos) = index_to_position.get(&w) {
                for &v_pos in &predecessors[w_pos] {
                    if sigma[w_pos] != 0.0 {
                        delta[v_pos] += (sigma[v_pos] / sigma[w_pos]) * (1.0 + delta[w_pos]);
                    }
                }
                if w != source {
                    betweenness[w_pos] += delta[w_pos];
                }
            }
        }
    }
    
    betweenness
}