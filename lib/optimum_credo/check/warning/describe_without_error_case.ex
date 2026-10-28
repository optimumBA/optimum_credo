defmodule OptimumCredo.Check.Warning.DescribeWithoutErrorCase do
  @moduledoc """
  Finds `describe` blocks with several tests but no visible sad path.

  A describe counts as covering a sad path when a test name contains one of `error_words`
  (including absence wording such as `non-existent`, `does not exist`, `expired`, `unknown`),
  or a test body mentions an error atom (`error_atoms`), an HTTP 4xx/5xx status in a status
  position (`json_response(conn, 404)`, `status: 422`, `conn.status == 403`,
  `assert_error_sent 404`), `assert_raise`/`catch_*`, or any call, variable or module
  attribute whose name contains an error word (`errors_on/1`, `assert_forbidden/1`,
  `@invalid_attrs`). Bare integers such as `500` elsewhere do not count.

  Words and phrases match whole words, case-insensitively, with an optional `s`/`es`/`ed`/`d`/`ing`
  ending for words longer than four letters (`error` matches `errors`, `reject` matches `rejected`). Hyphens, underscores and
  spaces are interchangeable, so `not found` matches `not_found`. `notifications`, `notes`,
  `existing` or `does broadcast` therefore never count. The bare word `not` is deliberately
  in the defaults: a negated test name ("is not allowed", "does not send") describes a
  refusal, which is the sad path; remove it from `error_words` to require more specific wording.

  Purely lexical: a sad path asserted through an unrelated helper name is invisible, and
  some functions have no error path at all. A describe can document that boundary with
  `@describetag error_path_exemption: "Concrete reason or location of separate error tests"`
  inside its body. Only a nonblank literal reason on that describe is accepted; module
  tags, booleans and tags inside individual tests do not exempt other groups.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [
      min_tests: 2,
      error_words: [
        "error",
        "invalid",
        "fail",
        "not",
        "not found",
        "unauthorized",
        "forbidden",
        "reject",
        "denied",
        "missing",
        "cannot",
        "raise",
        "non-existent",
        "nonexistent",
        "non-existing",
        "nonexisting",
        "does not exist",
        "doesn't exist",
        "expired",
        "unknown"
      ],
      error_atoms: [
        :error,
        :unauthorized,
        :forbidden,
        :not_found,
        :invalid,
        :unprocessable_entity,
        :bad_request,
        :conflict,
        :internal_server_error
      ],
      ignore_paths: ["test/support/"]
    ],
    explanations: [
      check: """
      Test the sad path next to the happy path: not-found, invalid and unauthorised cases.
      This heuristic only looks for textual hints and is meant as a prompt for review.
      """,
      params: [
        min_tests: "Describes with fewer tests are skipped.",
        error_words:
          "Case-insensitive whole words or phrases in a test name or identifier that indicate a sad path.",
        error_atoms: "Atoms in a test body that indicate a sad path.",
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
      describe_issues(source_file, params)
    else
      []
    end
  end

  defp describe_issues(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    min = Params.get(params, :min_tests, __MODULE__)

    words =
      params
      |> Params.get(:error_words, __MODULE__)
      |> Enum.map(&word_pattern/1)

    atoms = Params.get(params, :error_atoms, __MODULE__)

    source_file
    |> TestsSupport.ast()
    |> TestsSupport.blocks([:describe])
    |> Enum.filter(fn describe ->
      tests = TestsSupport.blocks(describe.body, [:test])

      length(tests) >= min and not justified_boundary?(describe.body) and
        not Enum.any?(tests, &sad_path?(&1, words, atoms))
    end)
    |> Enum.map(fn describe ->
      format_issue(issue_meta,
        message:
          "describe #{inspect(TestsSupport.name_text(describe.name))} shows no sad-path test.",
        line_no: describe.line
      )
    end)
  end

  defp justified_boundary?(body) do
    statements =
      case body do
        {:__block__, _meta, statements} -> statements
        statement -> [statement]
      end

    Enum.any?(statements, fn
      {:@, _meta, [{:describetag, _tag_meta, [tags]}]} when is_list(tags) ->
        case Keyword.get(tags, :error_path_exemption) do
          reason when is_binary(reason) -> String.trim(reason) != ""
          _invalid -> false
        end

      _other ->
        false
    end)
  end

  defp sad_path?(test, words, atoms) do
    name =
      test.name
      |> TestsSupport.name_text()
      |> normalize()

    Enum.any?(words, &Regex.match?(&1, name)) or
      TestsSupport.walk_env(
        test.body,
        false,
        fn node, env, acc ->
          {:cont, acc or error_node?(node, TestsSupport.call(node, env), atoms, words)}
        end,
        test.env
      )
  end

  defp error_node?(atom, _call, atoms, _words) when is_atom(atom), do: atom in atoms

  defp error_node?({:status, status}, _call, _atoms, _words), do: status?(status)

  defp error_node?({:@, _meta, [{name, _tuple_meta, context}]}, _call, _atoms, words)
       when is_atom(name) and is_atom(context),
       do: word_in?(name, words)

  defp error_node?({name, _meta, context}, _call, _atoms, words)
       when is_atom(name) and is_atom(context),
       do: word_in?(name, words)

  defp error_node?({op, _meta, [left, right]}, _call, _atoms, _words) when op in [:==, :===],
    do: (status_field?(left) and status?(right)) or (status_field?(right) and status?(left))

  defp error_node?(_node, nil, _atoms, _words), do: false

  defp error_node?(_node, call, _atoms, words) do
    call.fun in [:assert_raise, :catch_error, :catch_exit, :catch_throw] or
      word_in?(call.fun, words) or
      (status_function?(call.fun) and Enum.any?(call.args, &status?/1))
  end

  defp word_in?(name, words) do
    string =
      name
      |> Atom.to_string()
      |> normalize()

    Enum.any?(words, &Regex.match?(&1, string))
  end

  # Hyphens, underscores and whitespace are one separator, so `not found` also matches
  # the identifier `not_found`.
  defp normalize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[\s_-]+/, " ")
  end

  defp word_pattern(word) do
    escaped =
      word
      |> normalize()
      |> Regex.escape()
      |> String.replace("\\ ", " ")

    # Short words take no ending: `not` must not match `notes`.
    ending = if String.length(escaped) > 4, do: "(?:s|es|ed|d|ing)?", else: ""

    Regex.compile!("(?<![\\p{L}\\p{N}])#{escaped}#{ending}(?![\\p{L}\\p{N}])", "u")
  end

  defp status_function?(name),
    do: Regex.match?(~r/(response|status|resp|error_sent)/, Atom.to_string(name))

  defp status_field?({{:., _meta, [_receiver, :status]}, _tuple_meta, []}), do: true
  defp status_field?({:status, _meta, context}) when is_atom(context), do: true
  defp status_field?(_node), do: false

  defp status?(value), do: is_integer(value) and value >= 400 and value < 600
end
