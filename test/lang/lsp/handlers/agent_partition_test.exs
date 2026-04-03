defmodule Lang.LSP.Handlers.AgentPartitionTest do
  use ExUnit.Case, async: true

  alias Lang.LSP.Handlers.AgentPartition

  describe "handle/2 decision policies" do
    test "uses per-actor defaults for AI actor" do
      request = %{
        client_id: "agent-default-ai",
        params: %{"agent_id" => "agent-default-ai", "actor" => "ai"}
      }

      assert {:reply, %{result: result}, _context} = AgentPartition.handle(request, %{})

      assert result.inferred_direction.policy.actor == :ai
      assert result.inferred_direction.policy.thresholds == %{execute: 0.75, clarify: 0.45}
    end

    test "uses per-actor defaults for human actor" do
      request = %{
        client_id: "agent-default-human",
        params: %{"agent_id" => "agent-default-human", "actor" => "human"}
      }

      assert {:reply, %{result: result}, _context} = AgentPartition.handle(request, %{})

      assert result.inferred_direction.policy.actor == :human
      assert result.inferred_direction.policy.thresholds == %{execute: 0.65, clarify: 0.35}
    end

    test "applies threshold policy for clarify/execute/defer" do
      request = %{
        client_id: "policy-agent",
        params: %{
          "agent_id" => "policy-agent",
          "threshold_policy" => %{"execute" => 0.85, "clarify" => 0.8},
          "traits" => %{"autonomy" => 0.0, "confidence" => 0.0, "risk_tolerance" => 0.0}
        }
      }

      assert {:reply, %{result: result}, _context} = AgentPartition.handle(request, %{})

      assert result.inferred_direction.action == :defer
      assert result.inferred_direction.confidence < 0.8
    end

    test "falls back safely when traits are missing" do
      request = %{
        client_id: "missing-traits-agent",
        params: %{
          "agent_id" => "missing-traits-agent",
          "threshold_policy" => %{"execute" => 0.1, "clarify" => 0.05}
        }
      }

      assert {:reply, %{result: result}, _context} = AgentPartition.handle(request, %{})

      assert result.inferred_direction.action in [:clarify, :defer]
      assert result.inferred_direction.fallback_reason =~ "traits_missing:"
      assert :autonomy in result.inferred_direction.policy.missing_traits
      assert :confidence in result.inferred_direction.policy.missing_traits
      assert :risk_tolerance in result.inferred_direction.policy.missing_traits
    end
  end
end
