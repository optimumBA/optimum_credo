defmodule OptimumCredo.Check.Warning.SkippedTest do
  @moduledoc """
  A check that finds skipped tests via `@tag :skip` or `@moduletag :skip`.

  Skipped tests hide failures and erode the test suite over time. Every skipped
  test should either be fixed and re-enabled, or deleted entirely.

  ## Param: `allow_with_comment`

  When set to `true`, the check does NOT fire if a non-empty comment appears on
  the same line as the `@tag` or `@moduletag` annotation. This lets teams
  annotate intentionally-skipped tests with a reason (e.g. `@tag :skip # TODO #123`).

  Default: `false` — fire unconditionally, regardless of inline comments.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [allow_with_comment: false],
    explanations: [
      check: """
      Skipped tests (`@tag :skip`, `@tag skip: true`, `@moduletag :skip`, etc.)
      hide failures and erode the test suite over time.

      Every skipped test should either be fixed and re-enabled, or deleted entirely.

      ## Examples

      **Bad:**
      ```elixir
      @tag :skip
      test "something" do
        assert 1 == 2
      end
      ```

      **Good:**
      ```elixir
      test "something" do
        assert 1 == 1
      end
      ```
      """,
      params: [
        allow_with_comment:
          "When true, skip the check if a non-empty comment follows the @tag on the same line."
      ]
    ]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    allow_with_comment = Params.get(params, :allow_with_comment, __MODULE__)

    Credo.Code.prewalk(
      source_file,
      &traverse(&1, &2, issue_meta, source_file, allow_with_comment)
    )
  end

  defp traverse(ast, issues, issue_meta, source_file, allow_with_comment) do
    case find_skip_issue(ast, issue_meta, source_file, allow_with_comment) do
      nil -> {ast, issues}
      issue -> {ast, [issue | issues]}
    end
  end

  # @tag :skip  /  @moduletag :skip
  defp find_skip_issue(
         {:@, meta, [{tag, _tag_meta, [:skip]}]},
         issue_meta,
         source_file,
         allow_with_comment
       )
       when tag in [:tag, :moduletag] do
    line_no = meta[:line] || 1

    if allow_with_comment && has_comment_on_line?(source_file, line_no) do
      nil
    else
      format_issue(issue_meta, message: skip_message(tag), line_no: line_no)
    end
  end

  # @tag skip: value  /  @moduletag skip: value
  defp find_skip_issue(
         {:@, meta, [{tag, _tag_meta, [[{:skip, _value}]]}]},
         issue_meta,
         source_file,
         allow_with_comment
       )
       when tag in [:tag, :moduletag] do
    line_no = meta[:line] || 1

    if allow_with_comment && has_comment_on_line?(source_file, line_no) do
      nil
    else
      format_issue(issue_meta, message: skip_message(tag), line_no: line_no)
    end
  end

  defp find_skip_issue(_ast, _issue_meta, _source_file, _allow_with_comment), do: nil

  defp skip_message(:tag), do: "Skipped test via @tag :skip — fix or delete the test."

  defp skip_message(:moduletag),
    do: "Skipped test module via @moduletag :skip — fix or delete the test."

  defp has_comment_on_line?(source_file, line_no) do
    line =
      source_file
      |> Credo.SourceFile.source()
      |> String.split("\n")
      |> Enum.at(line_no - 1, "")

    case String.split(line, "#", parts: 2) do
      [_before, comment] -> String.trim(comment) != ""
      [_no_hash] -> false
    end
  end
end
