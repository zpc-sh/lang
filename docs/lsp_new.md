<file path="priv/lsp/specs/lang_agent_swarm_create.jsonld">
{
  "@context": {
    "lsp": "https://lsp.dev/schema#",
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
    "xsd": "http://www.w3.org/2001/XMLSchema#"
  },
  "@id": "lsp:lang_agent_swarm_create",
  "@type": "lsp:Method",
  "lsp:method": "lang_agent_swarm_create",
  "lsp:params": {
    "@type": "lsp:Params",
    "lsp:properties": [
      {
        "lsp:name": "goals",
        "lsp:type": {
          "@type": "lsp:Array",
          "lsp:items": { "@type": "xsd:string" }
        },
        "lsp:required": true,
        "lsp:description": "List of shared goals for the agent swarm"
      },
      {
        "lsp:name": "agent_count",
        "lsp:type": "xsd:integer",
        "lsp:required": true,
        "lsp:description": "Number of agents to create in the swarm"
      },
      {
        "lsp:name": "coordinator_id",
        "lsp:type": "xsd:string",
        "lsp:required": false,
        "lsp:description": "Optional ID of the coordinating agent"
      }
    ]
  },
  "lsp:result": {
    "@type": "lsp:Result",
    "lsp:type": {
      "@type": "lsp:Object",
      "lsp:properties": [
        {
          "lsp:name": "swarm_id",
          "lsp:type": "xsd:string"
        },
        {
          "lsp:name": "agent_ids",
          "lsp:type": {
            "@type": "lsp:Array",
            "lsp:items": { "@type": "xsd:string" }
          }
        },
        {
          "lsp:name": "status",
          "lsp:type": "xsd:string"
        }
      ]
    }
  },
  "lsp:description": "Creates a swarm of AI agents with shared goals for collaborative tasks"
}
</file>

<file path="priv/lsp/specs/lang_agent_failover.jsonld">
{
  "@context": {
    "lsp": "https://lsp.dev/schema#",
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
    "xsd": "http://www.w3.org/2001/XMLSchema#"
  },
  "@id": "lsp:lang_agent_failover",
  "@type": "lsp:Method",
  "lsp:method": "lang_agent_failover",
  "lsp:params": {
    "@type": "lsp:Params",
    "lsp:properties": [
      {
        "lsp:name": "agent_id",
        "lsp:type": "xsd:string",
        "lsp:required": true,
        "lsp:description": "ID of the failed agent"
      },
      {
        "lsp:name": "error_code",
        "lsp:type": "xsd:integer",
        "lsp:required": true,
        "lsp:description": "Error code from the failure"
      },
      {
        "lsp:name": "backup_strategy",
        "lsp:type": "xsd:string",
        "lsp:required": true,
        "lsp:description": "Strategy for failover, e.g., 'retry' or 'replace'"
      }
    ]
  },
  "lsp:result": {
    "@type": "lsp:Result",
    "lsp:type": {
      "@type": "lsp:Object",
      "lsp:properties": [
        {
          "lsp:name": "new_agent_id",
          "lsp:type": "xsd:string"
        },
        {
          "lsp:name": "recovery_steps",
          "lsp:type": {
            "@type": "lsp:Array",
            "lsp:items": { "@type": "xsd:string" }
          }
        }
      ]
    }
  },
  "lsp:description": "Triggers failover to a backup agent upon failure"
}
</file>

<file path="priv/lsp/specs/lang_agent_consensus.jsonld">
{
  "@context": {
    "lsp": "https://lsp.dev/schema#",
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
    "xsd": "http://www.w3.org/2001/XMLSchema#"
  },
  "@id": "lsp:lang_agent_consensus",
  "@type": "lsp:Method",
  "lsp:method": "lang_agent_consensus",
  "lsp:params": {
    "@type": "lsp:Params",
    "lsp:properties": [
      {
        "lsp:name": "agent_ids",
        "lsp:type": {
          "@type": "lsp:Array",
          "lsp:items": { "@type": "xsd:string" }
        },
        "lsp:required": true,
        "lsp:description": "List of agent IDs participating in consensus"
      },
      {
        "lsp:name": "query",
        "lsp:type": "xsd:string",
        "lsp:required": true,
        "lsp:description": "The query or decision to reach consensus on"
      },
      {
        "lsp:name": "vote_threshold",
        "lsp:type": "xsd:float",
        "lsp:required": false,
        "lsp:description": "Threshold for consensus (default: 0.5)"
      }
    ]
  },
  "lsp:result": {
    "@type": "lsp:Result",
    "lsp:type": {
      "@type": "lsp:Object",
      "lsp:properties": [
        {
          "lsp:name": "consensus_result",
          "lsp:type": "lsp:Any"
        },
        {
          "lsp:name": "confidence",
          "lsp:type": "xsd:float"
        },
        {
          "lsp:name": "dissenting_agents",
          "lsp:type": {
            "@type": "lsp:Array",
            "lsp:items": { "@type": "xsd:string" }
          }
        }
      ]
    }
  },
  "lsp:description": "Aggregates decisions from multiple agents to reach consensus"
}
</file>

<file path="priv/lsp/specs/lang_ml_embed.jsonld">
{
  "@context": {
    "lsp": "https://lsp.dev/schema#",
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
    "xsd": "http://www.w3.org/2001/XMLSchema#"
  },
  "@id": "lsp:lang_ml_embed",
  "@type": "lsp:Method",
  "lsp:method": "lang_ml_embed",
  "lsp:params": {
    "@type": "lsp:Params",
    "lsp:properties": [
      {
        "lsp:name": "content",
        "lsp:type": "xsd:string",
        "lsp:required": true,
        "lsp:description": "Text content to generate embeddings for"
      },
      {
        "lsp:name": "model",
        "lsp:type": "xsd:string",
        "lsp:required": false,
        "lsp:description": "Embedding model to use (default: 'opencode')"
      }
    ]
  },
  "lsp:result": {
    "@type": "lsp:Result",
    "lsp:type": {
      "@type": "lsp:Object",
      "lsp:properties": [
        {
          "lsp:name": "embedding",
          "lsp:type": {
            "@type": "lsp:Array",
            "lsp:items": { "@type": "xsd:float" }
          }
        },
        {
          "lsp:name": "dimension",
          "lsp:type": "xsd:integer"
        }
      ]
    }
  },
  "lsp:description": "Generates vector embeddings for the given text content"
}
</file>

<file path="priv/lsp/specs/lang_ml_finetune.jsonld">
{
  "@context": {
    "lsp": "https://lsp.dev/schema#",
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
    "xsd": "http://www.w3.org/2001/XMLSchema#"
  },
  "@id": "lsp:lang_ml_finetune",
  "@type": "lsp:Method",
  "lsp:method": "lang_ml_finetune",
  "lsp:params": {
    "@type": "lsp:Params",
    "lsp:properties": [
      {
        "lsp:name": "dataset_id",
        "lsp:type": "xsd:string",
        "lsp:required": true,
        "lsp:description": "ID of the dataset to fine-tune on"
      },
      {
        "lsp:name": "base_model",
        "lsp:type": "xsd:string",
        "lsp:required": true,
        "lsp:description": "Base model to fine-tune"
      },
      {
        "lsp:name": "epochs",
        "lsp:type": "xsd:integer",
        "lsp:required": false,
        "lsp:description": "Number of training epochs (default: 3)"
      }
    ]
  },
  "lsp:result": {
    "@type": "lsp:Result",
    "lsp:type": {
      "@type": "lsp:Object",
      "lsp:properties": [
        {
          "lsp:name": "tuned_model_id",
          "lsp:type": "xsd:string"
        },
        {
          "lsp:name": "training_status",
          "lsp:type": "xsd:string"
        }
      ]
    }
  },
  "lsp:description": "Initiates fine-tuning of an ML model on a specified dataset"
}
</file>

<file path="priv/lsp/specs/lang_ml_anomaly_detect.jsonld">
{
  "@context": {
    "lsp": "https://lsp.dev/schema#",
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
    "xsd": "http://www.w3.org/2001/XMLSchema#"
  },
  "@id": "lsp:lang_ml_anomaly_detect",
  "@type": "lsp:Method",
  "lsp:method": "lang_ml_anomaly_detect",
  "lsp:params": {
    "@type": "lsp:Params",
    "lsp:properties": [
      {
        "lsp:name": "data_points",
        "lsp:type": {
          "@type": "lsp:Array",
          "lsp:items": { "@type": "lsp:Object" }
        },
        "lsp:required": true,
        "lsp:description": "List of data points to analyze for anomalies"
      },
      {
        "lsp:name": "threshold",
        "lsp:type": "xsd:float",
        "lsp:required": false,
        "lsp:description": "Anomaly detection threshold (default: 0.95)"
      }
    ]
  },
  "lsp:result": {
    "@type": "lsp:Result",
    "lsp:type": {
      "@type": "lsp:Object",
      "lsp:properties": [
        {
          "lsp:name": "anomalies",
          "lsp:type": {
            "@type": "lsp:Array",
            "lsp:items": { "@type": "lsp:Object" }
          }
        },
        {
          "lsp:name": "score",
          "lsp:type": "xsd:float"
        }
      ]
    }
  },
  "lsp:description": "Detects anomalies in agent behaviors or content using ML"
}
</file>

<file path="priv/lsp/specs/lang_collab_session_join.jsonld">
{
  "@context": {
    "lsp": "https://lsp.dev/schema#",
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
    "xsd": "http://www.w3.org/2001/XMLSchema#"
  },
  "@id": "lsp:lang_collab_session_join",
  "@type": "lsp:Method",
  "lsp:method": "lang_collab_session_join",
  "lsp:params": {
    "@type": "lsp:Params",
    "lsp:properties": [
      {
        "lsp:name": "session_id",
        "lsp:type": "xsd:string",
        "lsp:required": true,
        "lsp:description": "ID of the collaboration session to join"
      },
      {
        "lsp:name": "client_id",
        "lsp:type": "xsd:string",
        "lsp:required": true,
        "lsp:description": "ID of the client (agent) joining"
      },
      {
        "lsp:name": "role",
        "lsp:type": "xsd:string",
        "lsp:required": false,
        "lsp:description": "Role in the session, e.g., 'observer' or 'editor'"
      }
    ]
  },
  "lsp:result": {
    "@type": "lsp:Result",
    "lsp:type": {
      "@type": "lsp:Object",
      "lsp:properties": [
        {
          "lsp:name": "joined",
          "lsp:type": "xsd:boolean"
        },
        {
          "lsp:name": "participants",
          "lsp:type": {
            "@type": "lsp:Array",
            "lsp:items": { "@type": "xsd:string" }
          }
        }
      ]
    }
  },
  "lsp:description": "Allows an agent to join a shared collaboration session"
}
</file>

<file path="priv/lsp/specs/lang_collab_diff_apply.jsonld">
{
  "@context": {
    "lsp": "https://lsp.dev/schema#",
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
    "xsd": "http://www.w3.org/2001/XMLSchema#"
  },
  "@id": "lsp:lang_collab_diff_apply",
  "@type": "lsp:Method",
  "lsp:method": "lang_collab_diff_apply",
  "lsp:params": {
    "@type": "lsp:Params",
    "lsp:properties": [
      {
        "lsp:name": "session_id",
        "lsp:type": "xsd:string",
        "lsp:required": true,
        "lsp:description": "ID of the collaboration session"
      },
      {
        "lsp:name": "diff",
        "lsp:type": "xsd:string",
        "lsp:required": true,
        "lsp:description": "Diff patch to apply"
      },
      {
        "lsp:name": "author_id",
        "lsp:type": "xsd:string",
        "lsp:required": true,
        "lsp:description": "ID of the author applying the diff"
      }
    ]
  },
  "lsp:result": {
    "@type": "lsp:Result",
    "lsp:type": {
      "@type": "lsp:Object",
      "lsp:properties": [
        {
          "lsp:name": "applied",
          "lsp:type": "xsd:boolean"
        },
        {
          "lsp:name": "conflicts",
          "lsp:type": {
            "@type": "lsp:Array",
            "lsp:items": { "@type": "lsp:Object" }
          }
        }
      ]
    }
  },
  "lsp:description": "Applies a diff from one agent to shared content in a session"
}
</file>

<file path="priv/lsp/specs/lang_metrics_predict_load.jsonld">
{
  "@context": {
    "lsp": "https://lsp.dev/schema#",
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
    "xsd": "http://www.w3.org/2001/XMLSchema#"
  },
  "@id": "lsp:lang_metrics_predict_load",
  "@type": "lsp:Method",
  "lsp:method": "lang_metrics_predict_load",
  "lsp:params": {
    "@type": "lsp:Params",
    "lsp:properties": [
      {
        "lsp:name": "historical_data",
        "lsp:type": {
          "@type": "lsp:Array",
          "lsp:items": { "@type": "lsp:Object" }
        },
        "lsp:required": true,
        "lsp:description": "Historical metrics data for prediction"
      },
      {
        "lsp:name": "forecast_horizon",
        "lsp:type": "xsd:integer",
        "lsp:required": true,
        "lsp:description": "Number of hours to forecast ahead"
      }
    ]
  },
  "lsp:result": {
    "@type": "lsp:Result",
    "lsp:type": {
      "@type": "lsp:Object",
      "lsp:properties": [
        {
          "lsp:name": "predicted_load",
          "lsp:type": {
            "@type": "lsp:Array",
            "lsp:items": { "@type": "lsp:Object" }
          }
        },
        {
          "lsp:name": "confidence_interval",
          "lsp:type": "lsp:Object"
        }
      ]
    }
  },
  "lsp:description": "Predicts future token or usage load based on historical data"
}
</file>

<file path="priv/lsp/specs/lang_metrics_bottleneck.jsonld">
{
  "@context": {
    "lsp": "https://lsp.dev/schema#",
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
    "xsd": "http://www.w3.org/2001/XMLSchema#"
  },
  "@id": "lsp:lang_metrics_bottleneck",
  "@type": "lsp:Method",
  "lsp:method": "lang_metrics_bottleneck",
  "lsp:params": {
    "@type": "lsp:Params",
    "lsp:properties": [
      {
        "lsp:name": "time_range",
        "lsp:type": "lsp:Object",
        "lsp:required": true,
        "lsp:description": "Time range for analysis, e.g., {from: datetime, to: datetime}"
      }
    ]
  },
  "lsp:result": {
    "@type": "lsp:Result",
    "lsp:type": {
      "@type": "lsp:Object",
      "lsp:properties": [
        {
          "lsp:name": "bottlenecks",
          "lsp:type": {
            "@type": "lsp:Array",
            "lsp:items": { "@type": "lsp:Object" }
          }
        },
        {
          "lsp:name": "impact",
          "lsp:type": "xsd:float"
        }
      ]
    }
  },
  "lsp:description": "Identifies performance bottlenecks in the system"
}
</file>

<file path="priv/lsp/specs/lang_security_audit_log.jsonld">
{
  "@context": {
    "lsp": "https://lsp.dev/schema#",
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
    "xsd": "http://www.w3.org/2001/XMLSchema#"
  },
  "@id": "lsp:lang_security_audit_log",
  "@type": "lsp:Method",
  "lsp:method": "lang_security_audit_log",
  "lsp:params": {
    "@type": "lsp:Params",
    "lsp:properties": [
      {
        "lsp:name": "filter",
        "lsp:type": "lsp:Object",
        "lsp:required": false,
        "lsp:description": "Filter criteria, e.g., {agent_id: string, time_range: object}"
      }
    ]
  },
  "lsp:result": {
    "@type": "lsp:Result",
    "lsp:type": {
      "@type": "lsp:Object",
      "lsp:properties": [
        {
          "lsp:name": "logs",
          "lsp:type": {
            "@type": "lsp:Array",
            "lsp:items": { "@type": "lsp:Object" }
          }
        },
        {
          "lsp:name": "total",
          "lsp:type": "xsd:integer"
        }
      ]
    }
  },
  "lsp:description": "Retrieves filtered security audit logs"
}
</file>

<file path="priv/lsp/specs/lang_security_compliance_check.jsonld">
{
  "@context": {
    "lsp": "https://lsp.dev/schema#",
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
    "xsd": "http://www.w3.org/2001/XMLSchema#"
  },
  "@id": "lsp:lang_security_compliance_check",
  "@type": "lsp:Method",
  "lsp:method": "lang_security_compliance_check",
  "lsp:params": {
    "@type": "lsp:Params",
    "lsp:properties": [
      {
        "lsp:name": "content",
        "lsp:type": "xsd:string",
        "lsp:required": true,
        "lsp:description": "Content to check for compliance"
      },
      {
        "lsp:name": "standard",
        "lsp:type": "xsd:string",
        "lsp:required": true,
        "lsp:description": "Compliance standard, e.g., 'gdpr'"
      }
    ]
  },
  "lsp:result": {
    "@type": "lsp:Result",
    "lsp:type": {
      "@type": "lsp:Object",
      "lsp:properties": [
        {
          "lsp:name": "compliant",
          "lsp:type": "xsd:boolean"
        },
        {
          "lsp:name": "issues",
          "lsp:type": {
            "@type": "lsp:Array",
            "lsp:items": { "@type": "xsd:string" }
          }
        }
      ]
    }
  },
  "lsp:description": "Checks content against specified compliance standards"
}
</file>

### Additional Suggestions for AI LLM Features

As an AI LLM myself, here's what I'd "want" in a system like LANG to enhance self-improvement, multi-modality, and efficiency—framed as new methods. These build on emerging AI patterns (e.g., reflection loops in o1 models, multi-modal in GPT-4o). I've added 5 more, keeping them practical for your AI-agent clients.

| Proposed Method              | Description & Rationale                                                                                                         | Params (Example)                                                                 | Results (Example)                                                 | Implementation Notes                                                          |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | ----------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `lang_agent_self_reflect`    | Allows an agent to reflect on its own outputs; rationale: Enables iterative improvement, like in reasoning models.              | `%{agent_id: string, previous_output: any, criteria: list(string)}`              | `%{reflection: string, improvements: list(string), score: float}` | Extend `lang_think_review_code`; use as a feedback loop in orchestration.     |
| `lang_prompt_optimize`       | Optimizes a prompt for better performance; rationale: Reduces token usage and improves response quality automatically.          | `%{original_prompt: string, examples: list(map(input: string, output: string))}` | `%{optimized_prompt: string, estimated_improvement: float}`       | Async via Oban; benchmark with `lang_tokens_estimate`.                        |
| `lang_multi_modal_analyze`   | Analyzes combined text/image input; rationale: Handles real-world data (e.g., diagrams + code), aligning with multi-modal LLMs. | `%{text: string, image_url: string, query: string}`                              | `%{analysis: any, entities: list(map)}`                           | Integrate `view_image` tool if needed; stub with providers supporting vision. |
| `lang_agent_knowledge_share` | Shares knowledge between agents; rationale: Builds collective intelligence in swarms.                                           | `%{from_agent_id: string, to_agent_ids: list(string), knowledge: any}`           | `%{shared: boolean, acknowledgments: list(map)}`                  | Use PubSub; tie to `lang_storage_store_patterns`.                             |
| `lang_ml_rag_query`          | Performs RAG (Retrieval-Augmented Generation) queries; rationale: Enhances accuracy with external knowledge retrieval.          | `%{query: string, knowledge_base_id: string, top_k: integer}`                    | `%{retrieved_docs: list(map), generated_response: string}`        | Build on `lang_ml_embed` for vector search; cache results.                    |

These additions bring the total to 17 new methods—enough to supercharge AI capabilities without overload. Generate their JSON-LD similarly if needed. Next, implement handlers in `lib/lang/lsp/handlers/` and update `mix lsp.generate` to include them! What do you want to tackle first?
