defmodule OptimumCredo.Check.Readability.EmptySetupBlock do
  @moduledoc """
  A check that finds empty `setup` blocks in test files.

  An empty `setup` block provides no value and adds visual noise to test files.
  The following bodies are considered empty:

  - `setup do :ok end`
  - `setup do end` (parses to `nil`)
  - `setup do {:ok, %{}} end` (returns an empty context map)
  - `setup context do :ok end` (with-argument variant of the above)

  The atom-shorthand form `setup :function_name` is NOT flagged — it delegates
  to a real function and is never empty by definition.

  This check is file-scoped: it only runs on `*_test.exs` files and files under
  `test/support/`.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    explanations: [
      check: """
      Empty `setup` blocks add noise to test files without providing any value.
      Remove them to keep tests concise.

      ## Examples

      **Bad:**
      ```elixir
      setup do
        :ok
      end
      ```

      **Good:**
      ```elixir
      # No setup block needed — remove it entirely, or add real test setup.
      ```
      """
    ]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    filename = source_file.filename || ""

    if test_file?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp test_file?(filename) do
    String.ends_with?(filename, "_test.exs") or String.contains?(filename, "test/support/")
  end

  defp traverse(ast, issues, issue_meta) do
    case find_empty_setup(ast, issue_meta) do
      nil -> {ast, issues}
      issue -> {ast, [issue | issues]}
    end
  end

  # setup do <body> end  (no argument)
  defp find_empty_setup({:setup, meta, [[do: body]]}, issue_meta) do
    if empty_body?(body) do
      format_issue(issue_meta,
        message: "Empty `setup` block — remove it or add real test setup.",
        line_no: meta[:line] || 1
      )
    end
  end

  # setup context do <body> end  (with argument)
  defp find_empty_setup({:setup, meta, [_arg, [do: body]]}, issue_meta) do
    if empty_body?(body) do
      format_issue(issue_meta,
        message: "Empty `setup` block — remove it or add real test setup.",
        line_no: meta[:line] || 1
      )
    end
  end

  defp find_empty_setup(_ast, _issue_meta), do: nil

  # setup do end  →  nil
  defp empty_body?(nil), do: true

  # setup do :ok end
  defp empty_body?(:ok), do: true

  # setup do end  →  {:__block__, [], []}
  defp empty_body?({:__block__, _meta, []}), do: true

  # setup do {:ok, %{}} end
  defp empty_body?({:ok, {:%{}, _meta, []}}), do: true

  defp empty_body?(_body), do: false
end
