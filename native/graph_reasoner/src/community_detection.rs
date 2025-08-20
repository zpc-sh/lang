use crate::*;
use petgraph::prelude::*;
use std::collections::{HashMap, HashSet, VecDeque};
use rayon::prelude::*;
use rand::prelude::*;
use rand::rngs::SmallRng;
use std::cmp::Ordering;

pub struct CommunityDetectionResult {
    pub communities: Vec<Community>,
    pub modularity: f64,
}

#[derive(Clone, Debug)]
pub struct CommunityState {
    node_to_community: HashMap<NodeIndex, usize>,
    community_sizes: Vec<usize>,
    community_internal_edges: Vec<u32>,
    community_external_edges: Vec<u32>,
    total_edges: usize,
}

pub fn detect_communities_louvain(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    options: &HashMap<String, serde_json::Value>
) -> Result<CommunityDetectionResult, RustlerError> {
    let resolution = options.get("resolution")
        .and_then(|v| v.as_f64())
        .unwrap_or(1.0);
    
    let max_iterations = options.get("max_iterations")
        .and_then(|v| v.as_u64())
        .map(|v| v as usize)
        .unwrap_or(100);
    
    let tolerance = options.get("tolerance")
        .and_then(|v| v.as_f64())
        .unwrap_or(1e-7);
    
    let random_seed = options.get("random_seed")
        .and_then(|v| v.as_u64())
        .unwrap_or(42);

    let node_count = graph.node_count();
    if node_count == 0 {
        return Ok(CommunityDetectionResult {
            communities: Vec::new(),
            modularity: 0.0,
        });
    }

    let node_indices: Vec<_> = graph.node_indices().collect();
    let mut rng = SmallRng::seed_from_u64(random_seed);
    
    // Initialize each node in its own community
    let mut community_state = initialize_communities(graph, &node_indices);
    let mut best_modularity = calculate_modularity(graph, &community_state, resolution);
    let mut improved = true;
    let mut iteration = 0;

    while improved && iteration < max_iterations {
        improved = false;
        iteration += 1;
        
        // Randomize node order for processing
        let mut shuffled_nodes = node_indices.clone();
        shuffled_nodes.shuffle(&mut rng);
        
        for &node in &shuffled_nodes {
            let current_community = community_state.node_to_community[&node];
            let mut best_community = current_community;
            let mut best_gain = 0.0;
            
            // Try moving node to neighboring communities
            let neighboring_communities = get_neighboring_communities(graph, node, &community_state);
            
            for &neighbor_community in &neighboring_communities {
                if neighbor_community != current_community {
                    let gain = calculate_modularity_gain(
                        graph, 
                        node, 
                        current_community,
                        neighbor_community, 
                        &community_state,
                        resolution
                    );
                    
                    if gain > best_gain + tolerance {
                        best_gain = gain;
                        best_community = neighbor_community;
                    }
                }
            }
            
            // Move node if beneficial
            if best_community != current_community {
                move_node_to_community(&mut community_state, node, current_community, best_community);
                improved = true;
            }
        }
        
        // Calculate new modularity
        let new_modularity = calculate_modularity(graph, &community_state, resolution);
        if new_modularity > best_modularity {
            best_modularity = new_modularity;
        }
        
        // Check for convergence
        if !improved {
            break;
        }
    }
    
    // Create final communities
    let communities = build_community_results(graph, &community_state, &node_indices);
    
    Ok(CommunityDetectionResult {
        communities,
        modularity: best_modularity,
    })
}

pub fn detect_communities_leiden(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    options: &HashMap<String, serde_json::Value>
) -> Result<CommunityDetectionResult, RustlerError> {
    let resolution = options.get("resolution")
        .and_then(|v| v.as_f64())
        .unwrap_or(1.0);
    
    let max_iterations = options.get("max_iterations")
        .and_then(|v| v.as_u64())
        .map(|v| v as usize)
        .unwrap_or(100);
    
    let random_seed = options.get("random_seed")
        .and_then(|v| v.as_u64())
        .unwrap_or(42);

    let node_count = graph.node_count();
    if node_count == 0 {
        return Ok(CommunityDetectionResult {
            communities: Vec::new(),
            modularity: 0.0,
        });
    }

    let node_indices: Vec<_> = graph.node_indices().collect();
    let mut rng = SmallRng::seed_from_u64(random_seed);
    let mut community_state = initialize_communities(graph, &node_indices);
    let mut best_modularity = calculate_modularity(graph, &community_state, resolution);
    
    for iteration in 0..max_iterations {
        // Phase 1: Local moving (similar to Louvain)
        let mut improved = true;
        while improved {
            improved = false;
            let mut shuffled_nodes = node_indices.clone();
            shuffled_nodes.shuffle(&mut rng);
            
            for &node in &shuffled_nodes {
                if move_node_to_best_community(graph, node, &mut community_state, resolution) {
                    improved = true;
                }
            }
        }
        
        // Phase 2: Refinement step (key difference from Louvain)
        refined_local_moving(graph, &mut community_state, resolution, &mut rng);
        
        // Phase 3: Aggregation - create new graph with communities as super-nodes
        let aggregated_graph = aggregate_graph(graph, &community_state);
        if aggregated_graph.node_count() == graph.node_count() {
            // No more aggregation possible
            break;
        }
        
        // Continue with aggregated graph
        // For simplicity, we'll break here in this implementation
        break;
    }
    
    let final_modularity = calculate_modularity(graph, &community_state, resolution);
    let communities = build_community_results(graph, &community_state, &node_indices);
    
    Ok(CommunityDetectionResult {
        communities,
        modularity: final_modularity,
    })
}

pub fn detect_communities_modularity(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    options: &HashMap<String, serde_json::Value>
) -> Result<CommunityDetectionResult, RustlerError> {
    let max_communities = options.get("max_communities")
        .and_then(|v| v.as_u64())
        .map(|v| v as usize)
        .unwrap_or(graph.node_count());
    
    let min_community_size = options.get("min_community_size")
        .and_then(|v| v.as_u64())
        .map(|v| v as usize)
        .unwrap_or(1);

    let node_count = graph.node_count();
    if node_count == 0 {
        return Ok(CommunityDetectionResult {
            communities: Vec::new(),
            modularity: 0.0,
        });
    }

    let node_indices: Vec<_> = graph.node_indices().collect();
    
    // Greedy modularity optimization
    let mut best_partition = initialize_communities(graph, &node_indices);
    let mut best_modularity = calculate_modularity(graph, &best_partition, 1.0);
    
    // Try different community configurations
    for target_communities in 2..=max_communities.min(node_count) {
        let mut current_partition = merge_communities_to_target(
            &best_partition, 
            target_communities, 
            min_community_size
        );
        
        // Optimize this partition
        let mut improved = true;
        while improved {
            improved = false;
            
            for &node in &node_indices {
                if move_node_to_best_community(graph, node, &mut current_partition, 1.0) {
                    improved = true;
                }
            }
        }
        
        let current_modularity = calculate_modularity(graph, &current_partition, 1.0);
        if current_modularity > best_modularity {
            best_modularity = current_modularity;
            best_partition = current_partition;
        }
    }
    
    let communities = build_community_results(graph, &best_partition, &node_indices);
    
    Ok(CommunityDetectionResult {
        communities,
        modularity: best_modularity,
    })
}

pub fn detect_communities_spectral(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    options: &HashMap<String, serde_json::Value>
) -> Result<CommunityDetectionResult, RustlerError> {
    let num_communities = options.get("num_communities")
        .and_then(|v| v.as_u64())
        .map(|v| v as usize)
        .unwrap_or(2);
    
    let max_iterations = options.get("max_iterations")
        .and_then(|v| v.as_u64())
        .map(|v| v as usize)
        .unwrap_or(100);

    let node_count = graph.node_count();
    if node_count == 0 {
        return Ok(CommunityDetectionResult {
            communities: Vec::new(),
            modularity: 0.0,
        });
    }

    let node_indices: Vec<_> = graph.node_indices().collect();
    
    // For this implementation, we'll use a simplified spectral approach
    // based on graph connectivity and edge weights
    let mut community_assignment = spectral_clustering_simplified(graph, num_communities, &node_indices)?;
    
    // Optimize the assignment using local search
    let mut community_state = CommunityState {
        node_to_community: community_assignment,
        community_sizes: vec![0; num_communities],
        community_internal_edges: vec![0; num_communities],
        community_external_edges: vec![0; num_communities],
        total_edges: graph.edge_count(),
    };
    
    // Recalculate community statistics
    recalculate_community_stats(graph, &mut community_state);
    
    // Local optimization
    for _ in 0..max_iterations {
        let mut improved = false;
        
        for &node in &node_indices {
            if move_node_to_best_community(graph, node, &mut community_state, 1.0) {
                improved = true;
            }
        }
        
        if !improved {
            break;
        }
    }
    
    let final_modularity = calculate_modularity(graph, &community_state, 1.0);
    let communities = build_community_results(graph, &community_state, &node_indices);
    
    Ok(CommunityDetectionResult {
        communities,
        modularity: final_modularity,
    })
}

// Helper functions

fn initialize_communities(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    node_indices: &[NodeIndex]
) -> CommunityState {
    let node_count = node_indices.len();
    let mut node_to_community = HashMap::new();
    
    // Each node starts in its own community
    for (i, &node_idx) in node_indices.iter().enumerate() {
        node_to_community.insert(node_idx, i);
    }
    
    let mut state = CommunityState {
        node_to_community,
        community_sizes: vec![1; node_count],
        community_internal_edges: vec![0; node_count],
        community_external_edges: vec![0; node_count],
        total_edges: graph.edge_count(),
    };
    
    recalculate_community_stats(graph, &mut state);
    state
}

fn calculate_modularity(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    state: &CommunityState,
    resolution: f64
) -> f64 {
    if graph.edge_count() == 0 {
        return 0.0;
    }
    
    let total_edges = graph.edge_count() as f64;
    let mut modularity = 0.0;
    
    // Calculate degree for each community
    let mut community_degrees: HashMap<usize, f64> = HashMap::new();
    
    for &node in graph.node_indices().collect::<Vec<_>>().iter() {
        let community = state.node_to_community[&node];
        let degree = graph.edges(node).count() as f64;
        *community_degrees.entry(community).or_insert(0.0) += degree;
    }
    
    // Calculate internal edges for each community
    let mut community_internal: HashMap<usize, f64> = HashMap::new();
    
    for edge in graph.edge_references() {
        let source_community = state.node_to_community[&edge.source()];
        let target_community = state.node_to_community[&edge.target()];
        
        if source_community == target_community {
            *community_internal.entry(source_community).or_insert(0.0) += edge.weight().weight;
        }
    }
    
    // Calculate modularity
    for (&community, &internal_edges) in community_internal.iter() {
        let degree_sum = community_degrees.get(&community).unwrap_or(&0.0);
        let expected = (degree_sum * degree_sum) / (2.0 * total_edges);
        modularity += (internal_edges / total_edges) - resolution * (expected / total_edges);
    }
    
    modularity
}

fn calculate_modularity_gain(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    node: NodeIndex,
    from_community: usize,
    to_community: usize,
    state: &CommunityState,
    resolution: f64
) -> f64 {
    if from_community == to_community {
        return 0.0;
    }
    
    let total_edges = graph.edge_count() as f64;
    if total_edges == 0.0 {
        return 0.0;
    }
    
    // Calculate node's degree and connections to communities
    let node_degree = graph.edges(node).count() as f64;
    let mut connections_to_from = 0.0;
    let mut connections_to_to = 0.0;
    
    for edge in graph.edges(node) {
        let neighbor = edge.target();
        let neighbor_community = state.node_to_community[&neighbor];
        let weight = edge.weight().weight;
        
        if neighbor_community == from_community && neighbor != node {
            connections_to_from += weight;
        }
        if neighbor_community == to_community {
            connections_to_to += weight;
        }
    }
    
    // Calculate degree sums for communities
    let from_degree_sum: f64 = graph.node_indices()
        .filter(|&n| state.node_to_community[&n] == from_community)
        .map(|n| graph.edges(n).count() as f64)
        .sum();
    
    let to_degree_sum: f64 = graph.node_indices()
        .filter(|&n| state.node_to_community[&n] == to_community)
        .map(|n| graph.edges(n).count() as f64)
        .sum();
    
    // Calculate modularity change
    let delta_q = (connections_to_to - connections_to_from) / total_edges
        - resolution * node_degree * (to_degree_sum - from_degree_sum + node_degree) / (2.0 * total_edges * total_edges);
    
    delta_q
}

fn get_neighboring_communities(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    node: NodeIndex,
    state: &CommunityState
) -> Vec<usize> {
    let mut communities = HashSet::new();
    
    for edge in graph.edges(node) {
        let neighbor = edge.target();
        communities.insert(state.node_to_community[&neighbor]);
    }
    
    communities.into_iter().collect()
}

fn move_node_to_community(
    state: &mut CommunityState,
    node: NodeIndex,
    from_community: usize,
    to_community: usize
) {
    if from_community == to_community {
        return;
    }
    
    // Update node assignment
    state.node_to_community.insert(node, to_community);
    
    // Update community sizes
    if state.community_sizes[from_community] > 0 {
        state.community_sizes[from_community] -= 1;
    }
    state.community_sizes[to_community] += 1;
}

fn move_node_to_best_community(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    node: NodeIndex,
    state: &mut CommunityState,
    resolution: f64
) -> bool {
    let current_community = state.node_to_community[&node];
    let neighboring_communities = get_neighboring_communities(graph, node, state);
    
    let mut best_community = current_community;
    let mut best_gain = 0.0;
    
    for &community in &neighboring_communities {
        if community != current_community {
            let gain = calculate_modularity_gain(
                graph, node, current_community, community, state, resolution
            );
            
            if gain > best_gain {
                best_gain = gain;
                best_community = community;
            }
        }
    }
    
    if best_community != current_community {
        move_node_to_community(state, node, current_community, best_community);
        return true;
    }
    
    false
}

fn refined_local_moving(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    state: &mut CommunityState,
    resolution: f64,
    rng: &mut SmallRng
) {
    let node_indices: Vec<_> = graph.node_indices().collect();
    let mut queue: VecDeque<NodeIndex> = VecDeque::new();
    let mut in_queue: HashSet<NodeIndex> = HashSet::new();
    
    // Add all nodes to queue initially
    for &node in &node_indices {
        queue.push_back(node);
        in_queue.insert(node);
    }
    
    while let Some(node) = queue.pop_front() {
        in_queue.remove(&node);
        
        if move_node_to_best_community(graph, node, state, resolution) {
            // Add neighbors back to queue if they're not already there
            for edge in graph.edges(node) {
                let neighbor = edge.target();
                if !in_queue.contains(&neighbor) {
                    queue.push_back(neighbor);
                    in_queue.insert(neighbor);
                }
            }
        }
    }
}

fn aggregate_graph(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    state: &CommunityState
) -> Graph<GraphNode, GraphEdge, Directed> {
    // This is a simplified aggregation
    // In a full implementation, you would create a new graph where each community
    // becomes a single node, and edges between communities are aggregated
    graph.clone()
}

fn merge_communities_to_target(
    state: &CommunityState,
    target_communities: usize,
    min_size: usize
) -> CommunityState {
    // Simplified merging - in practice, you'd use more sophisticated algorithms
    let mut new_state = state.clone();
    
    // Find communities that are too small and merge them
    let mut community_sizes: Vec<(usize, usize)> = state.community_sizes
        .iter()
        .enumerate()
        .map(|(i, &size)| (i, size))
        .filter(|(_, size)| *size > 0)
        .collect();
    
    community_sizes.sort_by_key(|(_, size)| *size);
    
    // Merge small communities with larger ones
    let mut community_mapping = HashMap::new();
    let mut next_community_id = 0;
    
    for (community_id, size) in community_sizes {
        if size >= min_size && next_community_id < target_communities {
            community_mapping.insert(community_id, next_community_id);
            next_community_id += 1;
        } else {
            // Merge with the largest community
            let target = if next_community_id > 0 { next_community_id - 1 } else { 0 };
            community_mapping.insert(community_id, target);
        }
    }
    
    // Update node assignments
    for (&node, &old_community) in &state.node_to_community {
        if let Some(&new_community) = community_mapping.get(&old_community) {
            new_state.node_to_community.insert(node, new_community);
        }
    }
    
    new_state
}

fn spectral_clustering_simplified(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    num_communities: usize,
    node_indices: &[NodeIndex]
) -> Result<HashMap<NodeIndex, usize>, RustlerError> {
    // Simplified spectral clustering based on connectivity patterns
    let mut assignment = HashMap::new();
    let node_count = node_indices.len();
    
    if num_communities >= node_count {
        // Each node gets its own community
        for (i, &node) in node_indices.iter().enumerate() {
            assignment.insert(node, i);
        }
        return Ok(assignment);
    }
    
    // Calculate simple connectivity-based assignment
    let nodes_per_community = node_count / num_communities;
    let mut community_id = 0;
    let mut nodes_in_current_community = 0;
    
    // Sort nodes by degree (simple heuristic)
    let mut nodes_with_degree: Vec<(NodeIndex, usize)> = node_indices.iter()
        .map(|&node| (node, graph.edges(node).count()))
        .collect();
    
    nodes_with_degree.sort_by_key(|(_, degree)| std::cmp::Reverse(*degree));
    
    for (node, _) in nodes_with_degree {
        assignment.insert(node, community_id);
        nodes_in_current_community += 1;
        
        if nodes_in_current_community >= nodes_per_community && community_id < num_communities - 1 {
            community_id += 1;
            nodes_in_current_community = 0;
        }
    }
    
    Ok(assignment)
}

fn recalculate_community_stats(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    state: &mut CommunityState
) {
    // Reset stats
    let num_communities = state.community_sizes.len();
    state.community_sizes.fill(0);
    state.community_internal_edges.fill(0);
    state.community_external_edges.fill(0);
    
    // Count community sizes
    for &community in state.node_to_community.values() {
        if community < num_communities {
            state.community_sizes[community] += 1;
        }
    }
    
    // Count internal and external edges
    for edge in graph.edge_references() {
        let source_community = state.node_to_community.get(&edge.source()).copied().unwrap_or(0);
        let target_community = state.node_to_community.get(&edge.target()).copied().unwrap_or(0);
        
        if source_community < num_communities && target_community < num_communities {
            if source_community == target_community {
                state.community_internal_edges[source_community] += 1;
            } else {
                state.community_external_edges[source_community] += 1;
                state.community_external_edges[target_community] += 1;
            }
        }
    }
}

fn build_community_results(
    graph: &Graph<GraphNode, GraphEdge, Directed>,
    state: &CommunityState,
    node_indices: &[NodeIndex]
) -> Vec<Community> {
    let mut communities = Vec::new();
    let mut community_nodes: HashMap<usize, Vec<String>> = HashMap::new();
    
    // Group nodes by community
    for &node_idx in node_indices {
        if let (Some(node), Some(&community)) = (
            graph.node_weight(node_idx),
            state.node_to_community.get(&node_idx)
        ) {
            community_nodes.entry(community)
                .or_insert_with(Vec::new)
                .push(node.id.clone());
        }
    }
    
    // Create community objects
    for (community_id, nodes) in community_nodes {
        if !nodes.is_empty() {
            let internal_edges = state.community_internal_edges.get(community_id).copied().unwrap_or(0);
            let external_edges = state.community_external_edges.get(community_id).copied().unwrap_or(0);
            let total_possible_internal = if nodes.len() > 1 {
                nodes.len() * (nodes.len() - 1) / 2
            } else {
                1
            };
            
            let density = internal_edges as f64 / total_possible_internal as f64;
            let centrality_score = internal_edges as f64 / (internal_edges + external_edges).max(1) as f64;
            
            communities.push(Community {
                id: format!("community_{}", community_id),
                nodes,
                internal_edges,
                external_edges,
                density,
                centrality_score,
            });
        }
    }
    
    communities
}