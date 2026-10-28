defmodule OptimumCredo.Check.Readability.VerboseAssertions do
  @moduledoc """
  A check that finds verbose assertion patterns that can be simplified.

  This check prefers explicit `is_nil/1` assertions over equality comparisons with nil.
  Suggestions preserve the distinction between `false` and `nil`; replacing a nil
  comparison with a bare truthiness assertion can change what the test verifies.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    explanations: [
      check: """
      Assertion patterns should use explicit `is_nil/1` predicates instead
      of equality comparisons with nil.

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
      refute is_nil(drop.id)
      assert is_nil(user.name)
      assert is_nil(item.id)
      refute is_nil(status)
      ```

      Bare `assert value` and `refute value` also reject or accept `false`, respectively,
      so they are not equivalent to nil comparisons. Keep the nil predicate explicit.
      """
    ]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(
      source_file,
      &traverse(&1, &2, issue_meta)
    )
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
    {:verbose, "refute is_nil(#{Macro.to_string(left)})"}
  end

  defp check_nil_comparison({:==, _meta, [left, nil]}) do
    {:verbose, "assert is_nil(#{Macro.to_string(left)})"}
  end

  defp check_nil_comparison({:!=, _meta, [left, {:__aliases__, _alias_meta, [nil]}]}) do
    {:verbose, "refute is_nil(#{Macro.to_string(left)})"}
  end

  defp check_nil_comparison({:==, _meta, [left, {:__aliases__, _alias_meta, [nil]}]}) do
    {:verbose, "assert is_nil(#{Macro.to_string(left)})"}
  end

  # Handle cases where nil is on the left side
  defp check_nil_comparison({:!=, _meta, [nil, right]}) do
    {:verbose, "refute is_nil(#{Macro.to_string(right)})"}
  end

  defp check_nil_comparison({:==, _meta, [nil, right]}) do
    {:verbose, "assert is_nil(#{Macro.to_string(right)})"}
  end

  defp check_nil_comparison({:!=, _meta, [{:__aliases__, _alias_meta, [nil]}, right]}) do
    {:verbose, "refute is_nil(#{Macro.to_string(right)})"}
  end

  defp check_nil_comparison({:==, _meta, [{:__aliases__, _alias_meta, [nil]}, right]}) do
    {:verbose, "assert is_nil(#{Macro.to_string(right)})"}
  end

  defp check_nil_comparison(_ignored), do: :ok

  defp check_nil_comparison_for_refute({:!=, _meta, [left, nil]}) do
    {:verbose, "assert is_nil(#{Macro.to_string(left)})"}
  end

  defp check_nil_comparison_for_refute({:==, _meta, [left, nil]}) do
    {:verbose, "refute is_nil(#{Macro.to_string(left)})"}
  end

  defp check_nil_comparison_for_refute({:!=, _meta, [left, {:__aliases__, _alias_meta, [nil]}]}) do
    {:verbose, "assert is_nil(#{Macro.to_string(left)})"}
  end

  defp check_nil_comparison_for_refute({:==, _meta, [left, {:__aliases__, _alias_meta, [nil]}]}) do
    {:verbose, "refute is_nil(#{Macro.to_string(left)})"}
  end

  defp check_nil_comparison_for_refute({:!=, _meta, [nil, right]}) do
    {:verbose, "assert is_nil(#{Macro.to_string(right)})"}
  end

  defp check_nil_comparison_for_refute({:==, _meta, [nil, right]}) do
    {:verbose, "refute is_nil(#{Macro.to_string(right)})"}
  end

  defp check_nil_comparison_for_refute({:!=, _meta, [{:__aliases__, _alias_meta, [nil]}, right]}) do
    {:verbose, "assert is_nil(#{Macro.to_string(right)})"}
  end

  defp check_nil_comparison_for_refute({:==, _meta, [{:__aliases__, _alias_meta, [nil]}, right]}) do
    {:verbose, "refute is_nil(#{Macro.to_string(right)})"}
  end

  defp check_nil_comparison_for_refute(_ignored), do: :ok

  defp issue_for(issue_meta, line_no, message) do
    format_issue(
      issue_meta,
      message: message,
      line_no: line_no || 1
    )
  end
end
