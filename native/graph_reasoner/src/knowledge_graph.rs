use crate::*;
use regex::Regex;
use std::collections::{HashMap, HashSet};
use aho_corasick::{AhoCorasick, MatchKind};
use unicode_segmentation::UnicodeSegmentation;
use serde_json::Value;

pub struct KnowledgeExtractor {
    entity_patterns: Vec<EntityPattern>,
    relation_patterns: Vec<RelationPattern>,
    confidence_threshold: f64,
    max_entity_distance: usize,
    use_coreference: bool,
    linguistic_features: bool,
}

#[derive(Debug, Clone)]
struct EntityPattern {
    pattern: Regex,
    entity_type: String,
    confidence_boost: f64,
    context_clues: Vec<String>,
}

#[derive(Debug, Clone)]
struct RelationPattern {
    pattern: Regex,
    relation_type: String,
    subject_types: Vec<String>,
    object_types: Vec<String>,
    confidence_boost: f64,
    bidirectional: bool,
}

pub struct KnowledgeExtractionResult {
    pub entities: Vec<Entity>,
    pub relations: Vec<Relation>,
    pub triples: Vec<Triple>,
    pub schema: GraphSchema,
    pub confidence_threshold: f64,
}

impl KnowledgeExtractor {
    pub fn new(config: &HashMap<String, Value>) -> Result<Self, RustlerError> {
        let confidence_threshold = config.get("confidence_threshold")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.7);

        let max_entity_distance = config.get("max_entity_distance")
            .and_then(|v| v.as_u64())
            .map(|v| v as usize)
            .unwrap_or(50);

        let use_coreference = config.get("use_coreference")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);

        let linguistic_features = config.get("linguistic_features")
            .and_then(|v| v.as_bool())
            .unwrap_or(true);

        let mut extractor = Self {
            entity_patterns: Vec::new(),
            relation_patterns: Vec::new(),
            confidence_threshold,
            max_entity_distance,
            use_coreference,
            linguistic_features,
        };

        extractor.initialize_patterns(config)?;
        Ok(extractor)
    }

    fn initialize_patterns(&mut self, config: &HashMap<String, Value>) -> Result<(), RustlerError> {
        // Initialize entity patterns
        self.add_person_patterns();
        self.add_organization_patterns();
        self.add_location_patterns();
        self.add_concept_patterns();
        self.add_technical_patterns();
        
        // Initialize relation patterns
        self.add_hierarchical_relation_patterns();
        self.add_semantic_relation_patterns();
        self.add_temporal_relation_patterns();
        self.add_causal_relation_patterns();
        self.add_technical_relation_patterns();

        // Load custom patterns from config if provided
        if let Some(custom_entities) = config.get("custom_entity_patterns") {
            self.load_custom_entity_patterns(custom_entities)?;
        }

        if let Some(custom_relations) = config.get("custom_relation_patterns") {
            self.load_custom_relation_patterns(custom_relations)?;
        }

        Ok(())
    }

    fn add_person_patterns(&mut self) {
        let patterns = vec![
            (r"\b[A-Z][a-z]+\s+[A-Z][a-z]+\b", "PERSON", 0.8, vec!["Dr.", "Prof.", "Mr.", "Ms."]),
            (r"(?:Dr\.?|Prof\.?|Mr\.?|Ms\.?|Mrs\.?)\s+[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*", "PERSON", 0.9, vec![]),
            (r"\b[A-Z][a-z]+(?:\s+[A-Z]\.)*\s+[A-Z][a-z]+\b", "PERSON", 0.75, vec!["author", "researcher", "developer"]),
        ];

        for (pattern, entity_type, confidence, context) in patterns {
            if let Ok(regex) = Regex::new(pattern) {
                self.entity_patterns.push(EntityPattern {
                    pattern: regex,
                    entity_type: entity_type.to_string(),
                    confidence_boost: confidence,
                    context_clues: context.into_iter().map(|s| s.to_string()).collect(),
                });
            }
        }
    }

    fn add_organization_patterns(&mut self) {
        let patterns = vec![
            (r"\b[A-Z][a-zA-Z]*(?:\s+[A-Z][a-zA-Z]*)*\s+(?:Inc|LLC|Corp|Ltd|Company|Organization|Foundation)\b", "ORGANIZATION", 0.9, vec![]),
            (r"\b(?:University|College|Institute)\s+of\s+[A-Z][a-zA-Z]*(?:\s+[A-Z][a-zA-Z]*)*", "ORGANIZATION", 0.85, vec![]),
            (r"\b[A-Z]{2,}\b(?:\s+[A-Z]{2,})*", "ORGANIZATION", 0.6, vec!["company", "organization", "agency"]),
        ];

        for (pattern, entity_type, confidence, context) in patterns {
            if let Ok(regex) = Regex::new(pattern) {
                self.entity_patterns.push(EntityPattern {
                    pattern: regex,
                    entity_type: entity_type.to_string(),
                    confidence_boost: confidence,
                    context_clues: context.into_iter().map(|s| s.to_string()).collect(),
                });
            }
        }
    }

    fn add_location_patterns(&mut self) {
        let patterns = vec![
            (r"\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*,\s*[A-Z]{2}\b", "LOCATION", 0.85, vec![]),
            (r"\b(?:San|New|Los|Las)\s+[A-Z][a-z]+\b", "LOCATION", 0.8, vec![]),
            (r"\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\s+(?:City|County|State|Province|Country)\b", "LOCATION", 0.9, vec![]),
        ];

        for (pattern, entity_type, confidence, context) in patterns {
            if let Ok(regex) = Regex::new(pattern) {
                self.entity_patterns.push(EntityPattern {
                    pattern: regex,
                    entity_type: entity_type.to_string(),
                    confidence_boost: confidence,
                    context_clues: context.into_iter().map(|s: &str| s.to_string()).collect(),
                });
            }
        }
    }

    fn add_concept_patterns(&mut self) {
        let patterns = vec![
            (r"\b[a-z]+(?:-[a-z]+)*(?:\s+[a-z]+(?:-[a-z]+)*)*\s+(?:algorithm|method|technique|approach|framework|model)\b", "CONCEPT", 0.85, vec![]),
            (r"\b(?:machine\s+learning|artificial\s+intelligence|deep\s+learning|neural\s+network|data\s+mining)\b", "CONCEPT", 0.9, vec![]),
            (r"\b[A-Z][a-zA-Z]*(?:\s+[A-Z][a-zA-Z]*)*\s+(?:Theory|Principle|Law|Rule|Theorem)\b", "CONCEPT", 0.8, vec![]),
        ];

        for (pattern, entity_type, confidence, context) in patterns {
            if let Ok(regex) = Regex::new(&pattern.to_lowercase()) {
                self.entity_patterns.push(EntityPattern {
                    pattern: regex,
                    entity_type: entity_type.to_string(),
                    confidence_boost: confidence,
                    context_clues: context.into_iter().map(|s: &str| s.to_string()).collect(),
                });
            }
        }
    }

    fn add_technical_patterns(&mut self) {
        let patterns = vec![
            (r"\b[A-Z][a-zA-Z]*(?:\.[A-Z][a-zA-Z]*)+\b", "API", 0.8, vec!["method", "function", "class"]),
            (r"\b[a-z_]+\([^)]*\)", "FUNCTION", 0.75, vec!["returns", "parameter", "argument"]),
            (r"\b[A-Z_]+(?:\.[A-Z_]+)*\b", "CONSTANT", 0.7, vec!["defined", "constant", "value"]),
            (r"\b(?:class|interface|struct|enum)\s+[A-Z][a-zA-Z]*", "TYPE", 0.85, vec![]),
        ];

        for (pattern, entity_type, confidence, context) in patterns {
            if let Ok(regex) = Regex::new(pattern) {
                self.entity_patterns.push(EntityPattern {
                    pattern: regex,
                    entity_type: entity_type.to_string(),
                    confidence_boost: confidence,
                    context_clues: context.into_iter().map(|s| s.to_string()).collect(),
                });
            }
        }
    }

    fn add_hierarchical_relation_patterns(&mut self) {
        let patterns = vec![
            (r"(.+?)\s+(?:is\s+a|are)\s+(.+)", "IS_A", vec!["CONCEPT", "TYPE"], vec!["CONCEPT", "TYPE"], 0.8, false),
            (r"(.+?)\s+(?:inherits?\s+from|extends?)\s+(.+)", "INHERITS", vec!["TYPE"], vec!["TYPE"], 0.9, false),
            (r"(.+?)\s+(?:belongs?\s+to|is\s+part\s+of)\s+(.+)", "PART_OF", vec!["CONCEPT"], vec!["CONCEPT"], 0.85, false),
            (r"(.+?)\s+(?:contains?|includes?|has)\s+(.+)", "CONTAINS", vec!["CONCEPT"], vec!["CONCEPT"], 0.8, false),
        ];

        for (pattern, rel_type, subj_types, obj_types, confidence, bidirectional) in patterns {
            if let Ok(regex) = Regex::new(pattern) {
                self.relation_patterns.push(RelationPattern {
                    pattern: regex,
                    relation_type: rel_type.to_string(),
                    subject_types: subj_types.into_iter().map(|s| s.to_string()).collect(),
                    object_types: obj_types.into_iter().map(|s| s.to_string()).collect(),
                    confidence_boost: confidence,
                    bidirectional,
                });
            }
        }
    }

    fn add_semantic_relation_patterns(&mut self) {
        let patterns = vec![
            (r"(.+?)\s+(?:uses?|utilizes?|employs?)\s+(.+)", "USES", vec!["PERSON", "ORGANIZATION"], vec!["CONCEPT", "API"], 0.8, false),
            (r"(.+?)\s+(?:implements?|realizes?)\s+(.+)", "IMPLEMENTS", vec!["TYPE", "FUNCTION"], vec!["CONCEPT", "API"], 0.85, false),
            (r"(.+?)\s+(?:depends?\s+on|relies?\s+on|requires?)\s+(.+)", "DEPENDS_ON", vec!["CONCEPT"], vec!["CONCEPT"], 0.9, false),
            (r"(.+?)\s+(?:creates?|generates?|produces?)\s+(.+)", "CREATES", vec!["PERSON", "FUNCTION"], vec!["CONCEPT", "TYPE"], 0.8, false),
            (r"(.+?)\s+(?:similar\s+to|like|resembles?)\s+(.+)", "SIMILAR_TO", vec!["CONCEPT"], vec!["CONCEPT"], 0.7, true),
        ];

        for (pattern, rel_type, subj_types, obj_types, confidence, bidirectional) in patterns {
            if let Ok(regex) = Regex::new(pattern) {
                self.relation_patterns.push(RelationPattern {
                    pattern: regex,
                    relation_type: rel_type.to_string(),
                    subject_types: subj_types.into_iter().map(|s| s.to_string()).collect(),
                    object_types: obj_types.into_iter().map(|s| s.to_string()).collect(),
                    confidence_boost: confidence,
                    bidirectional,
                });
            }
        }
    }

    fn add_temporal_relation_patterns(&mut self) {
        let patterns = vec![
            (r"(.+?)\s+(?:before|prior\s+to|precedes?)\s+(.+)", "BEFORE", vec!["CONCEPT"], vec!["CONCEPT"], 0.8, false),
            (r"(.+?)\s+(?:after|following|succeeds?)\s+(.+)", "AFTER", vec!["CONCEPT"], vec!["CONCEPT"], 0.8, false),
            (r"(.+?)\s+(?:during|while|throughout)\s+(.+)", "DURING", vec!["CONCEPT"], vec!["CONCEPT"], 0.75, false),
            (r"(.+?)\s+(?:leads?\s+to|results?\s+in|causes?)\s+(.+)", "LEADS_TO", vec!["CONCEPT"], vec!["CONCEPT"], 0.85, false),
        ];

        for (pattern, rel_type, subj_types, obj_types, confidence, bidirectional) in patterns {
            if let Ok(regex) = Regex::new(pattern) {
                self.relation_patterns.push(RelationPattern {
                    pattern: regex,
                    relation_type: rel_type.to_string(),
                    subject_types: subj_types.into_iter().map(|s| s.to_string()).collect(),
                    object_types: obj_types.into_iter().map(|s| s.to_string()).collect(),
                    confidence_boost: confidence,
                    bidirectional,
                });
            }
        }
    }

    fn add_causal_relation_patterns(&mut self) {
        let patterns = vec![
            (r"(.+?)\s+(?:because\s+of|due\s+to|owing\s+to)\s+(.+)", "CAUSED_BY", vec!["CONCEPT"], vec!["CONCEPT"], 0.85, false),
            (r"(.+?)\s+(?:enables?|allows?|facilitates?)\s+(.+)", "ENABLES", vec!["CONCEPT"], vec!["CONCEPT"], 0.8, false),
            (r"(.+?)\s+(?:prevents?|blocks?|inhibits?)\s+(.+)", "PREVENTS", vec!["CONCEPT"], vec!["CONCEPT"], 0.8, false),
            (r"(.+?)\s+(?:influences?|affects?|impacts?)\s+(.+)", "INFLUENCES", vec!["CONCEPT"], vec!["CONCEPT"], 0.75, false),
        ];

        for (pattern, rel_type, subj_types, obj_types, confidence, bidirectional) in patterns {
            if let Ok(regex) = Regex::new(pattern) {
                self.relation_patterns.push(RelationPattern {
                    pattern: regex,
                    relation_type: rel_type.to_string(),
                    subject_types: subj_types.into_iter().map(|s| s.to_string()).collect(),
                    object_types: obj_types.into_iter().map(|s| s.to_string()).collect(),
                    confidence_boost: confidence,
                    bidirectional,
                });
            }
        }
    }

    fn add_technical_relation_patterns(&mut self) {
        let patterns = vec![
            (r"(.+?)\s+(?:calls?|invokes?)\s+(.+)", "CALLS", vec!["FUNCTION"], vec!["FUNCTION", "API"], 0.9, false),
            (r"(.+?)\s+(?:overrides?|overloads?)\s+(.+)", "OVERRIDES", vec!["FUNCTION"], vec!["FUNCTION"], 0.9, false),
            (r"(.+?)\s+(?:throws?|raises?)\s+(.+)", "THROWS", vec!["FUNCTION"], vec!["TYPE"], 0.85, false),
            (r"(.+?)\s+(?:returns?|yields?)\s+(.+)", "RETURNS", vec!["FUNCTION"], vec!["TYPE"], 0.8, false),
        ];

        for (pattern, rel_type, subj_types, obj_types, confidence, bidirectional) in patterns {
            if let Ok(regex) = Regex::new(pattern) {
                self.relation_patterns.push(RelationPattern {
                    pattern: regex,
                    relation_type: rel_type.to_string(),
                    subject_types: subj_types.into_iter().map(|s| s.to_string()).collect(),
                    object_types: obj_types.into_iter().map(|s| s.to_string()).collect(),
                    confidence_boost: confidence,
                    bidirectional,
                });
            }
        }
    }

    fn load_custom_entity_patterns(&mut self, patterns: &Value) -> Result<(), RustlerError> {
        if let Some(patterns_array) = patterns.as_array() {
            for pattern_obj in patterns_array {
                if let Some(pattern_map) = pattern_obj.as_object() {
                    let pattern_str = pattern_map.get("pattern")
                        .and_then(|v| v.as_str())
                        .ok_or(RustlerError::Atom("invalid_pattern"))?;
                    
                    let entity_type = pattern_map.get("entity_type")
                        .and_then(|v| v.as_str())
                        .ok_or(RustlerError::Atom("missing_entity_type"))?;
                    
                    let confidence = pattern_map.get("confidence")
                        .and_then(|v| v.as_f64())
                        .unwrap_or(0.7);

                    let context_clues = pattern_map.get("context_clues")
                        .and_then(|v| v.as_array())
                        .map(|arr| arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect())
                        .unwrap_or_else(Vec::new);

                    if let Ok(regex) = Regex::new(pattern_str) {
                        self.entity_patterns.push(EntityPattern {
                            pattern: regex,
                            entity_type: entity_type.to_string(),
                            confidence_boost: confidence,
                            context_clues,
                        });
                    }
                }
            }
        }
        Ok(())
    }

    fn load_custom_relation_patterns(&mut self, patterns: &Value) -> Result<(), RustlerError> {
        if let Some(patterns_array) = patterns.as_array() {
            for pattern_obj in patterns_array {
                if let Some(pattern_map) = pattern_obj.as_object() {
                    let pattern_str = pattern_map.get("pattern")
                        .and_then(|v| v.as_str())
                        .ok_or(RustlerError::Atom("invalid_pattern"))?;
                    
                    let relation_type = pattern_map.get("relation_type")
                        .and_then(|v| v.as_str())
                        .ok_or(RustlerError::Atom("missing_relation_type"))?;
                    
                    let confidence = pattern_map.get("confidence")
                        .and_then(|v| v.as_f64())
                        .unwrap_or(0.7);

                    let bidirectional = pattern_map.get("bidirectional")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false);

                    let subject_types = pattern_map.get("subject_types")
                        .and_then(|v| v.as_array())
                        .map(|arr| arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect())
                        .unwrap_or_else(|| vec!["CONCEPT".to_string()]);

                    let object_types = pattern_map.get("object_types")
                        .and_then(|v| v.as_array())
                        .map(|arr| arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect())
                        .unwrap_or_else(|| vec!["CONCEPT".to_string()]);

                    if let Ok(regex) = Regex::new(pattern_str) {
                        self.relation_patterns.push(RelationPattern {
                            pattern: regex,
                            relation_type: relation_type.to_string(),
                            subject_types,
                            object_types,
                            confidence_boost: confidence,
                            bidirectional,
                        });
                    }
                }
            }
        }
        Ok(())
    }

    pub fn extract_from_text(&self, text: &str) -> Result<KnowledgeExtractionResult, RustlerError> {
        // Step 1: Extract entities
        let mut entities = self.extract_entities(text)?;
        
        // Step 2: Extract relations
        let relations = self.extract_relations(text, &entities)?;
        
        // Step 3: Build triples
        let triples = self.build_triples(text, &entities, &relations)?;
        
        // Step 4: Apply coreference resolution if enabled
        if self.use_coreference {
            entities = self.resolve_coreference(&entities, text)?;
        }
        
        // Step 5: Generate schema
        let schema = self.generate_schema(&entities, &relations)?;
        
        Ok(KnowledgeExtractionResult {
            entities,
            relations,
            triples,
            schema,
            confidence_threshold: self.confidence_threshold,
        })
    }

    fn extract_entities(&self, text: &str) -> Result<Vec<Entity>, RustlerError> {
        let mut entities = Vec::new();
        let mut entity_id_counter = 0;

        for pattern in &self.entity_patterns {
            for mat in pattern.pattern.find_iter(text) {
                let matched_text = mat.as_str();
                let start = mat.start() as u32;
                let end = mat.end() as u32;
                
                // Calculate confidence based on context
                let context_start = (start as usize).saturating_sub(50);
                let context_end = std::cmp::min(end as usize + 50, text.len());
                let context = &text[context_start..context_end];
                
                let mut confidence = pattern.confidence_boost;
                
                // Boost confidence if context clues are present
                for clue in &pattern.context_clues {
                    if context.to_lowercase().contains(&clue.to_lowercase()) {
                        confidence = (confidence + 0.1).min(1.0);
                    }
                }
                
                // Apply linguistic features if enabled
                if self.linguistic_features {
                    confidence = self.apply_linguistic_features(matched_text, context, confidence);
                }
                
                if confidence >= self.confidence_threshold {
                    entity_id_counter += 1;
                    entities.push(Entity {
                        id: format!("entity_{}", entity_id_counter),
                        entity_type: pattern.entity_type.clone(),
                        labels: vec![matched_text.to_string()],
                        properties: HashMap::new(),
                        confidence,
                        source_spans: vec![TextSpan {
                            start,
                            end,
                            text: matched_text.to_string(),
                            context: context.to_string(),
                        }],
                    });
                }
            }
        }

        // Deduplicate and merge similar entities
        entities = self.deduplicate_entities(entities)?;
        
        Ok(entities)
    }

    fn extract_relations(&self, text: &str, entities: &[Entity]) -> Result<Vec<Relation>, RustlerError> {
        let mut relations = Vec::new();
        let mut relation_id_counter = 0;

        for pattern in &self.relation_patterns {
            for mat in pattern.pattern.find_iter(text) {
                if let Some(captures) = pattern.pattern.captures(mat.as_str()) {
                    if captures.len() >= 3 {
                        let subject_text = captures.get(1).unwrap().as_str();
                        let object_text = captures.get(2).unwrap().as_str();
                        
                        // Find matching entities
                        let subject_entities = self.find_matching_entities(subject_text, entities, &pattern.subject_types);
                        let object_entities = self.find_matching_entities(object_text, entities, &pattern.object_types);
                        
                        if !subject_entities.is_empty() && !object_entities.is_empty() {
                            relation_id_counter += 1;
                            relations.push(Relation {
                                id: format!("relation_{}", relation_id_counter),
                                relation_type: pattern.relation_type.clone(),
                                domain: pattern.subject_types.join("|"),
                                range: pattern.object_types.join("|"),
                                properties: HashMap::new(),
                                confidence: pattern.confidence_boost,
                            });
                        }
                    }
                }
            }
        }

        Ok(relations)
    }

    fn build_triples(&self, text: &str, entities: &[Entity], relations: &[Relation]) -> Result<Vec<Triple>, RustlerError> {
        let mut triples = Vec::new();

        // Create entity lookup for faster access
        let entity_lookup: HashMap<String, &Entity> = entities.iter()
            .map(|e| (e.labels[0].clone(), e))
            .collect();

        for relation in relations {
            for pattern in &self.relation_patterns {
                if pattern.relation_type == relation.relation_type {
                    for mat in pattern.pattern.find_iter(text) {
                        if let Some(captures) = pattern.pattern.captures(mat.as_str()) {
                            if captures.len() >= 3 {
                                let subject_text = captures.get(1).unwrap().as_str();
                                let object_text = captures.get(2).unwrap().as_str();
                                
                                if let (Some(subject_entity), Some(object_entity)) = 
                                    (entity_lookup.get(subject_text), entity_lookup.get(object_text)) {
                                    
                                    triples.push(Triple {
                                        subject: subject_entity.id.clone(),
                                        predicate: relation.id.clone(),
                                        object: object_entity.id.clone(),
                                        confidence: relation.confidence,
                                        source_evidence: vec![mat.as_str().to_string()],
                                        inferred: false,
                                    });
                                    
                                    // Add reverse triple if bidirectional
                                    if pattern.bidirectional {
                                        triples.push(Triple {
                                            subject: object_entity.id.clone(),
                                            predicate: relation.id.clone(),
                                            object: subject_entity.id.clone(),
                                            confidence: relation.confidence * 0.9, // Slightly lower confidence for inferred direction
                                            source_evidence: vec![mat.as_str().to_string()],
                                            inferred: true,
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Ok(triples)
    }

    fn find_matching_entities(&self, text: &str, entities: &[Entity], allowed_types: &[String]) -> Vec<&Entity> {
        entities.iter()
            .filter(|entity| {
                entity.labels.iter().any(|label| text.contains(label)) &&
                (allowed_types.is_empty() || allowed_types.contains(&entity.entity_type))
            })
            .collect()
    }

    fn apply_linguistic_features(&self, matched_text: &str, context: &str, base_confidence: f64) -> f64 {
        let mut confidence = base_confidence;
        
        // Check capitalization patterns
        if matched_text.chars().next().unwrap().is_uppercase() {
            confidence += 0.05;
        }
        
        // Check for proper noun patterns
        let words: Vec<&str> = matched_text.split_whitespace().collect();
        let proper_noun_ratio = words.iter()
            .filter(|word| word.chars().next().unwrap().is_uppercase())
            .count() as f64 / words.len() as f64;
        
        confidence += proper_noun_ratio * 0.1;
        
        // Check for punctuation context (quotes, parentheses)
        if context.contains(&format!("\"{}\"", matched_text)) || 
           context.contains(&format!("({})", matched_text)) {
            confidence += 0.1;
        }
        
        confidence.min(1.0)
    }

    fn deduplicate_entities(&self, mut entities: Vec<Entity>) -> Result<Vec<Entity>, RustlerError> {
        // Simple deduplication based on similar labels
        let mut deduped = Vec::new();
        let mut seen_labels = HashSet::new();
        
        for entity in entities {
            let primary_label = &entity.labels[0];
            let normalized_label = primary_label.to_lowercase().trim().to_string();
            
            if !seen_labels.contains(&normalized_label) {
                seen_labels.insert(normalized_label);
                deduped.push(entity);
            }
        }
        
        Ok(deduped)
    }

    fn resolve_coreference(&self, entities: &[Entity], text: &str) -> Result<Vec<Entity>, RustlerError> {
        // Simple coreference resolution - merge entities with similar spans
        let mut resolved = entities.to_vec();
        
        // This is a simplified implementation
        // In a full implementation, you would use more sophisticated coreference resolution
        
        Ok(resolved)
    }

    fn generate_schema(&self, entities: &[Entity], relations: &[Relation]) -> Result<GraphSchema, RustlerError> {
        let mut entity_types = HashSet::new();
        let mut relation_types = HashSet::new();
        
        for entity in entities {
            entity_types.insert(entity.entity_type.clone());
        }
        
        for relation in relations {
            relation_types.insert(relation.relation_type.clone());
        }
        
        // Build simple type hierarchy
        let mut type_hierarchy = HashMap::new();
        
        // Add basic hierarchies
        type_hierarchy.insert("PERSON".to_string(), vec!["ENTITY".to_string()]);
        type_hierarchy.insert("ORGANIZATION".to_string(), vec!["ENTITY".to_string()]);
        type_hierarchy.insert("LOCATION".to_string(), vec!["ENTITY".to_string()]);
        type_hierarchy.insert("CONCEPT".to_string(), vec!["ENTITY".to_string()]);
        
        Ok(GraphSchema {
            entity_types: entity_types.into_iter().collect(),
            relation_types: relation_types.into_iter().collect(),
            type_hierarchy,
            constraints: vec!["entity_uniqueness".to_string(), "relation_domain_range".to_string()],
        })
    }
}