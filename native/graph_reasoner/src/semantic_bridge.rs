use crate::*;
use petgraph::prelude::*;
use std::collections::{HashMap, HashSet, VecDeque};
use rayon::prelude::*;
use serde_json::Value;
use regex::Regex;

pub struct SemanticBridge {
    similarity_threshold: f64,
    max_alignment_distance: usize,
    use_embedding_similarity: bool,
    text_preprocessing_enabled: bool,
    semantic_enrichment_enabled: bool,
}

pub struct TextGraphAlignment {
    pub aligned_pairs: Vec<AlignmentPair>,
    pub unaligned_text_spans: Vec<TextSpan>,
    pub unaligned_graph_nodes: Vec<String>,
    pub alignment_confidence: f64,
    pub semantic_coherence_score: f64,
}

#[derive(Debug, Clone)]
pub struct AlignmentPair {
    pub text_span: TextSpan,
    pub graph_node_id: String,
    pub alignment_type: AlignmentType,
    pub confidence: f64,
    pub semantic_features: Vec<String>,
}

#[derive(Debug, Clone)]
pub enum AlignmentType {
    ExactMatch,
    SemanticMatch,
    PartialMatch,
    InferredMatch,
    ContextualMatch,
}

pub struct GraphAugmentationResult {
    pub new_nodes: Vec<GraphNode>,
    pub new_edges: Vec<GraphEdge>,
    pub updated_nodes: Vec<GraphNode>,
    pub updated_edges: Vec<GraphEdge>,
    pub semantic_annotations: Vec<SemanticAnnotation>,
    pub augmentation_confidence: f64,
}

#[derive(Debug, Clone)]
pub struct SemanticAnnotation {
    pub annotation_id: String,
    pub target_type: String, // "node" or "edge"
    pub target_id: String,
    pub annotation_type: String,
    pub content: Value,
    pub confidence: f64,
    pub source_text: String,
}

pub struct TextGraphQueryResult {
    pub matching_subgraphs: Vec<SubgraphResult>,
    pub relevant_text_segments: Vec<TextSegment>,
    pub query_explanations: Vec<String>,
    pub semantic_connections: Vec<SemanticConnection>,
    pub query_confidence: f64,
}

#[derive(Debug, Clone)]
pub struct TextSegment {
    pub segment_id: String,
    pub text: String,
    pub start_offset: usize,
    pub end_offset: usize,
    pub semantic_type: String,
    pub relevance_score: f64,
    pub context_features: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct SemanticConnection {
    pub connection_id: String,
    pub text_element: String,
    pub graph_element: String,
    pub connection_type: String,
    pub strength: f64,
    pub evidence: Vec<String>,
}

impl SemanticBridge {
    pub fn new(options: &HashMap<String, Value>) -> Result<Self, RustlerError> {
        let similarity_threshold = options.get("similarity_threshold")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.7);

        let max_alignment_distance = options.get("max_alignment_distance")
            .and_then(|v| v.as_u64())
            .map(|v| v as usize)
            .unwrap_or(100);

        let use_embedding_similarity = options.get("use_embedding_similarity")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);

        let text_preprocessing_enabled = options.get("text_preprocessing_enabled")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);

        let semantic_enrichment_enabled = options.get("semantic_enrichment_enabled")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);

        Ok(Self {
            similarity_threshold,
            max_alignment_distance,
            use_embedding_similarity,
            text_preprocessing_enabled,
            semantic_enrichment_enabled,
        })
    }

    pub fn align_text_to_graph(
        &self,
        text_data: &[HashMap<String, Value>],
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        options: &HashMap<String, Value>
    ) -> Result<ReasoningResponse, RustlerError> {
        let mut reasoning_steps = Vec::new();
        reasoning_steps.push("Starting text-to-graph alignment".to_string());

        let mut aligned_nodes = Vec::new();
        let mut aligned_edges = Vec::new();
        let mut alignment_subgraphs = Vec::new();
        let mut total_confidence = 0.0;

        for (text_idx, text_item) in text_data.iter().enumerate() {
            if let Some(text_content) = text_item.get("text").and_then(|v| v.as_str()) {
                reasoning_steps.push(format!("Processing text segment {}", text_idx));

                let alignment = self.align_text_segment_to_graph(text_content, graph, options)?;
                
                // Extract nodes and edges from alignment
                for pair in &alignment.aligned_pairs {
                    if let Some(node) = self.find_graph_node_by_id(graph, &pair.graph_node_id) {
                        if !aligned_nodes.iter().any(|n: &GraphNode| n.id == node.id) {
                            aligned_nodes.push(node.clone());
                        }
                    }
                }

                // Create subgraph result for this alignment
                let subgraph = SubgraphResult {
                    id: format!("text_alignment_{}", text_idx),
                    nodes: alignment.aligned_pairs.iter()
                        .map(|pair| pair.graph_node_id.clone())
                        .collect(),
                    edges: Vec::new(),
                    pattern_type: "text_alignment".to_string(),
                    significance_score: alignment.alignment_confidence,
                    properties: {
                        let mut props = HashMap::new();
                        props.insert("text_content".to_string(), Value::String(text_content.to_string()));
                        props.insert("semantic_coherence".to_string(),
                                   Value::Number(serde_json::Number::from_f64(alignment.semantic_coherence_score).unwrap_or(serde_json::Number::from(0))));
                        props
                    },
                };
                alignment_subgraphs.push(subgraph);
                total_confidence += alignment.alignment_confidence;
            }
        }

        let final_confidence = if text_data.is_empty() {
            0.0
        } else {
            total_confidence / text_data.len() as f64
        };

        reasoning_steps.push(format!("Completed alignment with {} nodes and {} subgraphs",
                                   aligned_nodes.len(), alignment_subgraphs.len()));

        let mut metadata = HashMap::new();
        metadata.insert("alignment_type".to_string(), Value::String("text_to_graph".to_string()));
        metadata.insert("text_segments_processed".to_string(), Value::Number(text_data.len().into()));

        Ok(ReasoningResponse {
            nodes: aligned_nodes,
            edges: aligned_edges,
            paths: Vec::new(),
            subgraphs: alignment_subgraphs,
            reasoning_steps,
            confidence: final_confidence,
            metadata,
        })
    }

    pub fn augment_graph_with_text(
        &self,
        text_data: &[HashMap<String, Value>],
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        options: &HashMap<String, Value>
    ) -> Result<ReasoningResponse, RustlerError> {
        let mut reasoning_steps = Vec::new();
        reasoning_steps.push("Starting graph augmentation with text data".to_string());

        let mut new_nodes = Vec::new();
        let mut new_edges = Vec::new();
        let mut updated_nodes = Vec::new();
        let mut node_id_counter = 0;
        let mut edge_id_counter = 0;

        for (text_idx, text_item) in text_data.iter().enumerate() {
            if let Some(text_content) = text_item.get("text").and_then(|v| v.as_str()) {
                reasoning_steps.push(format!("Augmenting graph with text segment {}", text_idx));

                // Extract entities and relationships from text
                let entities = self.extract_entities_from_text(text_content)?;
                let relationships = self.extract_relationships_from_text(text_content)?;

                // Create new nodes for entities not in graph
                for entity in entities {
                    if !self.entity_exists_in_graph(graph, &entity) {
                        node_id_counter += 1;
                        let new_node = self.create_node_from_entity(entity, node_id_counter)?;
                        new_nodes.push(new_node);
                    } else {
                        // Update existing node with additional information
                        if let Some(existing_node) = self.find_matching_node(graph, &entity) {
                            let mut updated_node = existing_node.clone();
                            self.enrich_node_with_entity(&mut updated_node, &entity);
                            updated_nodes.push(updated_node);
                        }
                    }
                }

                // Create new edges for relationships
                for relationship in relationships {
                    edge_id_counter += 1;
                    if let Some(edge) = self.create_edge_from_relationship(relationship, edge_id_counter, graph)? {
                        new_edges.push(edge);
                    }
                }
            }
        }

        let confidence = self.calculate_augmentation_confidence(&new_nodes, &new_edges, &updated_nodes);

        reasoning_steps.push(format!("Created {} new nodes, {} new edges, updated {} nodes",
                                   new_nodes.len(), new_edges.len(), updated_nodes.len()));

        let mut all_nodes = new_nodes;
        all_nodes.extend(updated_nodes);

        let mut metadata = HashMap::new();
        metadata.insert("augmentation_type".to_string(), Value::String("text_to_graph".to_string()));
        metadata.insert("text_segments_processed".to_string(), Value::Number(text_data.len().into()));
        metadata.insert("new_nodes_created".to_string(), Value::Number(all_nodes.len().into()));
        metadata.insert("new_edges_created".to_string(), Value::Number(new_edges.len().into()));

        Ok(ReasoningResponse {
            nodes: all_nodes,
            edges: new_edges,
            paths: Vec::new(),
            subgraphs: Vec::new(),
            reasoning_steps,
            confidence,
            metadata,
        })
    }

    pub fn query_graph_with_text(
        &self,
        text_data: &[HashMap<String, Value>],
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        options: &HashMap<String, Value>
    ) -> Result<ReasoningResponse, RustlerError> {
        let mut reasoning_steps = Vec::new();
        reasoning_steps.push("Starting text-based graph querying".to_string());

        let mut result_nodes = Vec::new();
        let mut result_edges = Vec::new();
        let mut result_subgraphs = Vec::new();
        let mut query_paths = Vec::new();

        for (text_idx, text_item) in text_data.iter().enumerate() {
            if let Some(query_text) = text_item.get("query").and_then(|v| v.as_str()) {
                reasoning_steps.push(format!("Processing text query {}: {}", text_idx, query_text));

                // Parse query intent and extract key terms
                let query_terms = self.extract_query_terms(query_text);
                let query_type = self.determine_query_type(query_text);

                reasoning_steps.push(format!("Detected query type: {}, terms: {:?}", query_type, query_terms));

                match query_type.as_str() {
                    "find_nodes" => {
                        let nodes = self.find_nodes_by_text_query(graph, &query_terms, options)?;
                        result_nodes.extend(nodes);
                    }
                    "find_paths" => {
                        let paths = self.find_paths_by_text_query(graph, &query_terms, options)?;
                        query_paths.extend(paths);
                    }
                    "find_subgraphs" => {
                        let subgraphs = self.find_subgraphs_by_text_query(graph, &query_terms, options)?;
                        result_subgraphs.extend(subgraphs);
                    }
                    "semantic_search" => {
                        let (nodes, edges) = self.semantic_search_graph(graph, &query_terms, options)?;
                        result_nodes.extend(nodes);
                        result_edges.extend(edges);
                    }
                    _ => {
                        reasoning_steps.push(format!("Unknown query type: {}", query_type));
                    }
                }
            }
        }

        let confidence = self.calculate_query_confidence(&result_nodes, &result_edges, &result_subgraphs);

        reasoning_steps.push(format!("Found {} nodes, {} edges, {} subgraphs, {} paths",
                                   result_nodes.len(), result_edges.len(), result_subgraphs.len(), query_paths.len()));

        let mut metadata = HashMap::new();
        metadata.insert("query_type".to_string(), Value::String("text_based".to_string()));
        metadata.insert("queries_processed".to_string(), Value::Number(text_data.len().into()));

        Ok(ReasoningResponse {
            nodes: result_nodes,
            edges: result_edges,
            paths: query_paths,
            subgraphs: result_subgraphs,
            reasoning_steps,
            confidence,
            metadata,
        })
    }

    pub fn synthesize_text_graph_insights(
        &self,
        text_data: &[HashMap<String, Value>],
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        options: &HashMap<String, Value>
    ) -> Result<ReasoningResponse, RustlerError> {
        let mut reasoning_steps = Vec::new();
        reasoning_steps.push("Starting text-graph synthesis for insights".to_string());

        // Combine alignment, augmentation, and querying for comprehensive insights
        let alignment_result = self.align_text_to_graph(text_data, graph, options)?;
        let augmentation_result = self.augment_graph_with_text(text_data, graph, options)?;
        let query_result = self.query_graph_with_text(text_data, graph, options)?;

        // Synthesize results
        let mut synthesis_nodes = alignment_result.nodes;
        synthesis_nodes.extend(augmentation_result.nodes);
        synthesis_nodes.extend(query_result.nodes);

        let mut synthesis_edges = alignment_result.edges;
        synthesis_edges.extend(augmentation_result.edges);
        synthesis_edges.extend(query_result.edges);

        let mut synthesis_subgraphs = alignment_result.subgraphs;
        synthesis_subgraphs.extend(augmentation_result.subgraphs);
        synthesis_subgraphs.extend(query_result.subgraphs);

        let mut synthesis_paths = query_result.paths;

        // Deduplicate results
        synthesis_nodes = self.deduplicate_nodes(synthesis_nodes);
        synthesis_edges = self.deduplicate_edges(synthesis_edges);

        let combined_confidence = (alignment_result.confidence + 
                                 augmentation_result.confidence + 
                                 query_result.confidence) / 3.0;

        reasoning_steps.push("Completed text-graph synthesis".to_string());
        reasoning_steps.extend(alignment_result.reasoning_steps);
        reasoning_steps.extend(augmentation_result.reasoning_steps);
        reasoning_steps.extend(query_result.reasoning_steps);

        let mut metadata = HashMap::new();
        metadata.insert("synthesis_type".to_string(), Value::String("comprehensive".to_string()));
        metadata.insert("total_nodes".to_string(), Value::Number(synthesis_nodes.len().into()));
        metadata.insert("total_edges".to_string(), Value::Number(synthesis_edges.len().into()));
        metadata.insert("total_subgraphs".to_string(), Value::Number(synthesis_subgraphs.len().into()));

        Ok(ReasoningResponse {
            nodes: synthesis_nodes,
            edges: synthesis_edges,
            paths: synthesis_paths,
            subgraphs: synthesis_subgraphs,
            reasoning_steps,
            confidence: combined_confidence,
            metadata,
        })
    }

    // Helper methods
    fn align_text_segment_to_graph(
        &self,
        text: &str,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        _options: &HashMap<String, Value>
    ) -> Result<TextGraphAlignment, RustlerError> {
        let mut aligned_pairs = Vec::new();
        let mut alignment_confidence = 0.0;
        let mut matches_found = 0;

        // Simple word-based alignment
        let words: Vec<&str> = text.split_whitespace().collect();
        
        for (word_idx, word) in words.iter().enumerate() {
            for node in graph.node_weights() {
                let similarity = self.calculate_text_similarity(word, &node.label);
                
                if similarity >= self.similarity_threshold {
                    aligned_pairs.push(AlignmentPair {
                        text_span: TextSpan {
                            start: word_idx as u32 * 10, // Simplified offset calculation
                            end: (word_idx as u32 + 1) * 10,
                            text: word.to_string(),
                            context: text.to_string(),
                        },
                        graph_node_id: node.id.clone(),
                        alignment_type: if similarity > 0.9 {
                            AlignmentType::ExactMatch
                        } else {
                            AlignmentType::SemanticMatch
                        },
                        confidence: similarity,
                        semantic_features: vec!["word_match".to_string()],
                    });
                    alignment_confidence += similarity;
                    matches_found += 1;
                }
            }
        }

        if matches_found > 0 {
            alignment_confidence /= matches_found as f64;
        }

        Ok(TextGraphAlignment {
            aligned_pairs,
            unaligned_text_spans: Vec::new(),
            unaligned_graph_nodes: Vec::new(),
            alignment_confidence,
            semantic_coherence_score: alignment_confidence * 0.8,
        })
    }

    fn extract_entities_from_text(&self, text: &str) -> Result<Vec<HashMap<String, String>>, RustlerError> {
        let mut entities = Vec::new();
        
        // Simple entity extraction using patterns
        let word_regex = Regex::new(r"\b[A-Z][a-zA-Z]+\b").unwrap();
        
        for mat in word_regex.find_iter(text) {
            let mut entity = HashMap::new();
            entity.insert("text".to_string(), mat.as_str().to_string());
            entity.insert("type".to_string(), "ENTITY".to_string());
            entity.insert("confidence".to_string(), "0.8".to_string());
            entities.push(entity);
        }
        
        Ok(entities)
    }

    fn extract_relationships_from_text(&self, text: &str) -> Result<Vec<HashMap<String, String>>, RustlerError> {
        let mut relationships = Vec::new();
        
        // Simple relationship extraction using patterns
        let relation_regex = Regex::new(r"(\w+)\s+(is|are|has|have|uses|relates to)\s+(\w+)").unwrap();
        
        for cap in relation_regex.captures_iter(text) {
            let mut relationship = HashMap::new();
            relationship.insert("subject".to_string(), cap[1].to_string());
            relationship.insert("predicate".to_string(), cap[2].to_string());
            relationship.insert("object".to_string(), cap[3].to_string());
            relationship.insert("confidence".to_string(), "0.7".to_string());
            relationships.push(relationship);
        }
        
        Ok(relationships)
    }

    fn calculate_text_similarity(&self, text1: &str, text2: &str) -> f64 {
        let text1_lower = text1.to_lowercase();
        let text2_lower = text2.to_lowercase();
        
        if text1_lower == text2_lower {
            return 1.0;
        }
        
        if text1_lower.contains(&text2_lower) || text2_lower.contains(&text1_lower) {
            return 0.8;
        }
        
        // Simple Levenshtein-inspired similarity
        let len1 = text1_lower.len();
        let len2 = text2_lower.len();
        let max_len = len1.max(len2);
        
        if max_len == 0 {
            return 1.0;
        }
        
        let common_chars = text1_lower.chars()
            .filter(|c| text2_lower.contains(*c))
            .count();
        
        common_chars as f64 / max_len as f64
    }

    fn find_graph_node_by_id(&self, graph: &Graph<GraphNode, GraphEdge, Directed>, node_id: &str) -> Option<&GraphNode> {
        graph.node_weights().find(|node| node.id == node_id)
    }

    fn entity_exists_in_graph(&self, graph: &Graph<GraphNode, GraphEdge, Directed>, entity: &HashMap<String, String>) -> bool {
        if let Some(entity_text) = entity.get("text") {
            graph.node_weights().any(|node| {
                self.calculate_text_similarity(&node.label, entity_text) > self.similarity_threshold
            })
        } else {
            false
        }
    }

    fn find_matching_node(&self, graph: &Graph<GraphNode, GraphEdge, Directed>, entity: &HashMap<String, String>) -> Option<&GraphNode> {
        if let Some(entity_text) = entity.get("text") {
            graph.node_weights()
                .find(|node| self.calculate_text_similarity(&node.label, entity_text) > self.similarity_threshold)
        } else {
            None
        }
    }

    fn create_node_from_entity(&self, entity: HashMap<String, String>, node_id: usize) -> Result<GraphNode, RustlerError> {
        let text = entity.get("text").cloned().unwrap_or_default();
        let entity_type = entity.get("type").cloned().unwrap_or("ENTITY".to_string());
        
        Ok(GraphNode {
            id: format!("text_entity_{}", node_id),
            node_type: entity_type,
            label: text,
            properties: entity.iter().map(|(k, v)| (k.clone(), Value::String(v.clone()))).collect(),
            weight: 1.0,
            centrality_scores: HashMap::new(),
            community_id: None,
            semantic_embedding: None,
            metadata: {
                let mut meta = HashMap::new();
                meta.insert("source".to_string(), "text_extraction".to_string());
                meta
            },
        })
    }

    fn enrich_node_with_entity(&self, node: &mut GraphNode, entity: &HashMap<String, String>) {
        for (key, value) in entity {
            node.properties.insert(format!("text_{}", key), Value::String(value.clone()));
        }
        node.metadata.insert("enriched_from_text".to_string(), "true".to_string());
    }

    fn create_edge_from_relationship(
        &self,
        relationship: HashMap<String, String>,
        edge_id: usize,
        _graph: &Graph<GraphNode, GraphEdge, Directed>
    ) -> Result<Option<GraphEdge>, RustlerError> {
        let subject = relationship.get("subject").cloned().unwrap_or_default();
        let predicate = relationship.get("predicate").cloned().unwrap_or("RELATES_TO".to_string());
        let object = relationship.get("object").cloned().unwrap_or_default();
        let confidence: f64 = relationship.get("confidence").and_then(|s| s.parse().ok()).unwrap_or(0.7);
        
        Ok(Some(GraphEdge {
            id: format!("text_relation_{}", edge_id),
            source: subject,
            target: object,
            edge_type: predicate.to_uppercase(),
            label: predicate,
            weight: confidence,
            confidence,
            properties: relationship.iter().map(|(k, v)| (k.clone(), Value::String(v.clone()))).collect(),
            bidirectional: false,
            semantic_strength: confidence,
            metadata: {
                let mut meta = HashMap::new();
                meta.insert("source".to_string(), "text_extraction".to_string());
                meta
            },
        }))
    }

    fn extract_query_terms(&self, query_text: &str) -> Vec<String> {
        query_text.split_whitespace()
            .filter(|word| word.len() > 2)
            .map(|word| word.to_lowercase())
            .collect()
    }

    fn determine_query_type(&self, query_text: &str) -> String {
        let query_lower = query_text.to_lowercase();
        
        if query_lower.contains("find") && query_lower.contains("node") {
            "find_nodes".to_string()
        } else if query_lower.contains("path") {
            "find_paths".to_string()
        } else if query_lower.contains("subgraph") || query_lower.contains("pattern") {
            "find_subgraphs".to_string()
        } else if query_lower.contains("similar") || query_lower.contains("like") {
            "semantic_search".to_string()
        } else {
            "semantic_search".to_string() // Default
        }
    }

    fn find_nodes_by_text_query(
        &self,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        query_terms: &[String],
        _options: &HashMap<String, Value>
    ) -> Result<Vec<GraphNode>, RustlerError> {
        let mut matching_nodes = Vec::new();
        
        for node in graph.node_weights() {
            let node_text = format!("{} {}", node.label, node.node_type).to_lowercase();
            let matches = query_terms.iter().any(|term| node_text.contains(term));
            
            if matches {
                matching_nodes.push(node.clone());
            }
        }
        
        Ok(matching_nodes)
    }

    fn find_paths_by_text_query(
        &self,
        _graph: &Graph<GraphNode, GraphEdge, Directed>,
        _query_terms: &[String],
        _options: &HashMap<String, Value>
    ) -> Result<Vec<Vec<String>>, RustlerError> {
        // Simplified implementation
        Ok(Vec::new())
    }

    fn find_subgraphs_by_text_query(
        &self,
        _graph: &Graph<GraphNode, GraphEdge, Directed>,
        _query_terms: &[String],
        _options: &HashMap<String, Value>
    ) -> Result<Vec<SubgraphResult>, RustlerError> {
        // Simplified implementation
        Ok(Vec::new())
    }

    fn semantic_search_graph(
        &self,
        graph: &Graph<GraphNode, GraphEdge, Directed>,
        query_terms: &[String],
        _options: &HashMap<String, Value>
    ) -> Result<(Vec<GraphNode>, Vec<GraphEdge>), RustlerError> {
        let nodes = self.find_nodes_by_text_query(graph, query_terms, _options)?;
        let edges = Vec::new(); // Simplified
        Ok((nodes, edges))
    }

    fn calculate_augmentation_confidence(&self, new_nodes: &[GraphNode], new_edges: &[GraphEdge], updated_nodes: &[GraphNode]) -> f64 {
        let total_elements = new_nodes.len() + new_edges.len() + updated_nodes.len();
        if total_elements == 0 {
            return 0.0;
        }
        
        let node_confidence: f64 = new_nodes.iter().map(|n| n.weight).sum();
        let edge_confidence: f64 = new_edges.iter().map(|e| e.confidence).sum();
        let update_confidence: f64 = updated_nodes.iter().map(|n| n.weight).sum();
        
        (node_confidence + edge_confidence + update_confidence) / total_elements as f64
    }

    fn calculate_query_confidence(&self, nodes: &[GraphNode], edges: &[GraphEdge], subgraphs: &[SubgraphResult]) -> f64 {
        let total_elements = nodes.len() + edges.len() + subgraphs.len();
        if total_elements == 0 {
            return 0.0;
        }
        
        let node_conf: f64 = nodes.iter().map(|n| n.weight).sum();
        let edge_conf: f64 = edges.iter().map(|e| e.confidence).sum();
        let subgraph_conf: f64 = subgraphs.iter().map(|s| s.significance_score).sum();
        
        (node_conf + edge_conf + subgraph_conf) / total_elements as f64
    }

    fn deduplicate_nodes(&self, nodes: Vec<GraphNode>) -> Vec<GraphNode> {
        let mut unique_nodes = Vec::new();
        let mut seen_ids = HashSet::new();
        
        for node in nodes {
            if !seen_ids.contains(&node.id) {
                seen_ids.insert(node.id.clone());
                unique_nodes.push(node);
            }
        }
        
        unique_nodes
    }

    fn deduplicate_edges(&self, edges: Vec<GraphEdge>) -> Vec<GraphEdge> {
        let mut unique_edges = Vec::new();
        let mut seen_ids = HashSet::new();
        
        for edge in edges {
            if !seen_ids.contains(&edge.id) {
                seen_ids.insert(edge.id.clone());
                unique_edges.push(edge);
            }
        }
        
        unique_edges
    }
}