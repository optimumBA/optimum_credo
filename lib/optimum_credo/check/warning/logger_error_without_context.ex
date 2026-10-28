defmodule OptimumCredo.Check.Warning.LoggerErrorWithoutContext do
  @moduledoc """
  Finds `Logger.error/1,2` calls whose message is a fixed string with no values.

  A constant message in a `rescue`/`catch` clause, or in a `{:error, _}` branch, tells
  production nothing about what failed. Include the arguments or the error, or attach
  metadata.

  This is a partial heuristic. Only `Logger.error` with a plain string literal is checked
  (an interpolated string, concatenation, function or variable message counts as having context)
  and a call with a non-empty metadata keyword list, or a metadata argument that is not a
  literal (`Logger.error("failed", metadata)`), counts as having context too. Metadata set
  earlier with `Logger.metadata/1` is not tracked, so a bare constant message after it is still
  reported; silence it with a disable comment or include the value in the message.

  ## Parameters

  - `scope`: `:error_branches` (default) checks only inside `rescue`/`catch` blocks and clauses
    whose pattern is `{:error, ...}` or `:error`; `:all` checks every `Logger.error` call.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [scope: :error_branches],
    explanations: [
      check: """
      `Logger.error("failed")` in an error branch hides what failed. Include the relevant
      values: `Logger.error("sync failed for \#{id}: \#{inspect(reason)}")`, or pass metadata.
      Only constant string messages are reported. Opt-in, low priority.
      """,
      params: [scope: "`:error_branches` (default) or `:all`."]
    ]

  alias OptimumCredo.OptimumIdiomsSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    everywhere? = Params.get(params, :scope, __MODULE__) == :all

    if OptimumIdiomsSupport.heex_file?(source_file) do
      []
    else
      source_file
      |> Credo.SourceFile.ast()
      |> OptimumIdiomsSupport.unpipe()
      |> scan(everywhere?, issue_meta)
      |> List.flatten()
    end
  end

  defp scan({key, clauses}, _in_error?, issue_meta) when key in [:rescue, :catch],
    do: scan(clauses, true, issue_meta)

  defp scan({:->, _meta, [pattern, body]}, in_error?, issue_meta),
    do: scan(body, in_error? or error_pattern?(pattern), issue_meta)

  defp scan(
         {{:., _meta, [{:__aliases__, _alias_meta, [:Logger]}, :error]}, meta, args},
         in_error?,
         issue_meta
       )
       when is_list(args) do
    own = if in_error? and constant_message?(args), do: [issue(issue_meta, meta)], else: []
    [own | scan(args, in_error?, issue_meta)]
  end

  defp scan({form, _meta, args}, in_error?, issue_meta) do
    [
      scan(form, in_error?, issue_meta),
      scan(args, in_error?, issue_meta)
    ]
  end

  defp scan({left, right}, in_error?, issue_meta),
    do: [
      scan(left, in_error?, issue_meta),
      scan(right, in_error?, issue_meta)
    ]

  defp scan(list, in_error?, issue_meta) when is_list(list),
    do: Enum.map(list, &scan(&1, in_error?, issue_meta))

  defp scan(_other, _in_error?, _issue_meta), do: []

  defp error_pattern?([{:when, _meta, args}]), do: error_pattern?([List.first(args)])
  defp error_pattern?([{:error, _reason}]), do: true
  defp error_pattern?([:error]), do: true
  defp error_pattern?([{:{}, _meta, [:error | _tail]}]), do: true
  defp error_pattern?(_pattern), do: false

  defp constant_message?([message]) when is_binary(message), do: true
  defp constant_message?([message, metadata]) when is_binary(message), do: metadata in [[], nil]
  defp constant_message?(_args), do: false

  defp issue(issue_meta, meta) do
    format_issue(issue_meta,
      message:
        "`Logger.error` with a constant message gives no context; include the values or metadata.",
      line_no: meta[:line] || 1
    )
  end
end
