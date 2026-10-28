defmodule OptimumCredo.Check.Warning.NotNullWithoutDefault do
  @moduledoc """
  Finds `add :column, type, null: false` without a `default:` inside `alter table` blocks.

  Adding a `NOT NULL` column without a default fails on a table that already has rows.
  Either give the column a default, or add it as nullable, backfill, and then set
  `null: false` in a follow-up step.

  This is a heuristic. The check cannot see migration history, so it cannot know whether
  the table is empty or was created in the same release; it only reports `add` and
  `add_if_not_exists` inside `alter table` (never inside `create table`). It does not
  report `modify ..., null: false` (a backfill may legitimately precede it), nor does it
  look for a backfill elsewhere in the migration.

  An `alter table` of a table that the same migration creates is skipped (it is empty).

  `default: nil` does not count as a default. A `default:` given through a variable does.

  ## Parameters

  - `ignore_files`: path suffixes or regexes of migrations known to run on empty tables.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [ignore_files: []],
    explanations: [
      check: """
      Adding a NOT NULL column to an existing table needs a default or a backfill.

      ## Bad

      ```elixir
      alter table(:users) do
        add :status, :string, null: false
      end
      ```

      ## Good

      ```elixir
      alter table(:users) do
        add :status, :string, null: false, default: "active"
      end
      ```

      Heuristic: table contents and migration history are unknown to the check.
      """,
      params: [ignore_files: "Path suffixes or regexes for migrations to skip."]
    ]

  alias OptimumCredo.OptimumDataSupport

  @add_functions [:add, :add_if_not_exists]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    ignore_files = Params.get(params, :ignore_files, __MODULE__)

    if OptimumDataSupport.migration?(source_file) and
         not OptimumDataSupport.ignored_file?(source_file, ignore_files) do
      issue_meta = IssueMeta.for(source_file, params)

      ast = Credo.SourceFile.ast(source_file)
      created = created_tables(ast)

      ast
      |> alter_blocks(created)
      |> Enum.flat_map(&OptimumDataSupport.statements/1)
      |> Enum.filter(&not_null_without_default?/1)
      |> Enum.map(fn {_add, meta, [column | _tail]} ->
        format_issue(issue_meta,
          message:
            "Column #{inspect(column)} is added `null: false` without a default; " <>
              "this fails on populated tables. Add a default or backfill first.",
          trigger: "null: false",
          line_no: OptimumDataSupport.line(meta)
        )
      end)
    else
      []
    end
  end

  # A table created by the same migration is empty when it is altered.
  defp created_tables(ast) do
    {_ast, tables} =
      Macro.prewalk(ast, [], fn
        {create, _meta, [{:table, _table_meta, [table | _tail]} | _tail2]} = node, acc
        when create in [:create, :create_if_not_exists] and (is_atom(table) or is_binary(table)) ->
          {node, [to_string(table) | acc]}

        node, acc ->
          {node, acc}
      end)

    tables
  end

  defp alter_blocks(ast, created) do
    {_ast, bodies} =
      Macro.prewalk(ast, [], fn
        {:alter, _meta, [{:table, _table_meta, [table | _tail]}, [do: body]]} = node, acc
        when is_atom(table) or is_binary(table) ->
          if to_string(table) in created, do: {node, acc}, else: {node, [body | acc]}

        {:alter, _meta, [_table, [do: body]]} = node, acc ->
          {node, [body | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(bodies)
  end

  defp not_null_without_default?({function, _meta, [_column, _type | _tail] = args})
       when function in @add_functions do
    OptimumDataSupport.fetch_option(args, :null) == {:ok, false} and not default?(args)
  end

  defp not_null_without_default?(_statement), do: false

  defp default?(args) do
    case OptimumDataSupport.fetch_option(args, :default) do
      {:ok, nil} -> false
      {:ok, _value} -> true
      :error -> false
    end
  end
end
