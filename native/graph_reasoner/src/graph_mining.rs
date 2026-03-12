use crate::*;
use petgraph::prelude::*;
use std::collections::{HashMap, HashSet, VecDeque, BinaryHeap};
use rayon::prelude::*;
use serde_json::Value;
use std::cmp::Reverse;

pub struct GraphMiner {
    min_pattern_size: usize,
    max_pattern_size: usize,
    min_support_threshold: f64,
    max_mining_time_ms: u64,
    use_parallel_mining: bool,
    pattern_pruning_enabled: bool,
}

#[derive(Debug, Clone)]
pub struct MinedPattern {
    pub pattern_id: String,
    pub pattern_type: String,
    pub nodes: Vec<String>,
    pub edges: Vec<String>,
    pub support: f64,
    pub confidence: f64,
    pub lift: f64,
    pub interestingness: f64,
    pub occurrences: Vec<PatternOccurrence>,
}

#[derive(Debug, Clone)]
pub struct PatternOccurrence {
    pub occurrence_id: String,
    pub matched_nodes: HashMap<String, String>,
    pub matched_edges: HashMap<String, String>,
    pub context_score: f64,
}

#[derive(Debug, Clone)]
pub struct FrequentSubgraph {
    pub subgraph_id: String,
    pub nodes: Vec<NodeIndex>,
    pub edges: Vec<EdgeIndex>,
    pub frequency: usize,
    pub density: f64,
    pub centrality_score: f64,
}

#[derive(Debug, Clone)]
pub struct GraphMotif {
    pub motif_id: String,
    pub motif_type: String,
    pub size: usize,
    pub frequency: usize,
    pub significance: f64,
    pub z_score: f64,
    pub instances: Vec<MotifInstance>,
}

#[derive(Debug, Clone)]
pub struct MotifInstance {
    pub instance_id: String,
    pub nodes: Vec<String>,
    pub edges: Vec<String>,
    pub local_importance: f64,
}

impl GraphMiner {
    pub fn new(options: &HashMap<String, Value>) -> Result<Self, RustlerError> {
        let min_pattern_size = options.get("min_pattern_size")
            .and_then(|v| v.as_u64())
            .map(|v| v as usize)
            .unwrap_or(3);

        let max_pattern_size = options.get("max_pattern_size")
            .and_then(|v| v.as_u64())
            .map(|v| v as usize)
            .unwrap_or(8);

        let min_support_threshold = options.get("min_support_threshold")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.1);

        let max_mining_time_ms = options.get("max_mining_time_ms")
            .and_then(|v| v.as_u64())
            .unwrap_or(30000);

        let use_parallel_mining = options.get("use_parallel_mining")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);

        let pattern_pruning_enabled = options.get("pattern_pruning_enabled")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);

        Ok(Self {
            min_pattern_size,
            max_pattern_size,
            min_support_threshold,
            max_mining_time_ms,
            use_parallel_mining,
            pattern_pruning_enabled,
        })
    }

    pub fn find_motifs(
        &self,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        options: &HashMap<String, Value>
    ) -> Result<Vec<SubgraphResult>, RustlerError> {
        let start_time = std::time::Instant::now();
        let mut results = Vec::new();

        let motif_types = options.get("motif_types")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().filter_map(|v| v.as_str()).collect::<Vec<_>>())
            .unwrap_or_else(|| vec!["triangle", "square", "star", "chain"]);

        for motif_type in motif_types {
            if start_time.elapsed().as_millis() as u64 > self.max_mining_time_ms {
                break;
            }

            let
 motifs = self.mine_specific_motif(graph, motif_type, options)?;
            for motif in motifs {
                results.push(SubgraphResult {
                    id: motif.motif_id,
                    nodes: motif.instances.iter()
                        .flat_map(|inst| inst.nodes.clone())
                        .collect::<HashSet<_>>()
                        .into_iter()
                        .collect(),
                    edges: motif.instances.iter()
                        .flat_map(|inst| inst.edges.clone())
                        .collect::<HashSet<_>>()
                        .into_iter()
                        .collect(),
                    pattern_type: format!("{}_motif", motif.motif_type),
                    significance_score: motif.significance,
                    properties: {
                        let mut props = HashMap::new();
                        props.insert("frequency".to_string(), Value::Number(motif.frequency.into()));
                        props.insert("z_score".to_string(),
                                   Value::Number(serde_json::Number::from_f64(motif.z_score).unwrap_or(serde_json::Number::from(0))));
                        props.insert("size".to_string(), Value::Number(motif.size.into()));
                        props
                    },
                });
            }
        }

        Ok(results)
    }

    pub fn find_cliques(
        &self,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        options: &HashMap<String, Value>
    ) -> Result<Vec<SubgraphResult>, RustlerError> {
        let min_clique_size = options.get("min_clique_size")
            .and_then(|v| v.as_u64())
            .map(|v| v as usize)
            .unwrap_or(self.min_pattern_size);

        let max_clique_size = options.get("max_clique_size")
            .and_then(|v| v.as_u64())
            .map(|v| v as usize)
            .unwrap_or(self.max_pattern_size);

        let cliques = self.find_maximal_cliques(graph, min_clique_size, max_clique_size)?;
        let mut results = Vec::new();

        for (clique_id, clique) in cliques.into_iter().enumerate() {
            let node_names: Vec<String> = clique.nodes.iter()
                .filter_map(|&idx| graph.node_weight(idx))
                .map(|node| node.id.clone())
                .collect();

            let edge_names: Vec<String> = clique.edges.iter()
                .filter_map(|&idx| graph.edge_weight(idx))
                .map(|edge| edge.id.clone())
                .collect();

            results.push(SubgraphResult {
                id: format!("clique_{}", clique_id),
                nodes: node_names,
                edges: edge_names,
                pattern_type: "clique".to_string(),
                significance_score: clique.density * clique.centrality_score,
                properties: {
                    let mut props = HashMap::new();
                    props.insert("density".to_string(),
                               Value::Number(serde_json::Number::from_f64(clique.density).unwrap_or(serde_json::Number::from(0))));
                    props.insert("frequency".to_string(), Value::Number(clique.frequency.into()));
                    props
                },
            });
        }

        Ok(results)
    }

    pub fn find_bridges(
        &self,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        options: &HashMap<String, Value>
    ) -> Result<Vec<SubgraphResult>, RustlerError> {
        let bridge_importance_threshold = options.get("importance_threshold")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.5);

        let bridges = self.find_bridge_edges(graph)?;
        let mut results = Vec::new();

        for (bridge_id, bridge_edge) in bridges.into_iter().enumerate() {
            if let Some(edge) = graph.edge_weight(bridge_edge) {
                let importance = self.calculate_bridge_importance(graph, bridge_edge);

                if importance >= bridge_importance_threshold {
                    let source_node = graph.node_weight(graph.edge_endpoints(bridge_edge).unwrap().0)
                        .map(|n| n.id.clone())
                        .unwrap_or_default();
                    let target_node = graph.node_weight(graph.edge_endpoints(bridge_edge).unwrap().1)
                        .map(|n| n.id.clone())
                        .unwrap_or_default();

                    results.push(SubgraphResult {
                        id: format!("bridge_{}", bridge_id),
                        nodes: vec![source_node, target_node],
                        edges: vec![edge.id.clone()],
                        pattern_type: "bridge".to_string(),
                        significance_score: importance,
                        properties: {
                            let mut props = HashMap::new();
                            props.insert("bridge_importance".to_string(),
                                       Value::Number(serde_json::Number::from_f64(importance).unwrap_or(serde_json::Number::from(0))));
                            props.insert("edge_weight".to_string(),
                                       Value::Number(serde_json::Number::from_f64(edge.weight).unwrap_or(serde_json::Number::from(0))));
                            props
                        },
                    });
                }
            }
        }

        Ok(results)
    }

    pub fn find_articulation_points(
        &self,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        options: &HashMap<String, Value>
    ) -> Result<Vec<SubgraphResult>, RustlerError> {
        let min_importance = options.get("min_importance")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.3);

        let articulation_points = self.find_articulation_nodes(graph)?;
        let mut results = Vec::new();

        for (point_id, node_idx) in articulation_points.into_iter().enumerate() {
            if let Some(node) = graph.node_weight(node_idx) {
                let importance = self.calculate_articulation_importance(graph, node_idx);

                if importance >= min_importance {
                    let connected_edges: Vec<String> = graph.edges(node_idx)
                        .map(|edge| edge.weight().id.clone())
                        .collect();

                    results.push(SubgraphResult {
                        id: format!("articulation_point_{}", point_id),
                        nodes: vec![node.id.clone()],
                        edges: connected_edges,
                        pattern_type: "articulation_point".to_string(),
                        significance_score: importance,
                        properties: {
                            let mut props = HashMap::new();
                            props.insert("articulation_importance".to_string(),
                                       Value::Number(serde_json::Number::from_f64(importance).unwrap_or(serde_json::Number::from(0))));
                            props.insert("degree".to_string(),
                                       Value::Number(graph.edges(node_idx).count().into()));
                            props
                        },
                    });
                }
            }
        }

        Ok(results)
    }

    pub fn find_dense_subgraphs(
        &self,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        options: &HashMap<String, Value>
    ) -> Result<Vec<SubgraphResult>, RustlerError> {
        let min_density = options.get("min_density")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.6);

        let min_size = options.get("min_size")
            .and_then(|v| v.as_u64())
            .map(|v| v as usize)
            .unwrap_or(self.min_pattern_size);

        let dense_subgraphs = self.mine_dense_subgraphs(graph, min_density, min_size)?;
        let mut results = Vec::new();

        for (subgraph_id, subgraph) in dense_subgraphs.into_iter().enumerate() {
            let node_names: Vec<String> = subgraph.nodes.iter()
                .filter_map(|&idx| graph.node_weight(idx))
                .map(|node| node.id.clone())
                .collect();

            let edge_names: Vec<String> = subgraph.edges.iter()
                .filter_map(|&idx| graph.edge_weight(idx))
                .map(|edge| edge.id.clone())
                .collect();

            results.push(SubgraphResult {
                id: format!("dense_subgraph_{}", subgraph_id),
                nodes: node_names,
                edges: edge_names,
                pattern_type: "dense_subgraph".to_string(),
                significance_score: subgraph.density * (subgraph.nodes.len() as f64 / graph.node_count() as f64),
                properties: {
                    let mut props = HashMap::new();
                    props.insert("density".to_string(),
                               Value::Number(serde_json::Number::from_f64(subgraph.density).unwrap_or(serde_json::Number::from(0))));
                    props.insert("size".to_string(), Value::Number(subgraph.nodes.len().into()));
                    props.insert("centrality_score".to_string(),
                               Value::Number(serde_json::Number::from_f64(subgraph.centrality_score).unwrap_or(serde_json::Number::from(0))));
                    props
                },
            });
        }

        Ok(results)
    }

    fn mine_specific_motif(
        &self,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        motif_type: &str,
        _options: &HashMap<String, Value>
    ) -> Result<Vec<GraphMotif>, RustlerError> {
        let mut motifs = Vec::new();

        match motif_type {
            "triangle" => {
                let triangles = self.find_triangle_motifs(graph)?;
                motifs.extend(triangles);
            }
            "square" => {
                let squares = self.find_square_motifs(graph)?;
                motifs.extend(squares);
            }
            "star" => {
                let stars = self.find_star_motifs(graph)?;
                motifs.extend(stars);
            }
            "chain" => {
                let chains = self.find_chain_motifs(graph)?;
                motifs.extend(chains);
            }
            _ => {}
        }

        Ok(motifs)
    }

    fn find_triangle_motifs(&self, graph: &Graph<GraphNode, GraphEdge, Directed>) -> Result<Vec<GraphMotif>, RustlerError> {
        let mut triangles = Vec::new();
        let node_indices: Vec<_> = graph.node_indices().collect();
        let mut triangle_count = 0;

        for i in 0..node_indices.len() {
            for j in (i + 1)..node_indices.len() {
                for k in (j + 1)..node_indices.len() {
                    let nodes = [node_indices[i], node_indices[j], node_indices[k]];

                    if self.forms_triangle(graph, &nodes) {
                        triangle_count += 1;

                        let node_names: Vec<String> = nodes.iter()
                            .filter_map(|&idx| graph.node_weight(idx))
                            .map(|node| node.id.clone())
                            .collect();

                        let edge_names = self.get_triangle_edges(graph, &nodes);

                        
                        if triangle_count == 1 {
                            triangles.push(GraphMotif {
                                motif_id: "triangle_motif".to_string(),
                                motif_type: "triangle".to_string(),
                                size: 3,
                                frequency: 0,
                                significance: 0.0,
                                z_score: 0.0,
                                instances: Vec::new(),
                            });
                        }

                        if let Some(motif) = triangles.last_mut() {
                            motif.frequency += 1;
                            motif.instances.push(MotifInstance {
                                instance_id: format!("triangle_instance_{}", motif.instances.len()),
                                nodes: node_names,
                                edges: edge_names,
                                local_importance: 1.0,
                            });
                        }
                    }
                }
            }
        }

        // Calculate significance
        for motif in &mut triangles {
            motif.significance = self.calculate_motif_significance(graph, motif);
            motif.z_score = self.calculate_z_score(graph, motif);
        }

        Ok(triangles)
    }

    fn find_square_motifs(&self, graph: &Graph<GraphNode, GraphEdge, Directed>) -> Result<Vec<GraphMotif>, RustlerError> {
        // Simplified implementation - similar pattern to triangles but for 4-cycles
        Ok(Vec::new())
    }

    fn find_star_motifs(&self, graph: &Graph<GraphNode, GraphEdge, Directed>) -> Result<Vec<GraphMotif>, RustlerError> {
        let mut stars = Vec::new();
        let mut star_instances = Vec::new();

        for center_node in graph.node_indices() {
            let neighbors: Vec<_> = graph.neighbors(center_node).collect();
            
            if neighbors.len() >= 3 { // Minimum star size
                let center_name = graph.node_weight(center_node)
                    .map(|n| n.id.clone())
                    .unwrap_or_default();

                let neighbor_names: Vec<String> = neighbors.iter()
                    .filter_map(|&idx| graph.node_weight(idx))
                    .map(|node| node.id.clone())
                    .collect();

                let edge_names: Vec<String> = graph.edges(center_node)
                    .map(|edge| edge.weight().id.clone())
                    .collect();

                let mut nodes = vec![center_name];
                nodes.extend(neighbor_names);

                star_instances.push(MotifInstance {
                    instance_id: format!("star_instance_{}", star_instances.len()),
                    nodes,
                    edges: edge_names,
                    local_importance: neighbors.len() as f64 / graph.node_count() as f64,
                });
            }
        }

        if !star_instances.is_empty() {
            stars.push(GraphMotif {
                motif_id: "star_motif".to_string(),
                motif_type: "star".to_string(),
                size: 0, // Variable size
                frequency: star_instances.len(),
                significance: 0.8,
                z_score: 1.5,
                instances: star_instances,
            });
        }

        Ok(stars)
    }

    fn find_chain_motifs(&self, graph: &Graph<GraphNode, GraphEdge, Directed>) -> Result<Vec<GraphMotif>, RustlerError> {
        // Simplified implementation
        Ok(Vec::new())
    }

    fn find_maximal_cliques(
        &self,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        min_size: usize,
        max_size: usize
    ) -> Result<Vec<FrequentSubgraph>, RustlerError> {
        let mut cliques = Vec::new();
        let nodes: Vec<_> = graph.node_indices().collect();
        
        // Simplified clique detection
        for &center in &nodes {
            let neighbors: HashSet<NodeIndex> = graph.neighbors(center).collect();
            
            if neighbors.len() + 1 >= min_size && neighbors.len() + 1 <= max_size {
                let mut clique_nodes = vec![center];
                clique_nodes.extend(neighbors.iter().take(max_size - 1));
                
                let clique_edges: Vec<EdgeIndex> = clique_nodes.iter()
                    .flat_map(|&node| {
                        graph.edges(node)
                            .filter(|edge| clique_nodes.contains(&edge.target()))
                            .map(|edge| edge.id())
                    })
                    .collect();

                let density = self.calculate_subgraph_density(graph, &clique_nodes);
                
                cliques.push(FrequentSubgraph {
                    subgraph_id: format!("clique_{}", cliques.len()),
                    nodes: clique_nodes,
                    edges: clique_edges,
                    frequency: 1,
                    density,
                    centrality_score: 0.8,
                });
            }
        }

        Ok(cliques)
    }

    fn find_bridge_edges(&self, graph: &Graph<GraphNode, GraphEdge, Directed>) -> Result<Vec<EdgeIndex>, RustlerError> {
        let mut bridges = Vec::new();
        
        // Simplified bridge detection
        for edge_ref in graph.edge_references() {
            let edge_idx = edge_ref.id();
            let (source, target) = (edge_ref.source(), edge_ref.target());
            
            // Check if removing this edge would disconnect the graph
            if self.is_bridge_edge(graph, source, target, edge_idx) {
                bridges.push(edge_idx);
            }
        }

        Ok(bridges)
    }

    fn find_articulation_nodes(&self, graph: &Graph<GraphNode, GraphEdge, Directed>) -> Result<Vec<NodeIndex>, RustlerError> {
        let mut articulation_points = Vec::new();
        
        // Simplified articulation point detection
        for node in graph.node_indices() {
            if self.is_articulation_point(graph, node) {
                articulation_points.push(node);
            }
        }

        Ok(articulation_points)
    }

    fn mine_dense_subgraphs(
        &self,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        min_density: f64,
        min_size: usize
    ) -> Result<Vec<FrequentSubgraph>, RustlerError> {
        let mut dense_subgraphs = Vec::new();
        let nodes: Vec<_> = graph.node_indices().collect();

        // Simple density-based mining using expanding neighborhoods
        for &seed in &nodes {
            let subgraph = self.expand_dense_subgraph(graph, seed, min_density, min_size)?;
            if subgraph.nodes.len() >= min_size && subgraph.density >= min_density {
                dense_subgraphs.push(subgraph);
            }
        }

        Ok(dense_subgraphs)
    }

    fn expand_dense_subgraph(
        &self,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        seed: NodeIndex,
        min_density: f64,
        min_size: usize
    ) -> Result<FrequentSubgraph, RustlerError> {
        let mut subgraph_nodes = vec![seed];
        let mut candidates: Vec<NodeIndex> = graph.neighbors(seed).collect();
        
        while !candidates.is_empty() && subgraph_nodes.len() < self.max_pattern_size {
            let mut best_candidate = None;
            let mut best_density = 0.0;
            
            for &candidate in &candidates {
                let mut test_nodes = subgraph_nodes.clone();
                test_nodes.push(candidate);
                let test_density = self.calculate_subgraph_density(graph, &test_nodes);
                
                if test_density > best_density && test_density >= min_density {
                    best_density = test_density;
                    best_candidate = Some(candidate);
                }
            }
            
            if let Some(best) = best_candidate {
                subgraph_nodes.push(best);
                candidates.retain(|&x| x != best);
                
                // Add new candidates
                for neighbor in graph.neighbors(best) {
                    if !subgraph_nodes.contains(&neighbor) && !candidates.contains(&neighbor) {
                        candidates.push(neighbor);
                    }
                }
            } else {
                break;
            }
        }

        let subgraph_edges: Vec<EdgeIndex> = subgraph_nodes.iter()
            .flat_map(|&node| {
                graph.edges(node)
                    .filter(|edge| subgraph_nodes.contains(&edge.target()))
                    .map(|edge| edge.id())
            })
            .collect();

        let density = self.calculate_subgraph_density(graph, &subgraph_nodes);

        Ok(FrequentSubgraph {
            subgraph_id: format!("dense_subgraph_{}", subgraph_nodes.len()),
            nodes: subgraph_nodes,
            edges: subgraph_edges,
            frequency: 1,
            density,
            centrality_score: self.calculate_subgraph_centrality(graph, &subgraph_nodes),
        })
    }

    // Helper methods
    fn forms_triangle(&self, graph: &Graph<GraphNode, GraphEdge, Directed>, nodes: &[NodeIndex; 3]) -> bool {
        let [a, b, c] = *nodes;
        graph.find_edge(a, b).is_some() && 
        graph.find_edge(b, c).is_some() && 
        graph.find_edge(c, a).is_some()
    }

    fn get_triangle_edges(&self, graph: &Graph<GraphNode, GraphEdge, Directed>, nodes: &[NodeIndex; 3]) -> Vec<String> {
        let [a, b, c] = *nodes;
        let mut edges = Vec::new();
        
        if let Some(edge_ref) = graph.find_edge(a, b) {
            if let Some(edge) = graph.edge_weight(edge_ref) {
                edges.push(edge.id.clone());
            }
        }
        if let Some(edge_ref) = graph.find_edge(b, c) {
            if let Some(edge) = graph.edge_weight(edge_ref) {
                edges.push(edge.id.clone());
            }
        }
        if let Some(edge_ref) = graph.find_edge(c, a) {
            if let Some(edge) = graph.edge_weight(edge_ref) {
                edges.push(edge.id.clone());
            }
        }
        
        edges
    }

    fn calculate_subgraph_density(&self, graph: &Graph<GraphNode, GraphEdge, Directed>, nodes: &[NodeIndex]) -> f64 {
        if nodes.len() < 2 {
            return 1.0;
        }

        let node_set: HashSet<NodeIndex> = nodes.iter().copied().collect();
        let mut edge_count = 0;

        for &node in nodes {
            for edge in graph.edges(node) {
                if node_set.contains(&edge.target()) {
                    edge_count += 1;
                }
            }
        }

        let max_possible_edges = nodes.len() * (nodes.len() - 1);
        if max_possible_edges > 0 {
            edge_count as f64 / max_possible_edges as f64
        } else {
            0.0
        }
    }

    fn calculate_subgraph_centrality(&self, graph: &Graph<GraphNode, GraphEdge, Directed>, nodes: &[NodeIndex]) -> f64 {
        if nodes.is_empty() {
            return 0.0;
        }

        let total_degree: usize = nodes.iter()
            .map(|&node| graph.edges(node).count())
            .sum();

        total_degree as f64 / (nodes.len() * graph.node_count()).max(1) as f64
    }

    fn is_bridge_edge(&self, graph: &Graph<GraphNode, GraphEdge, Directed>, source: NodeIndex, target: NodeIndex, _edge: EdgeIndex) -> bool {
        // Simplified bridge detection - check if removing edge disconnects components
        let source_neighbors: HashSet<_> = graph.neighbors(source).collect();
        let target_neighbors: HashSet<_> = graph.neighbors(target).collect();
        
        // If source and target only connect through this edge, it's likely a bridge
        source_neighbors.intersection(&target_neighbors).count() <= 1
    }

    fn is_articulation_point(&self, graph: &Graph<GraphNode, GraphEdge, Directed>, node: NodeIndex) -> bool {
        // Simplified articulation point detection
        let degree = graph.edges(node).count();
        degree >= 2 && self.would_disconnect_graph(graph, node)
    }

    fn would_disconnect_graph(&self, _graph: &Graph<GraphNode, GraphEdge, Directed>, _node: NodeIndex) -> bool {
        // Simplified check - in practice would need proper connectivity analysis
        true
    }

    fn calculate_bridge_importance(&self, graph: &Graph<GraphNode, GraphEdge, Directed>, edge: EdgeIndex) -> f64 {
        if let Some(edge_weight) = graph.edge_weight(edge) {
            edge_weight.weight * edge_weight.confidence
        } else {
            0.0
        }
    }

    fn calculate_articulation_importance(&self, graph: &Graph<GraphNode, GraphEdge, Directed>, node: NodeIndex) -> f64 {
        let degree = graph.edges(node).count();
        let max_degree = graph.node_count().saturating_sub(1);
        
        if max_degree > 0 {
            degree as f64 / max_degree as f64
        } else {
            0.0
        }
    }

    fn calculate_motif_significance(&self, graph: &Graph<GraphNode, GraphEdge, Directed>, motif: &GraphMotif) -> f64 {
        let expected_frequency = self.calculate_expected_frequency(graph, motif);
        let observed_frequency = motif.frequency as f64;
        
        if expected_frequency > 0.0 {
            observed_frequency / expected_frequency
        } else {
            1.0
        }
    }

    fn calculate_expected_frequency(&self, graph: &Graph<GraphNode, GraphEdge, Directed>, motif: &GraphMotif) -> f64 {
        // Simplified expected frequency calculation
        let node_count = graph.node_count() as f64;
        let edge_probability = graph.edge_count() as f64 / (node_count * (node_count - 1.0));
        
        match motif.motif_type.as_str() {
            "triangle" => node_count * (node_count - 1.0) * (node_count - 2.0) / 6.0 * edge_probability.powi(3),
            "star" => node_count * edge_probability.powi(motif.size as i32 - 1),
            _ => 1.0,
        }
    }

    fn calculate_z_score(&self, graph: &Graph<GraphNode, GraphEdge, Directed>, motif: &GraphMotif) -> f64 {
        let expected = self.calculate_expected_frequency(graph, motif);
        let observed = motif.frequency as f64;
        let variance = expected * 0.5; // Simplified variance calculation
        
        if variance > 0.0 {
            (observed - expected) / variance.sqrt()
        } else {
            0.0
        }
    }
}