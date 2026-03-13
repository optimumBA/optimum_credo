defmodule OptimumCredo.Check.Readability.VerboseAssertions do
  @moduledoc """
  A check that finds verbose assertion patterns that can be simplified.

  This check identifies assertion patterns like `assert value != nil` and
  `assert value == nil` that should be simplified to `assert value` and
  `refute value` respectively.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    explanations: [
      check: """
      Assertion patterns should use Elixir's idiomatic assert/refute instead
      of verbose comparisons with nil.

      ## Examples

      **Bad:**
      ```elixir
      assert drop.id != nil
      assert user.name == nil
      refute item.id != nil
      refute status == nil
      ```

      **Good:**
      ```elixir
      assert drop.id
      refute user.name
      refute item.id
      assert status
      ```

      Use `is_nil(value)` only when you specifically need to distinguish nil from false.
      """
    ]

  @doc false
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta))
  end

  defp traverse(ast, issues, issue_meta) do
    new_issues = check_verbose_assertions(ast, issue_meta)
    {ast, issues ++ new_issues}
  end

  defp check_verbose_assertions({:assert, meta, [comparison]}, issue_meta) do
    case check_nil_comparison(comparison) do
      {:verbose, suggestion} ->
        [
          issue_for(
            issue_meta,
            meta[:line],
            "Use `#{suggestion}` instead of verbose nil comparison"
          )
        ]

      :ok ->
        []
    end
  end

  defp check_verbose_assertions({:refute, meta, [comparison]}, issue_meta) do
    case check_nil_comparison_for_refute(comparison) do
      {:verbose, suggestion} ->
        [
          issue_for(
            issue_meta,
            meta[:line],
            "Use `#{suggestion}` instead of verbose nil comparison"
          )
        ]

      :ok ->
        []
    end
  end

  defp check_verbose_assertions(_ast, _issue_meta), do: []

  defp check_nil_comparison({:!=, _meta, [left, nil]}) do
    {:verbose, "assert #{Macro.to_string(left)}"}
  end

  defp check_nil_comparison({:==, _meta, [left, nil]}) do
    {:verbose, "refute #{Macro.to_string(left)}"}
  end

  defp check_nil_comparison({:!=, _meta, [left, {:__aliases__, _, [nil]}]}) do
    {:verbose, "assert #{Macro.to_string(left)}"}
  end

  defp check_nil_comparison({:==, _meta, [left, {:__aliases__, _, [nil]}]}) do
    {:verbose, "refute #{Macro.to_string(left)}"}
  end

  # Handle cases where nil is on the left side
  defp check_nil_comparison({:!=, _meta, [nil, right]}) do
    {:verbose, "assert #{Macro.to_string(right)}"}
  end

  defp check_nil_comparison({:==, _meta, [nil, right]}) do
    {:verbose, "refute #{Macro.to_string(right)}"}
  end

  defp check_nil_comparison({:!=, _meta, [{:__aliases__, _, [nil]}, right]}) do
    {:verbose, "assert #{Macro.to_string(right)}"}
  end

  defp check_nil_comparison({:==, _meta, [{:__aliases__, _, [nil]}, right]}) do
    {:verbose, "refute #{Macro.to_string(right)}"}
  end

  defp check_nil_comparison(_), do: :ok

  defp check_nil_comparison_for_refute({:!=, _meta, [left, nil]}) do
    {:verbose, "refute #{Macro.to_string(left)}"}
  end

  defp check_nil_comparison_for_refute({:==, _meta, [left, nil]}) do
    {:verbose, "assert #{Macro.to_string(left)}"}
  end

  defp check_nil_comparison_for_refute({:!=, _meta, [left, {:__aliases__, _, [nil]}]}) do
    {:verbose, "refute #{Macro.to_string(left)}"}
  end

  defp check_nil_comparison_for_refute({:==, _meta, [left, {:__aliases__, _, [nil]}]}) do
    {:verbose, "assert #{Macro.to_string(left)}"}
  end

  defp check_nil_comparison_for_refute({:!=, _meta, [nil, right]}) do
    {:verbose, "refute #{Macro.to_string(right)}"}
  end

  defp check_nil_comparison_for_refute({:==, _meta, [nil, right]}) do
    {:verbose, "assert #{Macro.to_string(right)}"}
  end

  defp check_nil_comparison_for_refute({:!=, _meta, [{:__aliases__, _, [nil]}, right]}) do
    {:verbose, "refute #{Macro.to_string(right)}"}
  end

  defp check_nil_comparison_for_refute({:==, _meta, [{:__aliases__, _, [nil]}, right]}) do
    {:verbose, "assert #{Macro.to_string(right)}"}
  end

  defp check_nil_comparison_for_refute(_), do: :ok

  defp issue_for(issue_meta, line_no, message) do
    format_issue(
      issue_meta,
      message: message,
      line_no: line_no || 1
    )
  end
end
