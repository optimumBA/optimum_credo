defmodule OptimumCredo.Check.Warning.AsyncFalseWithoutComment do
  @moduledoc """
  Finds `use SomeCase, async: false` in test files without an explanatory comment.

  A comment counts when it sits on the line directly above the `use`, or anywhere on the
  lines the `use` expression spans. Heuristic: only `use` of a module whose last segment
  ends with `case_suffix` (after resolving `alias ..., as:`) and a literal `async: false`
  are considered.
  `@moduletag :timing` exempts the file.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [require_comment: true, case_suffix: "Case", exempt_moduletag: :timing],
    explanations: [
      check: """
      `async: false` serialises the suite. Keep tests async and isolate the one test that
      needs global state; when `async: false` is truly required, say why in a comment.

      Bad:

          use MyApp.DataCase, async: false

      Good:

          # Mutates the global application env
          use MyApp.DataCase, async: false
      """,
      params: [
        require_comment:
          "When true (default) a comment suppresses the issue; when false every `async: false` is reported.",
        case_suffix: "Only `use` of modules whose last segment ends with this suffix.",
        exempt_moduletag: "A `@moduletag` atom that exempts the whole file (false disables)."
      ]
    ]

  alias OptimumCredo.TestsSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    ast = TestsSupport.ast(source_file)

    if TestsSupport.test_file?(source_file) and
         not TestsSupport.moduletag?(ast, Params.get(params, :exempt_moduletag, __MODULE__)) do
      issue_meta = IssueMeta.for(source_file, params)

      options = %{
        suffix: Params.get(params, :case_suffix, __MODULE__),
        require_comment: Params.get(params, :require_comment, __MODULE__),
        comments: TestsSupport.comments(source_file)
      }

      ast
      |> TestsSupport.walk_env([], &scan(&1, &2, &3, options))
      |> Enum.reverse()
      |> Enum.map(fn line ->
        format_issue(issue_meta,
          message:
            "`async: false` without a comment explaining why; keep tests async or justify it.",
          line_no: line
        )
      end)
    else
      []
    end
  end

  defp scan({:use, meta, [target | rest]} = node, env, acc, options) do
    module = TestsSupport.resolve_module(target, env)

    if flagged_use?(module, rest, node, meta, options),
      do: {:cont, [meta[:line] || 1 | acc]},
      else: {:cont, acc}
  end

  defp scan(_node, _env, acc, _options), do: {:cont, acc}

  defp flagged_use?(module, rest, node, meta, options) do
    module != nil and case?(module, options.suffix) and async_false?(rest) and
      not (options.require_comment and commented?(options.comments, node, meta[:line] || 1))
  end

  defp case?(module, suffix) do
    module
    |> String.split(".")
    |> List.last()
    |> String.ends_with?(suffix)
  end

  defp async_false?(rest) do
    case List.last(rest) do
      options when is_list(options) -> Keyword.keyword?(options) and options[:async] == false
      _other -> false
    end
  end

  defp commented?(comments, node, line) do
    {_first, last} = TestsSupport.line_span(node)

    Enum.any?(comments, fn c ->
      c.text != "" and
        ((c.line == line - 1 and c.own_line?) or (c.line >= line and c.line <= last))
    end)
  end
end
