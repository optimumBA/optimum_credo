defmodule OptimumCredo.Check.Readability.TestNameRepeatsSubject do
  @moduledoc """
  Finds `test` names that repeat the function already named by their `describe`.

  Only `describe "name/arity"` blocks are considered. The function name is matched as a
  whole word inside the test's literal text. Short names are skipped
  (`min_subject_length`) because common words such as `get` produce false positives.
  A subject that is a plain English word (no underscore, `?` or `!`, such as `index` or
  `enqueue`) is only matched when the name starts with it or it appears as code
  (`index/2`, `index(`, backticks): mid-sentence it is ordinary prose ("returns the index of").
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [min_subject_length: 5, ignore_paths: ["test/support/"]],
    explanations: [
      check: """
      The `describe` already names the function, so the test name should state the
      behaviour only.

      Bad:

          describe "calc_lines/1" do
            test "calc_lines/1 returns zero for blank input" do

      Good:

          describe "calc_lines/1" do
            test "returns zero for blank input" do
      """,
      params: [
        min_subject_length: "Function names shorter than this are not checked.",
        ignore_paths: "Path fragments to skip."
      ]
    ]

  alias OptimumCredo.TestsSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    if TestsSupport.test_file?(source_file) and
         not TestsSupport.path_matches?(
           source_file,
           Params.get(params, :ignore_paths, __MODULE__)
         ) do
      issue_meta = IssueMeta.for(source_file, params)
      min = Params.get(params, :min_subject_length, __MODULE__)

      source_file
      |> TestsSupport.ast()
      |> TestsSupport.blocks([:describe])
      |> Enum.flat_map(&issues_for(&1, issue_meta, min))
    else
      []
    end
  end

  defp issues_for(%{name: name, body: body}, issue_meta, min) when is_binary(name) do
    case Regex.run(~r/^(\w+[?!]?)\/\d+$/, name) do
      [_first, subject] when byte_size(subject) >= min ->
        word = word_regex(subject)

        body
        |> TestsSupport.blocks([:test])
        |> Enum.filter(&Regex.match?(word, TestsSupport.name_text(&1.name)))
        |> Enum.map(fn test ->
          format_issue(issue_meta,
            message: "Test name repeats #{subject}, already named by describe #{inspect(name)}.",
            line_no: test.line
          )
        end)

      _other ->
        []
    end
  end

  defp issues_for(_describe, _issue_meta, _min), do: []

  defp word_regex(subject) do
    escaped = Regex.escape(subject)

    if Regex.match?(~r/^[a-z]+$/, subject) do
      Regex.compile!("^#{escaped}(?![\\w])|`#{escaped}`|(?<![\\w])#{escaped}(?:/\\d|\\()")
    else
      Regex.compile!("(?<![\\w])#{escaped}(?![\\w])")
    end
  end
end
