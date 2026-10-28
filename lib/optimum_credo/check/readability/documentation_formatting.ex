defmodule OptimumCredo.Check.Readability.DocumentationFormatting do
  @moduledoc """
  A check that ensures proper formatting in function documentation.

  This check enforces:
  - Blank line after section headers like `## Examples` in @doc strings
  - Consistent spacing in documentation blocks
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    explanations: [
      check: """
      Function documentation should have proper spacing for readability.

      ## Examples

      **Bad:**
      ```elixir
      @doc \"\"\"
      Returns the index URL.

      ## Examples
      iex> index_url()
      "http://localhost:4000/index.md"
      \"\"\"
      def index_url do
        # ...
      end
      ```

      **Good:**
      ```elixir
      @doc \"\"\"
      Returns the index URL.

      ## Examples

      iex> index_url()
      "http://localhost:4000/index.md"
      \"\"\"
      def index_url do
        # ...
      end
      ```
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

  defp traverse({:@, meta, [{:doc, _meta, [doc_string]}]} = ast, issues, issue_meta)
       when is_binary(doc_string) do
    new_issues = check_doc_formatting(doc_string, meta[:line], issue_meta)
    {ast, issues ++ new_issues}
  end

  defp traverse(ast, issues, _issue_meta) do
    {ast, issues}
  end

  defp check_doc_formatting(doc_string, line_no, issue_meta) do
    lines = String.split(doc_string, "\n")

    issues =
      for {line, index} <- Enum.with_index(lines),
          String.match?(line, ~r/^\s*##\s+\w+/),
          next_line = Enum.at(lines, index + 1),
          String.trim(next_line) != "" do
        issue_for(
          issue_meta,
          line_no + index + 1,
          "Missing blank line after documentation section header (#{String.trim(line)})"
        )
      end

    Enum.reverse(issues)
  end

  defp issue_for(issue_meta, line_no, message) do
    format_issue(
      issue_meta,
      message: message,
      line_no: line_no
    )
  end
end
