defmodule OptimumCredo.Check.Readability.AssignThree do
  @moduledoc """
  Finds `assign/2` calls that receive a literal keyword list or map, such as
  `assign(socket, a: 1, b: 2)`.

  The team convention is one `assign(socket, :key, value)` per line, so diffs and
  search-and-replace stay simple. Forwarding a variable (`assign(socket, assigns)`)
  is not reported.

  This is a static heuristic: it matches by call name and arity, so a non-LiveView
  function named `assign/2` with a literal keyword argument is reported too. Function heads
  (`def assign(socket, a: 1)`) and `@spec`/`@callback` attributes are not calls and are skipped.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [],
    explanations: [
      check: """
      Use `assign(socket, :key, value)` in a pipeline, one assign per line, instead of
      `assign(socket, key: value)` or `assign(socket, %{key: value})` with a literal.

      Calls that forward a variable, such as `assign(socket, assigns)`, are allowed.
      Matching is by name and arity only; non-LiveView `assign/2` helpers can be
      reported too. Opt-in, low priority.

      ## Bad

      ```elixir
      assign(socket, page: 1, per_page: 20)
      ```

      ## Good

      ```elixir
      socket
      |> assign(:page, 1)
      |> assign(:per_page, 20)
      ```
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
      |> Macro.prewalk([], &collect_assigns(&1, &2, issue_meta))
      |> elem(1)
      |> Enum.reverse()
    end
  end

  defp collect_assigns({call, meta, [_socket, literal]} = node, acc, issue_meta)
       when is_list(meta) do
    if assign_call?(call) and literal?(literal),
      do: {node, [issue(issue_meta, meta) | acc]},
      else: {node, acc}
  end

  defp collect_assigns(node, acc, _issue_meta), do: {node, acc}

  defp assign_call?(:assign), do: true
  defp assign_call?({:., _meta, [_module, :assign]}), do: true
  defp assign_call?(_call), do: false

  defp literal?([_head | _tail] = keyword),
    do: Enum.all?(keyword, &match?({key, _} when is_atom(key), &1))

  defp literal?({:%{}, _meta, [_head | _tail] = pairs}), do: Enum.all?(pairs, &match?({_, _}, &1))
  defp literal?(_other), do: false

  defp issue(issue_meta, meta) do
    format_issue(issue_meta,
      message:
        "Use `assign(socket, :key, value)` once per key instead of a literal keyword or map.",
      line_no: meta[:line] || 1
    )
  end
end
