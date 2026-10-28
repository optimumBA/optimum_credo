defmodule OptimumCredo.Check.Warning.SchemaModuleInMigration do
  @moduledoc """
  Finds references to application modules inside Ecto migrations.

  A migration runs long after the schema module it references may have changed or been
  deleted, so it should use raw table operations (`from(u in "users", ...)`,
  `execute/1`) instead.

  The check only reads files under `priv/<repo>/migrations/`. It reports an `alias`,
  `import`, `require`, `use`, remote call, struct literal or module reference whose
  first segments equal the app namespace, except `<Namespace>.Repo` (and the migration
  module itself, which lives under `<Namespace>.Repo.Migrations`).

  ## Parameters

  - `app_namespace`: string or atom such as `"MyApp"`. When omitted it is taken from the
    first segment of the migration's own `defmodule` (`MyApp.Repo.Migrations.AddUsers`).
  - `allowed_modules`: modules under the namespace that are acceptable, like
    `["MyApp.Vault"]`.
  - `ignore_files`: path suffixes or regexes of legacy migrations to skip.

  Aliases are followed lexically: after `alias MyApp.Accounts`, `Accounts.User` is reported
  as `MyApp.Accounts.User`. A bare name that an alias introduced (`User` after
  `alias MyApp.Accounts.User`) is reported once, at the `alias`. The check cannot tell which
  referenced modules are Ecto schemas.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [app_namespace: nil, allowed_modules: [], ignore_files: []],
    explanations: [
      check: """
      Migrations must not depend on application modules such as Ecto schemas. Those
      modules evolve (or disappear) after the migration is written, which breaks it
      when it runs against production data later.

      ## Bad

      ```elixir
      alias MyApp.Accounts.User

      def up, do: Repo.update_all(User, set: [active: true])
      ```

      ## Good

      ```elixir
      def up do
        repo().update_all(from(u in "users"), set: [active: true])
      end
      ```

      This lexical check reports references under the app namespace (except `Repo`) in
      files under `priv/*/migrations`. Aliases are resolved lexically.
      """,
      params: [
        app_namespace: "Application namespace; inferred from the migration module when nil.",
        allowed_modules: "Modules under the namespace that migrations may reference.",
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
      ast = Credo.SourceFile.ast(source_file)

      case namespace(ast, Params.get(params, :app_namespace, __MODULE__)) do
        [] -> []
        namespace -> report(source_file, params, ast, namespace)
      end
    else
      []
    end
  end

  defp report(source_file, params, ast, namespace) do
    issue_meta = IssueMeta.for(source_file, params)

    allowed =
      params
      |> Params.get(:allowed_modules, __MODULE__)
      |> Enum.map(&segments/1)

    ast
    |> strip_module_names()
    |> OptimumDataSupport.expand_aliases()
    |> references([])
    |> Enum.filter(&app_module?(&1, namespace, allowed))
    |> Enum.uniq_by(fn {segments, meta} -> {segments, OptimumDataSupport.line(meta)} end)
    |> Enum.sort_by(fn {_segments, meta} -> OptimumDataSupport.line(meta) end)
    |> Enum.map(&module_issue(&1, issue_meta))
  end

  defp module_issue({segments, meta}, issue_meta) do
    name = Enum.join(segments, ".")

    format_issue(issue_meta,
      message:
        "Migration references application module #{name}; " <>
          "use raw table operations instead of app modules.",
      trigger: name,
      line_no: OptimumDataSupport.line(meta)
    )
  end

  defp namespace(ast, nil) do
    ast
    |> OptimumDataSupport.modules()
    |> Enum.find_value([], fn
      {{:__aliases__, _meta, [root | _tail]}, _body} when is_atom(root) -> [root]
      _other -> nil
    end)
  end

  defp namespace(_ast, configured), do: segments(configured)

  defp segments(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> segments()
  end

  defp segments(value) when is_binary(value) do
    value
    |> String.replace_prefix("Elixir.", "")
    |> String.split(".")
    |> Enum.map(&String.to_atom/1)
  end

  # The module being defined is not a reference; keep its body.
  defp strip_module_names(ast) do
    Macro.prewalk(ast, fn
      {:defmodule, meta, [_name, body]} -> {:defmodule, meta, [nil, body]}
      node -> node
    end)
  end

  defp references(
         {:alias, _meta,
          [{{:., _dot_meta, [{:__aliases__, _alias_meta, base}, :{}]}, _tuple_meta, children}]} =
           node,
         acc
       )
       when is_list(children) do
    expanded =
      for {:__aliases__, meta, rest} <- children, do: {base ++ rest, meta}

    walk_children(node, expanded ++ acc)
  end

  # A bare `User` after `alias MyApp.Accounts.User` is reported once, at the alias itself.
  defp references({:__aliases__, meta, segments}, acc) when is_list(segments) do
    if Enum.all?(segments, &is_atom/1) and meta[:alias_written] != 1,
      do: [{segments, meta} | acc],
      else: acc
  end

  defp references({_form, _meta, args} = node, acc) when is_list(args),
    do: walk_children(node, acc)

  defp references({left, right}, acc), do: references(right, references(left, acc))
  defp references(list, acc) when is_list(list), do: Enum.reduce(list, acc, &references/2)
  defp references(_other, acc), do: acc

  defp walk_children({form, _meta, args}, acc) do
    acc = if is_tuple(form), do: references(form, acc), else: acc
    Enum.reduce(args, acc, &references/2)
  end

  defp app_module?({segments, _meta}, namespace, allowed) do
    List.starts_with?(segments, namespace) and length(segments) > length(namespace) and
      not repo_module?(segments, namespace) and
      not Enum.any?(allowed, &List.starts_with?(segments, &1))
  end

  defp repo_module?(segments, namespace),
    do: Enum.at(segments, length(namespace)) == :Repo
end
