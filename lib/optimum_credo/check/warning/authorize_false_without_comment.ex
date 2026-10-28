defmodule OptimumCredo.Check.Warning.AuthorizeFalseWithoutComment do
  @moduledoc """
  Finds `authorize?: false` without a comment on the same line.

  Skipping Ash authorization should be rare and deliberate. A short trailing comment saying
  why (`authorize?: false # system job, no actor`) makes every bypass reviewable.

  **Gated by `ash: true`.** The check does nothing unless you set `ash: true`.

  The scan is line-based on source text with strings, heredocs and sigils blanked, so
  occurrences in documentation or string literals are not reported, while code in
  comments is not code. It reports every `authorize?: false` outside `ignore_paths`
  (default `test/` and `priv/repo/seeds`), outside files named `*fixtures.ex`, and outside
  modules whose name ends in `Fixtures`. The comment must be on the same line as
  `authorize?: false`; a comment on the preceding line does not count.

  ## Parameters

  - `ash`: default `false`; set `true` to enable.
  - `ignore_paths`: directories or path fragments skipped entirely.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [ash: false, ignore_paths: ["test/", "priv/repo/seeds"]],
    explanations: [
      check: """
      Explain every `authorize?: false` with a comment on the same line.

      ## Bad

      ```elixir
      Ash.read!(Post, authorize?: false)
      ```

      ## Good

      ```elixir
      Ash.read!(Post, authorize?: false) # background job, no actor
      ```

      Set `ash: true` to enable the check.
      """,
      params: [
        ash: "Enable the Ash heuristics (default false).",
        ignore_paths: "Directories or path fragments that are not checked."
      ]
    ]

  alias OptimumCredo.OptimumDataSupport

  @authorize_false ~r/\bauthorize\?:\s*false\b/

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    if Params.get(params, :ash, __MODULE__) == true and checked_file?(source_file, params) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> OptimumDataSupport.code_and_comment_lines()
      |> Enum.filter(fn {_line_no, code, comment} ->
        is_nil(comment) and Regex.match?(@authorize_false, code)
      end)
      |> Enum.map(fn {line_no, _code, _comment} ->
        format_issue(issue_meta,
          message:
            "`authorize?: false` needs a same-line comment explaining why authorization is skipped.",
          trigger: "authorize?: false",
          line_no: line_no
        )
      end)
    else
      []
    end
  end

  defp checked_file?(source_file, params) do
    ignored = Params.get(params, :ignore_paths, __MODULE__)

    not (OptimumDataSupport.in_any_dir?(source_file, ignored) or fixtures?(source_file))
  end

  defp fixtures?(source_file) do
    source_file
    |> OptimumDataSupport.normalized_path()
    |> String.ends_with?("fixtures.ex") or
      source_file
      |> Credo.SourceFile.ast()
      |> OptimumDataSupport.modules()
      |> Enum.any?(&fixtures_module?/1)
  end

  defp fixtures_module?({name, _body}) do
    name
    |> OptimumDataSupport.last_segment()
    |> to_string()
    |> String.ends_with?("Fixtures")
  end
end
