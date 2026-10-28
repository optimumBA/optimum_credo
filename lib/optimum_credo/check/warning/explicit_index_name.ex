defmodule OptimumCredo.Check.Warning.ExplicitIndexName do
  @moduledoc """
  Finds `create index(...)` / `create unique_index(...)` calls in migrations that pass an
  explicit `name:` for a single-column index.

  Ecto infers a truthful name (`users_email_index`) from the table and column. A hand-written
  name can drift from the column it covers and has to be repeated when the index is dropped.

  ## Parameters

  - `allow_multi_column`: default `true`. Inferred names for several columns get long
    (Postgres truncates identifiers at 63 bytes), so explicit names are accepted for them.
    Set `false` to report them too.
  - `allow_partial_indexes`: default `true`. An index with `where:` usually needs a name of
    its own so it can live next to a full index on the same column. Set `false` to report
    those too.
  - `ignore_files`: path suffixes or regexes of legacy migrations to skip.

  A name is also accepted when the inferred one (`<table>_<column>_index`) would exceed
  Postgres' 63-byte identifier limit.

  Indexes over expressions (string columns such as `"lower(email)"`) are always accepted
  because they have no inferred name. `drop index(...)` is not inspected: it must repeat
  whatever name the index was created with. Indexes built from variables or helper
  functions are not analysed.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [allow_multi_column: true, allow_partial_indexes: true, ignore_files: []],
    explanations: [
      check: """
      Let Ecto infer index names for single-column indexes.

      ## Bad

      ```elixir
      create unique_index(:users, [:email], name: :users_email_unique)
      ```

      ## Good

      ```elixir
      create unique_index(:users, [:email])
      ```

      Multi-column indexes and expression indexes may need an explicit name.
      """,
      params: [
        allow_multi_column: "Accept explicit names for indexes over several columns.",
        allow_partial_indexes: "Accept explicit names for indexes with a `where:` clause.",
        ignore_files: "Path suffixes or regexes for migrations to skip."
      ]
    ]

  alias OptimumCredo.OptimumDataSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    ignore_files = Params.get(params, :ignore_files, __MODULE__)

    if OptimumDataSupport.migration?(source_file) and
         not OptimumDataSupport.ignored_file?(source_file, ignore_files) do
      index_issues(source_file, params)
    else
      []
    end
  end

  defp index_issues(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    allow_multi_column = Params.get(params, :allow_multi_column, __MODULE__)
    allow_partial = Params.get(params, :allow_partial_indexes, __MODULE__)

    source_file
    |> Credo.SourceFile.ast()
    |> named_indexes()
    |> Enum.filter(fn {columns, table, partial?, _meta} ->
      !(partial? and allow_partial) and reportable?(columns, allow_multi_column) and
        not too_long?(table, columns)
    end)
    |> Enum.map(fn {_columns, _table, _partial?, meta} ->
      format_issue(issue_meta,
        message:
          "Let Ecto infer the index name; pass `name:` only for multi-column or expression indexes.",
        trigger: "name:",
        line_no: OptimumDataSupport.line(meta)
      )
    end)
  end

  defp named_indexes(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {create, _meta, [{index, meta, [table | rest] = args}]} = node, acc
        when create in [:create, :create_if_not_exists] and index in [:index, :unique_index] ->
          case OptimumDataSupport.fetch_option(args, :name) do
            {:ok, _name} ->
              partial? = OptimumDataSupport.fetch_option(args, :where) != :error
              {node, [{columns(rest), table, partial?, meta} | acc]}

            :error ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  defp columns([column | _tail]) when is_atom(column), do: [column]
  defp columns([[_head | _tail] = columns | _tail2]), do: columns
  defp columns(_other), do: []

  defp too_long?(table, [column]) when is_atom(column) and (is_atom(table) or is_binary(table)),
    do: byte_size("#{table}_#{column}_index") > 63

  defp too_long?(_table, _columns), do: false

  # Only plain atom columns have an inferred name; unknown shapes are left alone.
  defp reportable?([column], _allow_multi_column), do: is_atom(column)

  defp reportable?([_first, _head | _tail] = columns, allow_multi_column),
    do: not allow_multi_column and Enum.all?(columns, &is_atom/1)

  defp reportable?([], _allow_multi_column), do: false
end
