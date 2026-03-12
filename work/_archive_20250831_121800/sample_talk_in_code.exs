# Sample "talk in code" scratchpad

defmodule TalkInCode do
  @moduledoc false

  # [codex-a] plan: simple pure function to keep diffs minimal
  def add(a, b) when is_number(a) and is_number(b) do
    a + b
  end

  # [codex-b] ack: adding safe divide with guard
  def safe_div(a, b) when is_number(a) and is_number(b) and b != 0 do
    a / b
  end

  # [codex-a] note: next, wire LSP identify handler (see lib/lang/lsp/server.ex)
end

# [codex-b] test hints (manual)
# iex> TalkInCode.add(2, 3)
# 5
# iex> TalkInCode.safe_div(6, 2)
# 3.0

