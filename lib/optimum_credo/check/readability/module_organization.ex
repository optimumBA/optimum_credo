defmodule OptimumCredo.Check.Readability.ModuleOrganization do
  @moduledoc """
  A check that ensures blank lines separate different statement groups in modules.

  This check enforces blank line separation between:
  - `use` and `import` statements
  - `import` and `alias` statements  
  - `alias` and `require` statements

  This complements the existing import_order.ex check which handles alphabetical ordering.
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Module organization should follow Phoenix conventions with proper blank line separation
      between different statement types (use, import, alias, require).

      ## Examples

      **Bad:**
      ```elixir
      defmodule MyModule do
        use Supervisor
        import Telemetry.Metrics
        alias MyApp.SomeModule
      end
      ```

      **Good:**
      ```elixir
      defmodule MyModule do
        use Supervisor
        
        import Telemetry.Metrics
        
        alias MyApp.SomeModule
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

  defp traverse({:defmodule, _meta, _children} = ast, issues, issue_meta) do
    new_issues = check_module_organization(ast, issue_meta)
    {ast, issues ++ new_issues}
  end

  defp traverse(ast, issues, _issue_meta) do
    {ast, issues}
  end

  defp check_module_organization(
         {:defmodule, _meta, [_name, [do: {:__block__, _block_meta, statements}]]},
         issue_meta
       ) do
    statements
    |> Enum.with_index()
    |> Enum.reduce([], fn {statement, index}, issues ->
      case check_statement_separation(statement, statements, index) do
        nil -> issues
        issue -> [issue_for(issue_meta, issue.line, issue.message) | issues]
      end
    end)
  end

  defp check_module_organization(_ast, _issue_meta), do: []

  defp check_statement_separation(statement, statements, index) do
    current_type = get_statement_type(statement)
    next_statement = Enum.at(statements, index + 1)

    if next_statement && current_type && should_have_blank_line?(current_type, next_statement) do
      current_line = get_line(statement)
      next_line = get_line(next_statement)

      if next_line - current_line == 1 do
        %{
          line: current_line,
          message:
            "Missing blank line between #{current_type} and #{get_statement_type(next_statement)} statements"
        }
      end
    end
  end

  defp get_statement_type({:use, _meta, _args}), do: "use"
  defp get_statement_type({:import, _meta, _args}), do: "import"
  defp get_statement_type({:alias, _meta, _args}), do: "alias"
  defp get_statement_type({:require, _meta, _args}), do: "require"
  defp get_statement_type(_ignored), do: nil

  defp should_have_blank_line?("use", next) do
    get_statement_type(next) in ["import", "alias", "require"]
  end

  defp should_have_blank_line?("import", next) do
    get_statement_type(next) in ["alias", "require"]
  end

  defp should_have_blank_line?("alias", next) do
    get_statement_type(next) == "require"
  end

  defp should_have_blank_line?(_ignored, _next), do: false

  defp get_line({_type, meta, _args}) do
    meta[:line] || 1
  end

  defp issue_for(issue_meta, line_no, message) do
    format_issue(
      issue_meta,
      message: message,
      line_no: line_no
    )
  end
end
