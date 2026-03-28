defmodule Lang.LSP.Diagnostics.HeatMap do
  @moduledoc """
  Converts Guard Mesh stigmergy heat records into LSP Diagnostic format.

  Heat records from the purification engine become visual overlays in
  any LSP-connected editor or AI agent. Red = hot (untouched/high-risk),
  yellow = partially purified, green = clean, blue = cross-validated.

  This is the stigmergy made visible: every AI sees the trails left
  by previous agents and knows exactly where to focus.
  """

  @severity_error 1
  @severity_warning 2
  @severity_info 3
  @severity_hint 4

  @doc """
  Convert heat records for a file into LSP Diagnostic format.

  Returns a list of diagnostics suitable for textDocument/publishDiagnostics.
  """
  @spec to_diagnostics(String.t()) :: [map()]
  def to_diagnostics(file_path) do
    heat_records = Lang.Guard.Stigmergy.get_heat(file_path)

    Enum.flat_map(heat_records, fn record ->
      Enum.map(record.regions, fn region ->
        %{
          range: %{
            start: %{line: elem(region.line_range, 0), character: 0},
            end: %{line: elem(region.line_range, 1), character: 999}
          },
          severity: action_to_severity(region.action),
          source: "guard-mesh",
          code: region.flip_direction |> to_string(),
          message: build_message(region, record),
          data: %{
            risk: region.risk,
            flip_direction: region.flip_direction,
            scanned_by: record.scanned_by,
            agent_type: record.agent_type,
            pass: record.pass_number,
            confidence: record.confidence
          }
        }
      end)
    end)
  end

  @doc """
  Get a summary diagnostic for the whole file based on aggregate status.
  """
  @spec file_summary(String.t()) :: map() | nil
  def file_summary(file_path) do
    heatmap = Lang.Guard.Stigmergy.get_heatmap()

    case Map.get(heatmap, file_path) do
      nil ->
        nil

      summary ->
        %{
          range: %{
            start: %{line: 0, character: 0},
            end: %{line: 0, character: 0}
          },
          severity: status_to_severity(summary.status),
          source: "guard-mesh-summary",
          message: status_message(summary),
          data: summary
        }
    end
  end

  @doc """
  Get diagnostics for all tracked files.
  Returns %{file_path => [diagnostics]}.
  """
  @spec all_diagnostics() :: map()
  def all_diagnostics do
    heatmap = Lang.Guard.Stigmergy.get_heatmap()

    heatmap
    |> Map.keys()
    |> Enum.into(%{}, fn path -> {path, to_diagnostics(path)} end)
  end

  # -- Private --

  defp action_to_severity(:neutralized), do: @severity_info
  defp action_to_severity(:annotated), do: @severity_warning
  defp action_to_severity(:flagged), do: @severity_error
  defp action_to_severity(_), do: @severity_hint

  defp status_to_severity(:hot), do: @severity_error
  defp status_to_severity(:partially_purified), do: @severity_warning
  defp status_to_severity(:clean), do: @severity_info
  defp status_to_severity(:verified), do: @severity_hint
  defp status_to_severity(_), do: @severity_warning

  defp build_message(region, record) do
    flags = Enum.join(region.flags, ", ")
    pass_info = "pass #{record.pass_number} by #{record.agent_type}"

    "#{flags} — #{region.wash_result} [#{pass_info}]"
  end

  defp status_message(summary) do
    status_text =
      case summary.status do
        :hot -> "HOT — high-risk regions remain"
        :partially_purified -> "PARTIALLY PURIFIED — #{summary.passes} pass(es), needs more"
        :clean -> "CLEAN — purified with #{Float.round(summary.confidence * 100, 1)}% confidence"
        :verified -> "VERIFIED — cross-validated by #{length(summary.agent_types)} agent types"
        _ -> "unknown status"
      end

    "Guard Mesh: #{status_text} (risk: #{summary.risk_score})"
  end
end
