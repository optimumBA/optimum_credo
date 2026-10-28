defmodule OptimumCredo.Check.Warning.AshUpsertOptions do
  @moduledoc """
  Finds `upsert_identity` / `upsert_fields` without `upsert?: true`.

  In Ash the upsert options are ignored unless `upsert?` is `true`, so a create that sets
  only `upsert_identity` inserts a duplicate row (or raises) instead of upserting.

  **Gated by `ash: true`.** The check does nothing unless you set `ash: true`.

  Two forms are read:

  - options keyword lists in calls (`Ash.create(changeset, upsert_identity: :unique_email)`,
    `Ash.bulk_create(...)`) that contain `upsert_identity:` or `upsert_fields:` but no
    `upsert?: true`;
  - resource DSL actions: a `do` block (`create :register do ... end`) with
    `upsert_identity` or `upsert_fields` but no `upsert? true`.

  A call is judged as a whole, so `create :x, upsert_identity: :y do upsert? true end` is fine.
  Options passed in a variable or an `upsert?:` set through a variable are treated as valid.

  ## Parameters

  - `ash`: default `false`; set `true` to enable.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [ash: false],
    explanations: [
      check: """
      `upsert_identity` and `upsert_fields` need `upsert?: true`.

      ## Bad

      ```elixir
      Ash.create!(changeset, upsert_identity: :unique_email)
      ```

      ## Good

      ```elixir
      Ash.create!(changeset, upsert?: true, upsert_identity: :unique_email)
      ```

      Set `ash: true` to enable the check.
      """,
      params: [ash: "Enable the Ash heuristics (default false)."]
    ]

  alias OptimumCredo.OptimumDataSupport

  @upsert_options [:upsert_identity, :upsert_fields]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    if Params.get(params, :ash, __MODULE__) == true do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.SourceFile.ast()
      |> offenders()
      |> Enum.map(fn {option, meta} ->
        format_issue(issue_meta,
          message: "`#{option}` has no effect without `upsert?: true`.",
          trigger: Atom.to_string(option),
          line_no: OptimumDataSupport.line(meta)
        )
      end)
    else
      []
    end
  end

  defp offenders(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {_name, meta, args} = node, acc when is_list(args) ->
          {node, upsert_offenders(args, meta) ++ acc}

        node, acc ->
          {node, acc}
      end)

    Enum.sort_by(found, fn {_option, meta} -> OptimumDataSupport.line(meta) end)
  end

  # One call is judged as a whole: `create :x, upsert_identity: :y do upsert? true end`
  # enables the upsert in the block even though the option list does not.
  defp upsert_offenders(args, meta) do
    keyword_lists = Enum.filter(args, &OptimumDataSupport.keyword_literal?/1)
    statements = block_statements(args)

    if upsert_enabled?(keyword_lists, statements) do
      []
    else
      keyword_offenders(keyword_lists, meta) ++
        for {option, statement_meta, [_value]} <- statements,
            option in @upsert_options,
            do: {option, statement_meta}
    end
  end

  defp block_statements(args) do
    case List.last(args) do
      [{:do, body} | _tail] -> OptimumDataSupport.statements(body)
      _other -> []
    end
  end

  # `upsert?` set to anything but a literal `false`, as an option or a DSL statement.
  defp upsert_enabled?(keyword_lists, statements) do
    Enum.any?(keyword_lists, &(Keyword.get(&1, :upsert?, false) != false)) or
      Enum.any?(statements, &match?({:upsert?, _, [value]} when value != false, &1))
  end

  defp keyword_offenders(keyword_lists, meta) do
    for options <- keyword_lists,
        [{option, _value} | _tail] <- [Keyword.take(options, @upsert_options)],
        do: {option, meta}
  end
end
