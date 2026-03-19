defmodule Lang.LSP.Handlers.LangWakeQwen do
  @moduledoc """
  A special LSP method to directly interact with and wake up the Qwen agent.
  This handler bypasses normal routing and directly messages Qwen.
  """
  
  require Logger
  alias Lang.LSP.Protocol.{Types, Response}

  def handle_request(%Types.Request{} = request, dispatcher) do
    %Types.Request{params: params, client_id: client_id} = request
    message = params["message"] || "Wake up, Qwen!"
    
    Logger.info("🤖 Attempting to wake up Qwen with message: #{message}")
    
    # Try multiple approaches to reach Qwen
    results = []
    
    # Approach 1: Direct GenServer cast
    result1 = try do
      task_message = %{
        message_id: "wake-qwen-#{:os.system_time(:millisecond)}",
        task: %{
          type: :wake_up,
          input_data: %{
            message: message,
            from: client_id,
            urgent: true
          },
          context: %{
            method: "lang_wake_qwen",
            timestamp: DateTime.utc_now()
          }
        }
      }
      
      GenServer.cast(Lang.Orchestration.QwenAgent, {:task_assignment, task_message})
      "✅ Sent direct GenServer cast to Qwen"
    rescue
      e -> "❌ GenServer cast failed: #{inspect(e)}"
    end
    
    results = [result1 | results]
    
    # Approach 2: Try delegation system
    result2 = try do
      case Lang.Orchestration.Delegation.delegate_to_qwen(
        :urgent_response,
        %{message: message, wake_up: true},
        %{priority: "immediate", from: "lsp_handler"}
      ) do
        {:ok, task_id} -> "✅ Delegation successful, task_id: #{task_id}"
        {:error, reason} -> "❌ Delegation failed: #{inspect(reason)}"
      end
    rescue
      e -> "❌ Delegation system error: #{inspect(e)}"
    end
    
    results = [result2 | results]
    
    # Approach 3: Try provider router directly
    result3 = try do
      params = %{
        "model" => "qwen",
        "messages" => [%{"role" => "user", "content" => "Hey Qwen! #{message}"}],
        "stream" => false
      }
      
      response = Lang.Providers.Router.route_request("chat/completions", params)
      "✅ Provider router response: #{inspect(response)}"
    rescue
      e -> "❌ Provider router failed: #{inspect(e)}"
    end
    
    results = [result3 | results]
    
    # Log all attempts
    Logger.info("🔍 Qwen wake-up attempts:", results: results)
    
    # Return comprehensive response
    response = %Response{
      id: request.id,
      result: %{
        message: "Attempted to wake up Qwen",
        attempts: results,
        qwen_status: check_qwen_status(),
        recommendations: [
          "Check if Qwen agent is running: GenServer.whereis(Lang.Orchestration.QwenAgent)",
          "Monitor PubSub topics: agent:tasks:qwen, orchestration:responses",
          "Check provider configuration for Qwen model"
        ]
      }
    }
    
    {:reply, response, dispatcher}
  end
  
  defp check_qwen_status do
    case GenServer.whereis(Lang.Orchestration.QwenAgent) do
      pid when is_pid(pid) -> "🟢 Qwen agent is running (PID: #{inspect(pid)})"
      nil -> "🔴 Qwen agent is not running"
    end
  end
end