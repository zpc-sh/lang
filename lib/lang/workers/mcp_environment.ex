defmodule Lang.Workers.MCPEnvironment do
  @moduledoc """
  Generates the OpenAPI spec for MCP (Model Context Protocol) Broker endpoints.
  """

  use Oban.Worker, queue: :analysis, max_attempts: 3, tags: ["mcp", "openapi"]
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task" => "generate_spec"}}) do
    Logger.info("Generating OpenAPI spec for MCP environment")

    allowed_server_types = Lang.MCP.Security.allowed_server_types()
    max_conn = Lang.MCP.Broker.max_connections_per_user()

    spec = %{
      "openapi" => "3.1.0",
      "info" => %{
        "title" => "LANG MCP Broker API",
        "version" => "2.0.0",
        "description" =>
          "Secure MCP Broker endpoints for MCP servers\n\n## Error Conventions\nAll error responses use a consistent JSON shape:\n\n- error: human‑readable message (string)\n- details: optional object with structured fields (e.g., allowed lists, limits)\n\nCommon HTTP status codes:\n- 400 Bad Request (validation issues; often includes details.allowed)\n- 401 Unauthorized (missing/invalid auth)\n- 403 Forbidden (exceeded limits; includes details.max_connections)\n- 404 Not Found\n- 409 Conflict (rare; resource conflicts)\n- 422 Unprocessable Entity (semantic validation)\n- 429 Too Many Requests (rate limiting)\n- 500 Internal Server Error",
        "x-generated" => DateTime.utc_now()
      },
      "servers" => [
        %{"url" => "https://lang.nocsi.com", "description" => "Production"}
      ],
      "paths" => paths(allowed_server_types, max_conn),
      "components" => %{
        "schemas" => schemas(allowed_server_types),
        "securitySchemes" => security(),
        "responses" => error_responses()
      },
      "security" => [%{"ApiKeyAuth" => []}],
      "tags" => [%{"name" => "MCP", "description" => "MCP Broker endpoints"}]
    }

    File.mkdir_p!("priv/static/docs/mcp")
    File.write!("priv/static/docs/mcp/openapi.json", Jason.encode!(spec, pretty: true))

    {:ok, %{spec_path: "priv/static/docs/mcp/openapi.json"}}
  end

  @doc """
  Enqueue generation now or at a later time.
  Pass a map like %{"task" => "generate_spec"}, optionally with scheduled_at.
  """
  def enqueue(opts \\ %{}) do
    args = Map.merge(%{"task" => "generate_spec"}, opts)
    __MODULE__.new(args) |> Oban.insert()
  end

  defp paths(allowed_server_types, max_conn) do
    %{
      "/api/v2/mcp/connect" => %{
        "post" => %{
          "tags" => ["MCP"],
          "summary" => "Create MCP connection",
          "requestBody" => %{
            "required" => true,
            "content" => %{
              "application/json" => %{
                "schema" => %{"$ref" => "#/components/schemas/MCPConnectRequest"}
              }
            }
          },
          "responses" => %{
            "201" => %{
              "description" => "Created",
              "content" => %{
                "application/json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/MCPConnectResponse"},
                  "examples" => %{"default" => %{"value" => example_connect_response()}}
                }
              }
            },
            "400" => %{
              "description" => "Bad request",
              "content" => %{
                "application/json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/MCPError"},
                  "examples" => %{
                    "missing_server_type" => %{
                      "value" => %{"error" => "Missing required parameter: server_type"}
                    },
                    "server_type_not_allowed" => %{
                      "value" => %{
                        "error" => "MCP server type not allowed",
                        "details" => %{"allowed" => allowed_server_types}
                      }
                    }
                  }
                }
              }
            },
            "403" => %{
              "description" => "Forbidden",
              "content" => %{
                "application/json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/MCPError"},
                  "examples" => %{
                    "user_connection_limit_exceeded" => %{
                      "value" => %{
                        "error" => "Maximum MCP connections exceeded for user",
                        "details" => %{"max_connections" => max_conn}
                      }
                    }
                  }
                }
              }
            },
            "429" => %{
              "description" => "Rate limited",
              "content" => %{
                "application/json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/MCPError"},
                  "examples" => %{
                    "default" => %{
                      "value" => %{"error" => "Rate limit exceeded for MCP connections"}
                    }
                  }
                }
              }
            },
            "500" => %{
              "description" => "Internal error",
              "content" => %{
                "application/json" => %{"schema" => %{"$ref" => "#/components/schemas/MCPError"}}
              }
            }
          }
        }
      },
      "/api/v2/mcp/status/{stream_id}" => %{
        "get" => %{
          "tags" => ["MCP"],
          "summary" => "Stream and connection status",
          "parameters" => [param_stream_id()],
          "responses" => %{
            "200" => %{
              "description" => "OK",
              "content" => %{
                "application/json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/MCPStatusResponse"},
                  "examples" => %{"default" => %{"value" => example_status_response()}}
                }
              }
            },
            "404" => %{
              "description" => "Not found",
              "content" => %{
                "application/json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/MCPError"},
                  "examples" => %{"default" => %{"value" => %{"error" => "MCP stream not found"}}}
                }
              }
            },
            "403" => %{
              "description" => "Forbidden",
              "content" => %{
                "application/json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/MCPError"},
                  "examples" => %{
                    "default" => %{"value" => %{"error" => "Access denied to MCP stream"}}
                  }
                }
              }
            },
            "500" => %{
              "description" => "Internal error",
              "content" => %{
                "application/json" => %{"schema" => %{"$ref" => "#/components/schemas/MCPError"}}
              }
            }
          }
        }
      },
      "/api/v2/mcp/disconnect/{id}" => %{
        "delete" => %{
          "tags" => ["MCP"],
          "summary" => "Disconnect by stream_id or connection_id",
          "parameters" => [param_disconnect_id()],
          "responses" => %{
            "200" => %{
              "description" => "OK",
              "content" => %{
                "application/json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/MCPDisconnectResponse"}
                }
              }
            },
            "404" => %{
              "description" => "Not found",
              "content" => %{
                "application/json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/MCPError"},
                  "examples" => %{
                    "default" => %{"value" => %{"error" => "MCP connection not found"}}
                  }
                }
              }
            },
            "403" => %{
              "description" => "Access denied",
              "content" => %{
                "application/json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/MCPError"},
                  "examples" => %{
                    "default" => %{"value" => %{"error" => "Access denied to MCP connection"}}
                  }
                }
              }
            }
          }
        }
      },
      "/api/v2/mcp/connections" => %{
        "get" => %{
          "tags" => ["MCP"],
          "summary" => "List active connections",
          "responses" => %{
            "200" => %{
              "description" => "OK",
              "content" => %{
                "application/json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/MCPConnectionsResponse"},
                  "examples" => %{"default" => %{"value" => example_connections_response()}}
                }
              }
            },
            "401" => %{
              "description" => "Unauthorized",
              "content" => %{
                "application/json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/MCPError"},
                  "examples" => %{
                    "default" => %{"value" => %{"error" => "Authentication required"}}
                  }
                }
              }
            }
          }
        }
      },
      "/api/v2/mcp/billing/usage" => %{
        "get" => %{
          "tags" => ["MCP"],
          "summary" => "Usage billing summary",
          "parameters" => [
            %{
              "name" => "period",
              "in" => "query",
              "required" => true,
              "schema" => %{"type" => "string", "enum" => ["current_month", "last_month"]}
            }
          ],
          "responses" => %{
            "200" => %{
              "description" => "OK",
              "content" => %{
                "application/json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/MCPUsageResponse"}
                }
              }
            },
            "400" => %{
              "description" => "Bad request",
              "content" => %{
                "application/json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/MCPError"},
                  "examples" => %{
                    "missing_period" => %{
                      "value" => %{"error" => "Missing required parameter: period"}
                    },
                    "invalid_period" => %{
                      "value" => %{
                        "error" => "Invalid period parameter",
                        "details" => %{"allowed" => ["current_month", "last_month"]}
                      }
                    }
                  }
                }
              }
            },
            "401" => %{
              "description" => "Unauthorized",
              "content" => %{
                "application/json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/MCPError"},
                  "examples" => %{
                    "default" => %{"value" => %{"error" => "Authentication required"}}
                  }
                }
              }
            }
          }
        }
      }
    }
  end

  defp schemas(allowed_server_types) do
    %{
      "MCPConnectRequest" => %{
        "type" => "object",
        "properties" => %{
          "server_type" => %{"type" => "string", "enum" => allowed_server_types},
          "config" => %{"type" => "object"},
          "session_id" => %{"type" => "string"}
        },
        "required" => ["server_type"]
      },
      "MCPConnectResponse" => %{
        "type" => "object",
        "properties" => %{
          "connection_id" => %{"type" => "string"},
          "stream_id" => %{"type" => "string"},
          "status" => %{"type" => "string"},
          "server_info" => %{
            "type" => "object",
            "properties" => %{
              "server_type" => %{"type" => "string"},
              "created_at" => %{"type" => "string", "format" => "date-time"},
              "endpoints" => %{"$ref" => "#/components/schemas/MCPEndpoints"}
            }
          },
          "topics" => %{"$ref" => "#/components/schemas/MCPTopics"}
        },
        "required" => ["connection_id", "stream_id", "status"]
      },
      "MCPEndpoints" => %{
        "type" => "object",
        "properties" => %{
          "status" => %{"type" => "string"},
          "disconnect_by_stream" => %{"type" => "string"},
          "disconnect" => %{"type" => "string"},
          "websocket" => %{"type" => "string"}
        }
      },
      "MCPTopics" => %{
        "type" => "object",
        "properties" => %{
          "websocket" => %{"type" => "string"},
          "session" => %{"type" => "string"}
        }
      },
      "MCPStatusResponse" => %{
        "type" => "object",
        "properties" => %{
          "stream_id" => %{"type" => "string"},
          "connection_id" => %{"type" => "string"},
          "connection_status" => %{"$ref" => "#/components/schemas/MCPConnectionStatus"},
          "stream_status" => %{"type" => "string"},
          "server_type" => %{"type" => "string"},
          "progress" => %{
            "type" => "object",
            "properties" => %{
              "total_chunks" => %{"type" => "integer"},
              "sent_chunks" => %{"type" => "integer"},
              "completion_percentage" => %{"type" => "number"}
            }
          },
          "stats" => %{
            "type" => "object",
            "properties" => %{
              "created_at" => %{"type" => "string", "format" => "date-time"},
              "last_activity" => %{"type" => "string", "format" => "date-time"},
              "session_id" => %{"type" => "string"}
            }
          },
          "pool" => %{
            "type" => "object",
            "properties" => %{
              "total_pools" => %{"type" => "integer"},
              "total_connections" => %{"type" => "integer"},
              "active_connections" => %{"type" => "integer"},
              "idle_connections" => %{"type" => "integer"},
              "failed_connections" => %{"type" => "integer"}
            }
          },
          "endpoints" => %{"$ref" => "#/components/schemas/MCPEndpoints"},
          "topics" => %{"$ref" => "#/components/schemas/MCPTopics"}
        }
      },
      "MCPConnectionStatus" => %{
        "type" => "object",
        "properties" => %{
          "server_type" => %{"type" => "string"},
          "created_at" => %{"type" => "string", "format" => "date-time"},
          "last_activity" => %{"type" => "string", "format" => "date-time"},
          "request_count" => %{"type" => "integer"},
          "uptime_seconds" => %{"type" => "integer"},
          "health" => %{"type" => "string", "enum" => ["healthy", "unhealthy"]},
          "server_pid_masked" => %{"type" => "string"},
          "health_details" => %{
            "type" => "object",
            "properties" => %{
              "requests_handled" => %{"type" => "integer"},
              "files_read" => %{"type" => "integer"},
              "directories_listed" => %{"type" => "integer"},
              "root_path_accessible" => %{"type" => "boolean"},
              "uptime_seconds" => %{"type" => "integer"},
              "status" => %{"type" => "string"}
            },
            "additionalProperties" => true
          },
          "user_id" => %{"type" => "string"},
          "session_id" => %{"type" => "string"},
          "stream_id" => %{"type" => "string"},
          "status" => %{"type" => "string", "enum" => ["alive", "dead"]}
        }
      },
      "MCPError" => %{
        "type" => "object",
        "properties" => %{
          "error" => %{"type" => "string"},
          "details" => %{"type" => "object", "additionalProperties" => true}
        },
        "required" => ["error"]
      },
      "MCPDisconnectResponse" => %{
        "type" => "object",
        "properties" => %{
          "stream_id" => %{"type" => "string"},
          "connection_id" => %{"type" => "string"},
          "status" => %{"type" => "string"},
          "cleanup" => %{"type" => "string"}
        }
      },
      "MCPConnectionsResponse" => %{
        "type" => "object",
        "properties" => %{
          "connections" => %{
            "type" => "array",
            "items" => %{"$ref" => "#/components/schemas/MCPConnectionItem"}
          },
          "pool" => %{
            "type" => "object",
            "properties" => %{
              "total_pools" => %{"type" => "integer"},
              "total_connections" => %{"type" => "integer"},
              "active_connections" => %{"type" => "integer"},
              "idle_connections" => %{"type" => "integer"},
              "failed_connections" => %{"type" => "integer"}
            }
          }
        }
      },
      "MCPConnectionItem" => %{
        "type" => "object",
        "properties" => %{
          "connection_id" => %{"type" => "string"},
          "server_type" => %{"type" => "string"},
          "status" => %{"type" => "string"},
          "created_at" => %{"type" => "string", "format" => "date-time"},
          "last_activity" => %{"type" => "string", "format" => "date-time"},
          "request_count" => %{"type" => "integer"},
          "uptime_seconds" => %{"type" => "integer"},
          "health" => %{"type" => "string", "enum" => ["healthy", "unhealthy"]},
          "server_pid_masked" => %{"type" => "string"},
          "health_details" => %{"type" => "object", "additionalProperties" => true},
          "session_id" => %{"type" => "string"},
          "stream_id" => %{"type" => "string"},
          "endpoints" => %{"$ref" => "#/components/schemas/MCPEndpoints"},
          "topics" => %{"$ref" => "#/components/schemas/MCPTopics"}
        }
      },
      "MCPUsageResponse" => %{
        "type" => "object",
        "properties" => %{
          "total_connections" => %{"type" => "integer"},
          "total_cost_cents" => %{"type" => "integer"},
          "period" => %{"type" => "string"},
          "by_server_type" => %{
            "type" => "object",
            "additionalProperties" => %{"type" => "integer"}
          }
        }
      }
    }
  end

  defp security do
    %{
      "ApiKeyAuth" => %{"type" => "apiKey", "in" => "header", "name" => "X-API-Key"}
    }
  end

  defp error_responses do
    %{
      "BadRequestError" => %{
        "description" => "Bad request",
        "content" => %{
          "application/json" => %{"schema" => %{"$ref" => "#/components/schemas/MCPError"}}
        }
      },
      "UnauthorizedError" => %{
        "description" => "Unauthorized",
        "content" => %{
          "application/json" => %{"schema" => %{"$ref" => "#/components/schemas/MCPError"}}
        }
      },
      "ForbiddenError" => %{
        "description" => "Forbidden",
        "content" => %{
          "application/json" => %{"schema" => %{"$ref" => "#/components/schemas/MCPError"}}
        }
      },
      "NotFoundError" => %{
        "description" => "Not found",
        "content" => %{
          "application/json" => %{"schema" => %{"$ref" => "#/components/schemas/MCPError"}}
        }
      },
      "TooManyRequestsError" => %{
        "description" => "Rate limited",
        "content" => %{
          "application/json" => %{"schema" => %{"$ref" => "#/components/schemas/MCPError"}}
        }
      },
      "UnprocessableEntityError" => %{
        "description" => "Unprocessable entity",
        "content" => %{
          "application/json" => %{"schema" => %{"$ref" => "#/components/schemas/MCPError"}}
        }
      },
      "InternalError" => %{
        "description" => "Internal server error",
        "content" => %{
          "application/json" => %{"schema" => %{"$ref" => "#/components/schemas/MCPError"}}
        }
      }
    }
  end

  defp param(name),
    do: %{"name" => name, "in" => "path", "required" => true, "schema" => %{"type" => "string"}}

  defp param_stream_id do
    %{
      "name" => "stream_id",
      "in" => "path",
      "required" => true,
      "description" => "MCP stream identifier",
      "schema" => %{"type" => "string", "pattern" => "^mcp_stream_[a-f0-9]+$"},
      "examples" => %{"example" => %{"value" => "mcp_stream_deadbeef"}}
    }
  end

  defp param_disconnect_id do
    %{
      "name" => "id",
      "in" => "path",
      "required" => true,
      "description" => "MCP stream_id or connection_id",
      "schema" => %{
        "type" => "string",
        "anyOf" => [
          %{"type" => "string", "pattern" => "^mcp_stream_[a-f0-9]+$"},
          %{"type" => "string", "pattern" => "^mcp_conn_[a-f0-9]+$"}
        ]
      },
      "examples" => %{
        "stream_id" => %{"value" => "mcp_stream_deadbeef"},
        "connection_id" => %{"value" => "mcp_conn_cafebabe"}
      }
    }
  end

  defp example_connect_response do
    %{
      connection_id: "mcp_conn_deadbeef",
      stream_id: "mcp_stream_cafebabe",
      status: "connected",
      server_info: %{
        server_type: "filesystem",
        created_at: DateTime.utc_now(),
        endpoints: %{
          status: "/api/v2/mcp/status/mcp_stream_cafebabe",
          disconnect_by_stream: "/api/v2/mcp/disconnect/mcp_stream_cafebabe",
          disconnect: "/api/v2/mcp/disconnect/mcp_conn_deadbeef",
          websocket: "/socket/websocket?vsn=2.0.0"
        }
      },
      topics: %{
        websocket: "mcp:mcp_stream_cafebabe",
        session: "mcp_stream:session:mcp_session_1234"
      }
    }
  end

  defp example_status_response do
    %{
      stream_id: "mcp_stream_cafebabe",
      connection_id: "mcp_conn_deadbeef",
      connection_status: %{
        server_type: "filesystem",
        created_at: DateTime.utc_now(),
        last_activity: DateTime.utc_now(),
        request_count: 1,
        uptime_seconds: 12,
        health: :healthy,
        server_pid_masked: "pid-12345",
        user_id: "user-uuid",
        session_id: "mcp_session_1234",
        stream_id: "mcp_stream_cafebabe",
        status: :alive
      },
      stream_status: :active,
      server_type: "filesystem",
      progress: %{total_chunks: 1, sent_chunks: 0, completion_percentage: 0.0},
      stats: %{
        created_at: DateTime.utc_now(),
        last_activity: DateTime.utc_now(),
        session_id: "mcp_session_1234"
      },
      pool: %{
        total_pools: 1,
        total_connections: 1,
        active_connections: 1,
        idle_connections: 0,
        failed_connections: 0
      },
      endpoints: %{
        status: "/api/v2/mcp/status/mcp_stream_cafebabe",
        disconnect_by_stream: "/api/v2/mcp/disconnect/mcp_stream_cafebabe",
        disconnect: "/api/v2/mcp/disconnect/mcp_conn_deadbeef"
      },
      topics: %{
        websocket: "mcp:mcp_stream_cafebabe",
        session: "mcp_stream:session:mcp_session_1234"
      }
    }
  end

  defp example_connections_response do
    %{
      connections: [
        %{
          connection_id: "mcp_conn_deadbeef",
          server_type: "filesystem",
          status: :alive,
          created_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now(),
          request_count: 1,
          uptime_seconds: 12,
          health: :healthy,
          server_pid_masked: "pid-12345",
          session_id: "mcp_session_1234",
          stream_id: "mcp_stream_cafebabe",
          endpoints: %{
            status: "/api/v2/mcp/status/mcp_stream_cafebabe",
            disconnect_by_stream: "/api/v2/mcp/disconnect/mcp_stream_cafebabe",
            disconnect: "/api/v2/mcp/disconnect/mcp_conn_deadbeef"
          },
          topics: %{
            websocket: "mcp:mcp_stream_cafebabe",
            session: "mcp_stream:session:mcp_session_1234"
          }
        }
      ],
      pool: %{
        total_pools: 1,
        total_connections: 1,
        active_connections: 1,
        idle_connections: 0,
        failed_connections: 0
      }
    }
  end
end
