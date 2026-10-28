defmodule OptimumCredo.Check.Readability.TestNameLowercase do
  @moduledoc """
  Finds `test` and `describe` names that start with an uppercase letter.

  Names starting with a backtick, digit, slash or other non-letter are fine. By default a
  leading all-caps word of two or more characters (`API`, `HTTP`) is treated as an
  acronym and accepted, as is a leading qualified function reference (`Accounts.create/1`)
  and a leading CamelCase identifier (`PubSub`, `WebSocket`, `LiveView`), which names a
  module or product and cannot be lowercased. Single capitalised words (`Javascript`) are
  still reported; list them in `allowed_prefixes` if they are proper nouns.
  Names that begin with an interpolation are skipped.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [
      allow_acronyms: true,
      allow_camel_case: true,
      allowed_prefixes: [],
      ignore_paths: ["test/support/"]
    ],
    explanations: [
      check: """
      Test names complete a sentence about behaviour and start lowercase.

      Bad:   test "Returns an error" do
      Good:  test "returns an error" do
      """,
      params: [
        allow_acronyms: "Accept a leading all-caps word such as `API`.",
        allow_camel_case: "Accept a leading CamelCase identifier such as `PubSub`.",
        allowed_prefixes: "Name prefixes that are always accepted.",
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
      acronyms? = Params.get(params, :allow_acronyms, __MODULE__)
      camel? = Params.get(params, :allow_camel_case, __MODULE__)
      prefixes = Params.get(params, :allowed_prefixes, __MODULE__)

      source_file
      |> TestsSupport.ast()
      |> TestsSupport.blocks([:test, :describe])
      |> Enum.filter(fn block ->
        text = TestsSupport.leading_text(block.name)
        text != nil and uppercase_start?(text, acronyms?, camel?, prefixes)
      end)
      |> Enum.map(fn block ->
        format_issue(issue_meta,
          message:
            "#{block.kind} name #{inspect(TestsSupport.name_text(block.name))} should start lowercase.",
          line_no: block.line
        )
      end)
    else
      []
    end
  end

  defp uppercase_start?(text, acronyms?, camel?, prefixes) do
    text = String.trim_leading(text)

    cond do
      Enum.any?(prefixes, &String.starts_with?(text, &1)) -> false
      not Regex.match?(~r/^\p{Lu}/u, text) -> false
      Regex.match?(~r/^\p{Lu}\w*(\.\w+[?!]?)+/u, text) -> false
      acronyms? and Regex.match?(~r/^[\p{Lu}\d]{2,}(\W|$)/u, text) -> false
      camel? and Regex.match?(~r/^\p{Lu}\p{Ll}+\p{Lu}\w*(\W|$)/u, text) -> false
      true -> true
    end
  end
end
