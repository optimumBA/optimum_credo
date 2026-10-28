defmodule OptimumCredo.Check.Warning.RawSqlIndexInMigration do
  @moduledoc """
  Finds `execute/1,2` calls in migrations that create, drop or alter an index with raw SQL.

  `Ecto.Migration` has an index DSL (`create index(:users, [:email])`,
  `create unique_index(...)`) that is reversible and portable.

  The check reads string literals (plain strings, heredocs, `~s`/`~S` sigils and
  interpolated strings) passed to `execute`, in files under `priv/<repo>/migrations/`.
  SQL comments and quoted string literals are ignored, and each `;`-separated statement is
  judged on its own: only a statement that *starts* with `CREATE/DROP/ALTER [UNIQUE] INDEX`
  counts.

  ## Parameters

  - `allow_concurrent`: default `true`. `CREATE INDEX CONCURRENTLY` cannot be written with
    the DSL in a transaction, so it is accepted.
  - `allow_expression_indexes`: default `true`. Indexes whose column list contains a
    function call or other expression (`lower(email)`) are accepted, since the DSL cannot
    express them.
  - `ignore_files`: path suffixes or regexes of migrations to skip.

  In `execute(up, down)` the rollback is not judged when the `up` statement is an index
  statement accepted by the options above: the `DROP INDEX` of a `CONCURRENTLY` or
  expression index cannot be written with the DSL either. A plain create/drop pair is reported.

  SQL held in module attributes or variables is not inspected. Partial indexes can be
  written with the DSL (`where:`) and are reported.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [allow_concurrent: true, allow_expression_indexes: true, ignore_files: []],
    explanations: [
      check: """
      Prefer the migration DSL for indexes over raw SQL in `execute/1`.

      ## Bad

      ```elixir
      execute("CREATE UNIQUE INDEX users_email_index ON users (email)")
      ```

      ## Good

      ```elixir
      create unique_index(:users, [:email])
      ```

      `CREATE INDEX CONCURRENTLY` and expression indexes are accepted by default.
      """,
      params: [
        allow_concurrent: "Accept CREATE INDEX CONCURRENTLY.",
        allow_expression_indexes: "Accept indexes over expressions such as lower(email).",
        ignore_files: "Path suffixes or regexes for migrations to skip."
      ]
    ]

  alias OptimumCredo.OptimumDataSupport

  @index_statement ~r/\A\s*(?:create|drop|alter)\s+(?:unique\s+)?index\b/i
  @concurrently ~r/\bconcurrently\b/i
  @expression_column ~r/\bon\s+[\w."]+(?:\s+using\s+\w+)?\s*\([^)]*[\w"]\s*\(|\bon\s+[\w."]+(?:\s+using\s+\w+)?\s*\(\s*\(/i

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    ignore_files = Params.get(params, :ignore_files, __MODULE__)

    if OptimumDataSupport.migration?(source_file) and
         not OptimumDataSupport.ignored_file?(source_file, ignore_files) do
      issue_meta = IssueMeta.for(source_file, params)
      allow_concurrent = Params.get(params, :allow_concurrent, __MODULE__)
      allow_expression = Params.get(params, :allow_expression_indexes, __MODULE__)

      source_file
      |> Credo.SourceFile.ast()
      |> executes()
      |> Enum.flat_map(&judged(&1, allow_concurrent, allow_expression))
      |> Enum.uniq_by(fn meta -> {OptimumDataSupport.line(meta), meta[:column]} end)
      |> Enum.map(fn meta ->
        format_issue(issue_meta,
          message:
            "Use the migration index DSL (`create index/unique_index`) instead of raw SQL in `execute`.",
          trigger: "execute",
          line_no: OptimumDataSupport.line(meta)
        )
      end)
    else
      []
    end
  end

  defp executes(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {:execute, meta, args} = node, acc when is_list(args) ->
          {node, [{meta, Enum.map(args, &OptimumDataSupport.string_value/1)} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  # Returns the call's meta when one of its statements is flagged. For `execute(up, down)`
  # the rollback is skipped when `up` is an accepted (exempt) index statement.
  defp judged({meta, [up, down | _rest]}, allow_concurrent, allow_expression) do
    exempt_up? = up != nil and exempt?(up, allow_concurrent, allow_expression)
    sqls = if exempt_up?, do: [up], else: [up, down]

    flagged_any(sqls, meta, allow_concurrent, allow_expression)
  end

  defp judged({meta, sqls}, allow_concurrent, allow_expression),
    do: flagged_any(sqls, meta, allow_concurrent, allow_expression)

  defp flagged_any(sqls, meta, allow_concurrent, allow_expression) do
    if Enum.any?(sqls, &(&1 != nil and flagged?(&1, allow_concurrent, allow_expression))),
      do: [meta],
      else: []
  end

  # An index statement that is present, but accepted by the options.
  defp exempt?(sql, allow_concurrent, allow_expression) do
    statements =
      sql
      |> blank_sql_noise()
      |> String.split(";")

    Enum.any?(statements, &Regex.match?(@index_statement, &1)) and
      not flagged?(sql, allow_concurrent, allow_expression)
  end

  # Every `;`-separated statement is judged on its own, after SQL comments and quoted
  # strings are blanked, so `INSERT ... VALUES ('create index')` or a `-- create index`
  # comment is not an index statement.
  defp flagged?(sql, allow_concurrent, allow_expression) do
    sql
    |> blank_sql_noise()
    |> String.split(";")
    |> Enum.any?(fn statement ->
      Regex.match?(@index_statement, statement) and
        not (allow_concurrent and Regex.match?(@concurrently, statement)) and
        not (allow_expression and Regex.match?(@expression_column, statement))
    end)
  end

  defp blank_sql_noise(sql) do
    sql
    |> String.replace(~r{/\*.*?\*/}s, " ")
    |> String.replace(~r/--[^\n]*/, " ")
    |> String.replace(~r/'(?:[^']|'')*'/, "''")
  end
end
