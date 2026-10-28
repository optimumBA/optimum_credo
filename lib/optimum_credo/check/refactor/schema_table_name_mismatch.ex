defmodule OptimumCredo.Check.Refactor.SchemaTableNameMismatch do
  @moduledoc """
  Finds `schema "table"` declarations whose table name is not the plural of the
  schema module's last segment.

  `MyApp.Accounts.Question` is expected to use `"questions"`, not `"user_questions"`:
  a schema named after a different concept than its table is hard to find and invites
  confusion. The comparison uses small English pluralisation rules (regular `s`/`es`/`ies`
  plurals and a short irregular list) and is deliberately tolerant: either
  `plural(module) == table` or `singular(table) == module` is accepted.

  A table whose every word is the plural of the matching module word is accepted too
  (`MyApp.Accounts.UserToken` with `"users_tokens"`, the table `mix phx.gen.auth` generates).

  Projects that prefix every table with its context to keep contexts apart
  (`MyApp.Library.Follow` with `"library_follows"`, `MyApp.Memberships.Reservation` with
  `"membership_reservations"`) can opt in with `allow_context_prefix: true`. Only the context
  that actually contains the schema counts as a prefix: `MyApp.Accounts.Question` with
  `"user_questions"` is still reported.

  Skipped: `embedded_schema` (no table), non-literal table names, a schema prefix
  (`"public.users"` is compared as `"users"`), and modules that set
  `@credo_table_name_ok true` for legacy tables.

  ## Parameters

  - `allow_context_prefix`: accept `"<context>_<plural>"` tables, default `false`.
  - `custom_inflections`: map of singular word to plural word for domain words the rules get
    wrong, for example `%{"person" => "people", "datum" => "datasets"}`. Words in snake_case.

  Inflection is a heuristic: unusual plurals not in the list or in `custom_inflections`
  are reported.
  """

  use Credo.Check,
    base_priority: :low,
    category: :refactor,
    param_defaults: [custom_inflections: %{}, allow_context_prefix: false],
    explanations: [
      check: """
      Name the schema after its table (singular of the table name).

      ## Bad

      ```elixir
      defmodule MyApp.Quiz.Question do
        use Ecto.Schema

        schema "user_questions" do
        end
      end
      ```

      ## Good

      ```elixir
      defmodule MyApp.Quiz.Question do
        use Ecto.Schema

        schema "questions" do
        end
      end
      ```

      Legacy tables can opt out with `@credo_table_name_ok true` in the module.
      """,
      params: [
        allow_context_prefix:
          "Accept a table named `<context>_<plural of schema>`, for example `library_follows` for `Library.Follow`.",
        custom_inflections:
          "Map of singular => plural snake_case words for irregular domain words."
      ]
    ]

  alias OptimumCredo.OptimumDataSupport

  @irregular %{
    "person" => "people",
    "child" => "children",
    "man" => "men",
    "woman" => "women",
    "mouse" => "mice",
    "foot" => "feet",
    "tooth" => "teeth",
    "goose" => "geese",
    "datum" => "data",
    "medium" => "media",
    "criterion" => "criteria",
    "analysis" => "analyses",
    "index" => "indices",
    "series" => "series",
    "species" => "species",
    "news" => "news",
    "equipment" => "equipment",
    "information" => "information",
    "quiz" => "quizzes",
    "data" => "data",
    "metadata" => "metadata",
    "sheep" => "sheep",
    "fish" => "fish",
    "matrix" => "matrices",
    "vertex" => "vertices"
  }

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    inflections =
      params
      |> Params.get(:custom_inflections, __MODULE__)
      |> inflections()

    context_prefix? = Params.get(params, :allow_context_prefix, __MODULE__)

    source_file
    |> Credo.SourceFile.ast()
    |> OptimumDataSupport.modules()
    |> Enum.flat_map(fn {name, body} -> schemas(name, OptimumDataSupport.statements(body)) end)
    |> Enum.reject(&accepted?(&1, inflections, context_prefix?))
    |> Enum.map(&mismatch_issue(&1, inflections, issue_meta))
  end

  defp accepted?({name, table, _meta, context}, inflections, context_prefix?) do
    table_matches?(name, table, inflections) or
      (context_prefix? and context_prefixed?(name, table, context, inflections))
  end

  defp mismatch_issue({name, table, meta, _context}, inflections, issue_meta) do
    format_issue(issue_meta,
      message:
        "Schema #{Macro.camelize(name)} uses table #{inspect(table)}; " <>
          "name the schema after the table (expected #{inspect(plural(name, inflections))}).",
      trigger: table,
      line_no: OptimumDataSupport.line(meta)
    )
  end

  defp schemas({:__aliases__, _meta, segments}, statements) when is_list(segments) do
    last = List.last(segments)
    context = context(segments)

    if is_atom(last) and not opted_out?(statements) do
      for {:schema, meta, [table | _tail]} <- statements, is_binary(table) do
        {last
         |> Atom.to_string()
         |> Macro.underscore(),
         table
         |> String.split(".")
         |> List.last(), meta, context}
      end
    else
      []
    end
  end

  defp schemas(_name, _statements), do: []

  defp context(segments) do
    case Enum.take(segments, -2) do
      [context, _schema] when is_atom(context) ->
        context
        |> Atom.to_string()
        |> Macro.underscore()

      _no_context ->
        nil
    end
  end

  defp opted_out?(statements) do
    Enum.any?(statements, &match?({:@, _, [{:credo_table_name_ok, _, [true]}]}, &1))
  end

  defp inflections(custom) do
    then(
      for {singular, plural} <- Enum.to_list(custom || %{}), into: %{} do
        {to_string(singular), to_string(plural)}
      end,
      &Map.merge(@irregular, &1)
    )
  end

  defp table_matches?(name, table, inflections) do
    table == plural(name, inflections) or name in singular_candidates(table, inflections) or
      every_word_plural?(name, table, inflections)
  end

  # `user_token` and `users_tokens`: each table word is the module word or its plural.
  defp every_word_plural?(name, table, inflections) do
    name_words = String.split(name, "_")
    table_words = String.split(table, "_")

    length(name_words) > 1 and length(name_words) == length(table_words) and
      name_words
      |> Enum.zip(table_words)
      |> Enum.all?(fn {word, table_word} ->
        table_word in [word, pluralize(word, inflections)]
      end)
  end

  # `Library.Follow` in `library_follows`: the context (or its singular) prefixes the table.
  defp context_prefixed?(_name, _table, nil, _inflections), do: false

  defp context_prefixed?(name, table, context, inflections) do
    prefixes = [context | regular_singulars(context)]

    Enum.any?(prefixes, fn prefix ->
      String.starts_with?(table, prefix <> "_") and
        table_matches?(name, String.replace_prefix(table, prefix <> "_", ""), inflections)
    end)
  end

  # Inflect only the last `_`-separated word: `user_story` => `user_stories`.
  defp plural(name, inflections) do
    {prefix, word} = split_last(name)
    prefix <> pluralize(word, inflections)
  end

  defp singular_candidates(table, inflections) do
    {prefix, word} = split_last(table)

    irregular = for {singular, plural} <- inflections, plural == word, do: singular

    Enum.map(irregular ++ regular_singulars(word), &(prefix <> &1))
  end

  defp split_last(name) do
    case String.split(name, "_") do
      [word] ->
        {"", word}

      parts ->
        prefix =
          parts
          |> Enum.drop(-1)
          |> Enum.join("_")

        {prefix <> "_", List.last(parts)}
    end
  end

  defp pluralize(word, inflections) do
    cond do
      plural = inflections[word] -> plural
      String.ends_with?(word, ["s", "x", "z", "ch", "sh"]) -> word <> "es"
      Regex.match?(~r/[^aeiou]y$/, word) -> String.replace_suffix(word, "y", "ies")
      true -> word <> "s"
    end
  end

  defp regular_singulars(word) do
    Enum.reject(
      [
        if(String.ends_with?(word, "ies"), do: String.replace_suffix(word, "ies", "y")),
        if(String.ends_with?(word, "ves"), do: String.replace_suffix(word, "ves", "f")),
        if(String.ends_with?(word, "ves"), do: String.replace_suffix(word, "ves", "fe")),
        if(String.ends_with?(word, "oes"), do: String.replace_suffix(word, "oes", "o")),
        if(String.ends_with?(word, ["ses", "xes", "zes", "ches", "shes"]),
          do: String.replace_suffix(word, "es", "")
        ),
        if(String.ends_with?(word, "s") and not String.ends_with?(word, "ss"),
          do: String.replace_suffix(word, "s", "")
        )
      ],
      &is_nil/1
    )
  end
end
