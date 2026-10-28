defmodule OptimumCredo.Check.Readability.SingleElementTupleMessage do
  @moduledoc """
  Finds messages sent as one-element tuples, such as `send(pid, {:refresh})`.

  A bare atom carries the same information without the wrapper. Inspected calls are
  `send/2`, `Kernel.send/2`, `Process.send/3`, `Process.send_after/3,4` (including the piped
  forms), and only when the tuple holds a single atom literal; `{ref}` or `{value}` cannot be
  replaced by an atom and is not reported. Messages passed through a variable, other receivers
  (`GenServer.cast/2`) and aliased `Process` modules are not inspected. Function heads
  such as `defp send(pid, {:ok})` are not calls and are skipped.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [],
    explanations: [
      check: """
      Send an atom rather than a one-element tuple: `send(pid, :refresh)` instead of
      `send(pid, {:refresh})`. Covers `send/2`, `Process.send/3` and `Process.send_after/3,4`.
      Opt-in, low priority.
      """
    ]

  alias OptimumCredo.OptimumIdiomsSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    if OptimumIdiomsSupport.heex_file?(source_file) do
      []
    else
      source_file
      |> Credo.SourceFile.ast()
      |> OptimumIdiomsSupport.without_definition_heads()
      |> OptimumIdiomsSupport.unpipe()
      |> Macro.prewalk([], &collect_sends(&1, &2, issue_meta))
      |> elem(1)
      |> Enum.reverse()
    end
  end

  defp collect_sends(
         {call, meta, [_pid, {:{}, _meta, [single]} | _tail] = args} = node,
         acc,
         issue_meta
       )
       when is_list(meta) do
    if atom?(single) and send_call?(call, length(args)),
      do: {node, [issue(issue_meta, meta) | acc]},
      else: {node, acc}
  end

  defp collect_sends(node, acc, _issue_meta), do: {node, acc}

  # `{ref}` or `{message}` cannot become a bare atom, so only `{:atom}` is reported.
  defp atom?(value), do: is_atom(value)

  defp send_call?(:send, 2), do: true
  defp send_call?({:., _meta, [{:__aliases__, _alias_meta, [:Kernel]}, :send]}, 2), do: true
  defp send_call?({:., _meta, [{:__aliases__, _alias_meta, [:Process]}, :send]}, 3), do: true

  defp send_call?({:., _meta, [{:__aliases__, _alias_meta, [:Process]}, :send_after]}, arity),
    do: arity in [3, 4]

  defp send_call?(_call, _arity), do: false

  defp issue(issue_meta, meta) do
    format_issue(issue_meta,
      message: "Send a bare atom instead of a one-element tuple message.",
      line_no: meta[:line] || 1
    )
  end
end
