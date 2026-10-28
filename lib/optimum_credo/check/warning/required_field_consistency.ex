defmodule OptimumCredo.Check.Warning.RequiredFieldConsistency do
  @moduledoc """
  Finds schema fields that are `null: false` in migrations but are not required by the
  schema's changesets.

  A NOT NULL column that `validate_required/2` never mentions turns a missing value into a
  database exception instead of a changeset error. The check reads the schema file, then
  replays the migrations on disk for the schema's table.

  How it works:

  1. For every module with `schema "table"`, it finds the table's migrations by walking up
     from the file path to the nearest directory that contains `migrations_path`.
  2. It replays `create table`, `alter table` (`add`, `modify`, `remove`), `drop table` and
     `rename` in file-name order and keeps columns that end up `null: false` with no default.
     Only `up` (or `change`) is replayed; a `def down` is skipped.
  3. It reports declared `field`/`belongs_to` columns that appear in no `validate_required`
     call. A `field ..., source: :name` is matched through its `source` column, and a
     `virtual: true` field or `belongs_to ..., define_field: false` has no column.

  Conservative by design: nothing is reported when the module has no `validate_required`
  at all (changesets may live elsewhere), when any `validate_required` argument cannot
  be resolved statically (only atom lists, atoms, `@attribute` lists and `++` of those are
  understood), when the migrations directory or table is missing, or for fields that have a
  schema `default:`, a database default, or are set with `put_change`/`put_assoc`/`change`/
  `force_change` in the same file. It also reads the project's `lib/**/*.ex` files for
  literal `Schema.changeset(...) |> Ecto.Changeset.put_assoc(:association, value)`
  chains, including resolved aliases and imports. Such associations are set by the
  context after the schema changeset runs, so requiring them earlier would reject valid
  inserts. Dynamic dispatch, variable-separated chains and helper wrappers remain invisible.
  No project code is evaluated. Migrations built from helper modules are invisible, and
  `execute` SQL is read only for literal `ALTER TABLE t ALTER COLUMN c DROP | SET NOT NULL`. A `belongs_to :user` is satisfied by `:user` or `:user_id`.

  This only checks one direction (NOT NULL without validation); it does not warn when a
  nullable column is validated.

  ## Parameters

  - `migrations_path`: relative to the project root, default `"priv/repo/migrations"`.
  - `ignore_fields`: columns never reported, default `[:id, :inserted_at, :updated_at]`.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [
      migrations_path: "priv/repo/migrations",
      ignore_fields: [:id, :inserted_at, :updated_at]
    ],
    explanations: [
      check: """
      A column that is `null: false` in the migration should be required by the changeset.

      ## Bad

      ```elixir
      # migration: add :title, :string, null: false
      schema "posts" do
        field :title, :string
      end

      def changeset(post, attrs), do: cast(post, attrs, [:title])
      ```

      ## Good

      ```elixir
      def changeset(post, attrs) do
        post |> cast(attrs, [:title]) |> validate_required([:title])
      end
      ```

      The check replays migrations from disk; see the module docs for its limits.
      """,
      params: [
        migrations_path: "Migrations directory relative to the project root.",
        ignore_fields: "Columns that are set by the system and never reported."
      ]
    ]

  alias OptimumCredo.OptimumDataSupport
  alias OptimumCredo.RequiredAssociations
  alias OptimumCredo.TestsSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    ast = Credo.SourceFile.ast(source_file)

    schemas =
      for {name, body} <- OptimumDataSupport.modules(ast),
          schema = schema(body),
          do: {name, schema}

    if schemas == [] do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      migrations = migrations(source_file, Params.get(params, :migrations_path, __MODULE__))

      ignored =
        params
        |> Params.get(:ignore_fields, __MODULE__)
        |> Enum.map(&to_string/1)

      external =
        RequiredAssociations.externally_set(
          source_file.filename,
          Params.get(params, :migrations_path, __MODULE__)
        )

      report_schemas(schemas, external, migrations, ignored, issue_meta)
    end
  end

  defp report_schemas(schemas, external, migrations, ignored, issue_meta) do
    Enum.flat_map(schemas, fn {name, schema} ->
      module = TestsSupport.resolve_module(name, TestsSupport.new_env())
      fields = Map.get(external, module, MapSet.new())
      system_set = Enum.flat_map(fields, &[&1, &1 <> "_id"])

      report(
        %{schema | system_set: schema.system_set ++ system_set},
        migrations,
        ignored,
        issue_meta
      )
    end)
  end

  defp report(schema, migrations, ignored, issue_meta) do
    required = Map.get(migrations, schema.table, MapSet.new())

    case validated(schema) do
      {:ok, validated} ->
        schema.fields
        |> Enum.filter(&unvalidated?(&1, schema, required, ignored, validated))
        |> Enum.map(fn field ->
          format_issue(issue_meta,
            message:
              "Column #{atom_label(field.column)} is `null: false` in the migrations for " <>
                "#{inspect(schema.table)} but is not in any validate_required/2 list.",
            trigger: field.column,
            line_no: OptimumDataSupport.line(field.meta)
          )
        end)

      _unknown_or_none ->
        []
    end
  end

  # Column names stay strings (they come from source and SQL text); this prints them the way
  # `inspect/1` prints the matching atom.
  defp atom_label(name) when name in ["nil", "true", "false"], do: name

  defp atom_label(name) do
    if Regex.match?(~r/\A[\p{L}_][\p{L}\p{N}_@]*[?!]?\z/u, name),
      do: ":" <> name,
      else: ":" <> inspect(name)
  end

  defp unvalidated?(field, schema, required, ignored, validated) do
    field.column in required and not field.default? and
      not Enum.any?([field.column | field.names], &(&1 in ignored or &1 in schema.system_set)) and
      not Enum.any?(field.names, &(&1 in validated))
  end

  # -- schema side ---------------------------------------------------------------------

  defp schema(body) do
    statements = OptimumDataSupport.statements(body)

    case Enum.find(statements, &match?({:schema, _, [table | _]} when is_binary(table), &1)) do
      {:schema, _meta, [table | rest]} -> schema_info(table, rest, statements, body)
      nil -> nil
    end
  end

  defp schema_info(table, rest, statements, body) do
    block =
      Enum.find_value(rest, [], fn options ->
        is_list(options) && Keyword.get(options, :do)
      end)

    lexical = OptimumDataSupport.lexical_body(body)

    %{
      table:
        table
        |> String.split(".")
        |> List.last(),
      fields:
        block
        |> OptimumDataSupport.statements()
        |> fields(),
      attributes: attributes(statements),
      body: lexical,
      system_set: system_set(lexical)
    }
  end

  # One entry per database column: the schema names that satisfy it (`belongs_to :user` is
  # satisfied by `:user` or `:user_id`) and whether the schema itself supplies a default.
  defp fields(declarations) do
    Enum.flat_map(declarations, &declared_column/1)
  end

  defp declared_column({:field, meta, [name | _tail] = args}) when is_atom(name) do
    with false <- virtual?(args),
         column when column != nil <- source(name, args) do
      [%{column: column, names: [Atom.to_string(name)], default?: default?(args), meta: meta}]
    else
      _skip -> []
    end
  end

  defp declared_column({:belongs_to, meta, [name | _tail] = args}) when is_atom(name) do
    with true <- OptimumDataSupport.fetch_option(args, :define_field) != {:ok, false},
         key when key != nil <- foreign_key(name, args) do
      [
        %{
          column: key,
          names: [Atom.to_string(name), key],
          default?: default?(args),
          meta: meta
        }
      ]
    else
      _skip -> []
    end
  end

  defp declared_column(_other), do: []

  defp virtual?(args), do: OptimumDataSupport.fetch_option(args, :virtual) == {:ok, true}

  defp default?(args), do: OptimumDataSupport.fetch_option(args, :default) != :error

  # `field :title, :string, source: :name` lives in the `name` column.
  defp source(name, args) do
    case OptimumDataSupport.fetch_option(args, :source) do
      {:ok, nil} -> nil
      {:ok, source} when is_atom(source) -> Atom.to_string(source)
      {:ok, source} when is_binary(source) -> source
      {:ok, _dynamic} -> nil
      :error -> Atom.to_string(name)
    end
  end

  # A foreign key that is not a literal atom cannot be mapped to a column.
  defp foreign_key(name, args) do
    case OptimumDataSupport.fetch_option(args, :foreign_key) do
      {:ok, nil} -> nil
      {:ok, key} when is_atom(key) -> Atom.to_string(key)
      {:ok, _dynamic} -> nil
      :error -> "#{name}_id"
    end
  end

  defp attributes(statements) do
    for {:@, _meta, [{name, _tuple_meta, [value]}]} <- statements, into: %{}, do: {name, value}
  end

  defp system_set(body) do
    {_ast, fields} =
      Macro.prewalk(body, [], fn
        {function, _meta, args} = node, acc
        when function in [:put_change, :put_assoc, :force_change, :change] and is_list(args) ->
          {node, Enum.filter(args, &is_atom/1) ++ acc}

        node, acc ->
          {node, acc}
      end)

    fields
    |> Enum.reject(&(is_nil(&1) or is_boolean(&1)))
    |> Enum.flat_map(&[Atom.to_string(&1), "#{&1}_id"])
  end

  defp validated(schema) do
    {_ast, lists} =
      Macro.prewalk(schema.body, [], fn
        {:validate_required, _meta, args} = node, acc when is_list(args) ->
          {node, [required_argument(args) | acc]}

        node, acc ->
          {node, acc}
      end)

    resolved = Enum.map(lists, &fields_in(&1, schema.attributes))

    cond do
      resolved == [] ->
        :none

      :unknown in resolved ->
        :unknown

      true ->
        {:ok,
         resolved
         |> List.flatten()
         |> MapSet.new()}
    end
  end

  defp required_argument(args) do
    args
    |> Enum.reject(&OptimumDataSupport.keyword_literal?/1)
    |> List.last()
  end

  defp fields_in(fields, _attributes) when is_list(fields),
    do: if(Enum.all?(fields, &is_atom/1), do: Enum.map(fields, &Atom.to_string/1), else: :unknown)

  defp fields_in(field, _attributes) when is_atom(field) and not is_nil(field),
    do: [Atom.to_string(field)]

  defp fields_in({:@, _meta, [{name, _tuple_meta, nil}]}, attributes) do
    case Map.fetch(attributes, name) do
      {:ok, value} -> fields_in(value, attributes)
      :error -> :unknown
    end
  end

  defp fields_in({:++, _meta, [left, right]}, attributes) do
    with [_head | _tail] = a <- fields_in(left, attributes),
         [_head | _tail] = b <- fields_in(right, attributes) do
      a ++ b
    else
      _other -> :unknown
    end
  end

  defp fields_in(_other, _attributes), do: :unknown

  # -- migration side ------------------------------------------------------------------

  defp migrations(source_file, migrations_path) do
    case migrations_dir(source_file.filename || "", migrations_path) do
      nil ->
        %{}

      dir ->
        dir
        |> Path.join("**/*.exs")
        |> Path.wildcard()
        |> Enum.sort()
        |> Enum.reduce(%{}, &replay/2)
    end
  end

  # The nearest ancestor of the schema file that holds the migrations directory, which also
  # finds the right app of an umbrella.
  defp migrations_dir(filename, migrations_path) do
    root =
      filename
      |> Path.dirname()
      |> ancestors()
      |> Enum.find(fn dir ->
        dir
        |> Path.join(migrations_path)
        |> File.dir?()
      end)

    if root, do: Path.join(root, migrations_path)
  end

  defp ancestors(dir) do
    parent = Path.dirname(dir)
    if parent == dir, do: [dir], else: [dir | ancestors(parent)]
  end

  defp replay(file, state) do
    with {:ok, source} <- File.read(file),
         {:ok, ast} <- Code.string_to_quoted(source, emit_warnings: false) do
      ast
      |> operations()
      |> Enum.reduce(state, &apply_operation/2)
    else
      _error -> state
    end
  end

  # Schema changes in source order. `down` is not replayed: it would undo the `up` just
  # applied. Operations on tables whose name is not a literal are invisible.
  defp operations(ast) do
    {_ast, operations} = Macro.prewalk(ast, [], &collect_operation/2)

    Enum.reverse(operations)
  end

  defp collect_operation({:def, _meta, [{:down, _down_meta, _args} | _tail]}, acc),
    do: {nil, acc}

  defp collect_operation(
         {operation, _meta, [{:table, _table_meta, [table | _tail]}, [do: body]]} = node,
         acc
       )
       when operation in [:create, :create_if_not_exists, :alter] and
              (is_atom(table) or is_binary(table)) do
    {node, [{:statements, to_string(table), OptimumDataSupport.statements(body)} | acc]}
  end

  defp collect_operation(
         {drop, _meta, [{:table, _table_meta, [table | _tail]} | _tail2]} = node,
         acc
       )
       when drop in [:drop, :drop_if_exists] and (is_atom(table) or is_binary(table)) do
    {node, [{:drop, to_string(table)} | acc]}
  end

  defp collect_operation(
         {:rename, _meta,
          [{:table, _table_meta, [from | _tail]}, [to: {:table, _ignored, [to | _tail2]}]]} = node,
         acc
       )
       when (is_atom(from) or is_binary(from)) and (is_atom(to) or is_binary(to)) do
    {node, [{:rename_table, to_string(from), to_string(to)} | acc]}
  end

  defp collect_operation(
         {:rename, _meta, [{:table, _table_meta, [table | _tail]}, old, [to: new]]} = node,
         acc
       )
       when (is_atom(table) or is_binary(table)) and is_atom(old) and is_atom(new) do
    {node, [{:rename_column, to_string(table), Atom.to_string(old), Atom.to_string(new)} | acc]}
  end

  defp collect_operation({:execute, _meta, [sql | _tail]} = node, acc) do
    {node,
     sql
     |> sql_operations()
     |> Enum.reverse(acc)}
  end

  defp collect_operation(node, acc), do: {node, acc}

  @not_null_sql ~r/ALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:ONLY\s+)?(?:"?\w+"?\.)?"?(\w+)"?\s+ALTER\s+(?:COLUMN\s+)?"?(\w+)"?\s+(DROP|SET)\s+NOT\s+NULL/i

  # `execute "ALTER TABLE t ALTER COLUMN c DROP NOT NULL"`: the first argument is the `up`
  # statement. Only static strings are read; any other SQL stays invisible.
  defp sql_operations(sql) do
    case OptimumDataSupport.string_value(sql) do
      nil ->
        []

      sql ->
        for [_match, table, column, action] <- Regex.scan(@not_null_sql, sql) do
          {:sql_not_null, table, column, String.downcase(action)}
        end
    end
  end

  defp apply_operation({:statements, table, statements}, state) do
    columns =
      Enum.reduce(statements, Map.get(state, table, MapSet.new()), fn statement, columns ->
        apply_statement(statement, columns)
      end)

    Map.put(state, table, columns)
  end

  defp apply_operation({:sql_not_null, table, column, "set"}, state),
    do: Map.update(state, table, MapSet.new([column]), &MapSet.put(&1, column))

  defp apply_operation({:sql_not_null, table, column, "drop"}, state) do
    case state do
      %{^table => columns} -> Map.put(state, table, MapSet.delete(columns, column))
      _state -> state
    end
  end

  defp apply_operation({:drop, table}, state), do: Map.delete(state, table)

  defp apply_operation({:rename_table, from, to}, state) do
    case Map.pop(state, from) do
      {nil, state} -> state
      {columns, state} -> Map.put(state, to, columns)
    end
  end

  defp apply_operation({:rename_column, table, old, new}, state) do
    case state do
      %{^table => columns} ->
        if old in columns,
          do: Map.put(state, table, rename_in(columns, old, new)),
          else: state

      _state ->
        state
    end
  end

  defp rename_in(columns, old, new) do
    columns
    |> MapSet.delete(old)
    |> MapSet.put(new)
  end

  defp apply_statement({function, _meta, [column, _type | _tail] = args}, columns)
       when function in [:add, :add_if_not_exists, :modify] and is_atom(column) do
    column = Atom.to_string(column)
    null = OptimumDataSupport.fetch_option(args, :null)

    default? =
      match?({:ok, value} when value != nil, OptimumDataSupport.fetch_option(args, :default))

    primary_key? = OptimumDataSupport.fetch_option(args, :primary_key) == {:ok, true}

    cond do
      primary_key? or default? -> MapSet.delete(columns, column)
      null == {:ok, false} -> MapSet.put(columns, column)
      function == :modify and null == :error -> columns
      true -> MapSet.delete(columns, column)
    end
  end

  defp apply_statement({:remove, _meta, [column | _tail]}, columns) when is_atom(column),
    do: MapSet.delete(columns, Atom.to_string(column))

  defp apply_statement(_statement, columns), do: columns
end
