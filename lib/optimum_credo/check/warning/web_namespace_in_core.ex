defmodule OptimumCredo.Check.Warning.WebNamespaceInCore do
  @moduledoc """
  Finds core modules that reference the web namespace (`MyAppWeb`).

  Web modules may depend on core modules, but core modules under `lib/<app>/` must
  not alias, import, or call into `lib/<app>_web/`. The dependency direction can
  break `mix release` and couples business logic to the delivery layer.

  This is a static heuristic over the file path and literal aliases. It does not read
  `mix.exs`: without `web_namespace` the namespace is inferred from the path
  (`lib/my_app/x.ex` means `MyAppWeb`). A nested root namespace is inferred
  from the file's own module name: `lib/my_app/x.ex` defining `MyOrg.MyApp.X` means
  `MyOrg.MyAppWeb`, and `lib/my_org/my_app/x.ex` defining `MyOrg.MyApp.X` means
  `MyOrg.MyAppWeb` as well. Set `web_namespace` when the layout is less regular.

  References are literal module names. `alias A.B.{C, D}` is expanded, and names reached
  through the file's `alias` statements are resolved (`alias MyOrg, as: Org` makes
  `Org.MyAppWeb.Endpoint` a web reference). Aliases are resolved file-wide, not by lexical
  scope. A reference that is already reported at its `alias` line is not reported again
  at each use. Dynamic modules and `quote` bodies, which expand in the caller's module,
  are not followed.

  Files outside `lib/`, files in the web directory itself, `lib/mix/tasks`, and the OTP
  application module `lib/<app>/application.ex` (a Phoenix supervisor has to start the
  endpoint; turn off `allow_application` to inspect it) are never inspected.

  ## Parameters

  - `web_namespace`: explicit web namespace string such as `"MyAppWeb"` (or a list of
    them). Files under the matching directory (`lib/my_app_web/`) are treated as web
    files and every other `lib/` file as core.
  - `allowed_modules`: modules (and their children) that core may reference, for
    example `["MyAppWeb.Endpoint"]` for PubSub broadcasts.
  - `allow_application`: skip the OTP application module (default `true`).
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [web_namespace: nil, allowed_modules: [], allow_application: true],
    explanations: [
      check: """
      Core modules should not depend on the web namespace. Web code may use core
      modules, never the other way around.

      ## Bad

      ```elixir
      # lib/my_app/drops.ex
      MyAppWeb.Endpoint.broadcast("drops", "created", payload)
      ```

      ## Good

      ```elixir
      # lib/my_app/drops.ex
      Phoenix.PubSub.broadcast(MyApp.PubSub, "drops", {:created, payload})
      ```

      The namespace is inferred from the path when `web_namespace` is not set. Use
      `allowed_modules` for deliberate exceptions. Dynamic modules and `quote` bodies
      are not inspected; `lib/<app>/application.ex` is skipped by default.
      """,
      params: [
        web_namespace:
          "Web namespace such as \"MyAppWeb\" (or a list). Inferred from the path and module name when unset.",
        allowed_modules: "Web modules (and their children) that core code may reference.",
        allow_application: "Skip `lib/<app>/application.ex`, which starts the endpoint."
      ]
    ]

  alias OptimumCredo.OptimumStructureSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    configured = Params.get(params, :web_namespace, __MODULE__)

    allowed_modules =
      params
      |> Params.get(:allowed_modules, __MODULE__)
      |> OptimumStructureSupport.to_strings()

    allowed = Enum.map(allowed_modules, &module_names/1)
    allow_application? = Params.get(params, :allow_application, __MODULE__)
    ast = Credo.SourceFile.ast(source_file)

    case web_prefixes(source_file.filename, ast, configured, allow_application?) do
      [] -> []
      prefixes -> web_references(ast, prefixes, allowed, issue_meta)
    end
  end

  defp web_references(ast, prefixes, allowed, issue_meta) do
    aliases =
      ast
      |> collect_aliases(%{})
      |> reportable_aliases(prefixes, allowed)

    ast
    |> references(aliases, [])
    |> Enum.filter(fn {names, _line} -> web?(names, prefixes, allowed) end)
    |> Enum.map(fn {names, line} -> {Enum.join(names, "."), line} end)
    |> Enum.uniq()
    |> Enum.sort_by(&elem(&1, 1))
    |> Enum.map(fn {module, line} ->
      format_issue(issue_meta,
        message: "Core module references web module #{module}; depend on core or PubSub instead.",
        line_no: line
      )
    end)
  end

  defp module_names(name) do
    name
    |> String.replace(~r/^Elixir\./, "")
    |> String.split(".")
  end

  defp web?(names, prefixes, allowed) do
    Enum.any?(prefixes, &List.starts_with?(names, &1)) and
      not Enum.any?(allowed, &List.starts_with?(names, &1))
  end

  # Web namespaces (as segment lists) to look for, or [] when the file is not a core file.
  defp web_prefixes(filename, ast, configured, allow_application?) do
    case OptimumStructureSupport.split_at_dir(filename, "lib") do
      {_root, [_head | _tail] = rest} ->
        if skipped?(rest, allow_application?),
          do: [],
          else: namespaces(rest, ast, configured)

      _other ->
        []
    end
  end

  defp skipped?(["mix", "tasks" | _rest], _allow_application?), do: true
  defp skipped?([_app, "application.ex"], true), do: true
  defp skipped?(_rest, _allow_application?), do: false

  defp namespaces(rest, ast, configured) when is_binary(configured) or is_list(configured) do
    prefixes =
      configured
      |> List.wrap()
      |> OptimumStructureSupport.to_strings()
      |> Enum.map(&module_names/1)

    relative = Enum.join(rest, "/")

    web_file? =
      Enum.any?(prefixes, fn prefix ->
        web_path =
          prefix
          |> Enum.join(".")
          |> Macro.underscore()

        relative == web_path <> ".ex" or String.starts_with?(relative, web_path <> "/")
      end)

    if web_file? or own_module_web?(ast, prefixes), do: [], else: prefixes
  end

  defp namespaces([first | _tail] = rest, ast, nil) do
    dirs = Enum.drop(rest, -1)
    app = Path.rootname(first, ".ex")

    if app in ["", "mix"] or
         rest
         |> Enum.take(2)
         |> Enum.any?(&web_dir?/1) do
      []
    else
      prefixes = inferred_prefixes(app, dirs, ast)
      if own_module_web?(ast, prefixes), do: [], else: prefixes
    end
  end

  defp web_dir?(segment) do
    segment
    |> Path.rootname(".ex")
    |> String.ends_with?("_web")
  end

  defp inferred_prefixes(app, dirs, ast) do
    module = module_segments(ast)
    from_path = [[Macro.camelize(app) <> "Web"]]

    Enum.uniq(from_path ++ nested_prefixes(module, dirs) ++ from_module(module, app))
  end

  defp module_segments(ast) do
    case OptimumStructureSupport.primary_module(ast) do
      {segments, _line} -> Enum.map(segments, &Atom.to_string/1)
      nil -> []
    end
  end

  defp nested_prefixes(module, [first, second | _tail]) do
    root = [Macro.camelize(first), Macro.camelize(second)]

    if List.starts_with?(module, root),
      do: [List.update_at(root, 1, &(&1 <> "Web"))],
      else: []
  end

  defp nested_prefixes(_module, _dirs), do: []

  defp from_module(module, app) do
    module
    |> Enum.with_index()
    |> Enum.filter(fn {segment, index} -> index > 0 and Macro.underscore(segment) == app end)
    |> Enum.map(fn {segment, index} ->
      module
      |> Enum.take(index)
      |> Enum.concat([segment <> "Web"])
    end)
  end

  # A file whose own module is in the web namespace is a web file in the wrong place.
  defp own_module_web?(ast, prefixes) do
    case OptimumStructureSupport.primary_module(ast) do
      {segments, _line} ->
        names = Enum.map(segments, &Atom.to_string/1)
        Enum.any?(prefixes, &List.starts_with?(names, &1))

      nil ->
        false
    end
  end

  # Collects `alias` statements as %{alias_name => target segments}.
  defp collect_aliases({:quote, _meta, _args}, aliases), do: aliases

  defp collect_aliases({:alias, _meta, [target | options]}, aliases) do
    as =
      options
      |> List.first()
      |> as_name()

    target
    |> alias_targets()
    |> Enum.reduce(aliases, fn {names, _line}, acc ->
      Map.put(acc, as || List.last(names), names)
    end)
  end

  defp collect_aliases(term, aliases) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> Enum.reduce(aliases, &collect_aliases/2)
  end

  defp collect_aliases(list, aliases) when is_list(list),
    do: Enum.reduce(list, aliases, &collect_aliases/2)

  defp collect_aliases(_term, aliases), do: aliases

  defp as_name([{:as, {:__aliases__, _meta, [name]}}]) when is_atom(name),
    do: Atom.to_string(name)

  defp as_name(_options), do: nil

  # Full targets of an alias/import/require argument: `A.B`, `A.B.{C, D}` or `__MODULE__`-based.
  defp alias_targets({{:., _dot, [base, :{}]}, _meta, children}) do
    case literal_names(base) do
      nil ->
        []

      base_names ->
        Enum.flat_map(children, &child_targets(&1, base_names))
    end
  end

  defp alias_targets({:__aliases__, meta, _segments} = node) do
    case literal_names(node) do
      nil -> []
      names -> [{names, meta[:line] || 1}]
    end
  end

  defp alias_targets(_other), do: []

  defp child_targets(child, base_names) do
    for {names, line} <- alias_targets(child), do: {base_names ++ names, line}
  end

  # Aliases whose own target is reported at the alias line need no second report per use.
  defp reportable_aliases(aliases, prefixes, allowed) do
    aliases
    |> Enum.reject(fn {_name, names} -> web?(names, prefixes, allowed) end)
    |> Map.new()
  end

  defp literal_names(node) do
    case OptimumStructureSupport.alias_segments(node) do
      nil ->
        nil

      segments ->
        segments
        |> Enum.map(&Atom.to_string/1)
        |> drop_elixir()
    end
  end

  defp drop_elixir(["Elixir" | names]), do: names
  defp drop_elixir(names), do: names

  # Module references as {names, line}. The header of `defmodule` and `quote` bodies are skipped.
  defp references({:defmodule, _meta, [_name, body]}, aliases, acc),
    do: references(body, aliases, acc)

  defp references({:quote, _meta, _args}, _aliases, acc), do: acc

  defp references({{:., _dot, [_base, :{}]}, _meta, _children} = node, aliases, acc) do
    node
    |> alias_targets()
    |> Enum.reduce(acc, fn {names, line}, found -> [{resolve(names, aliases), line} | found] end)
  end

  defp references({:__aliases__, meta, _segments} = node, aliases, acc) do
    case literal_names(node) do
      nil -> acc
      names -> [{resolve(names, aliases), meta[:line] || 1} | acc]
    end
  end

  defp references(term, aliases, acc) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> Enum.reduce(acc, &references(&1, aliases, &2))
  end

  defp references(list, aliases, acc) when is_list(list),
    do: Enum.reduce(list, acc, &references(&1, aliases, &2))

  defp references(_term, _aliases, acc), do: acc

  defp resolve([first | rest] = names, aliases) do
    case Map.fetch(aliases, first) do
      {:ok, target} -> target ++ rest
      :error -> names
    end
  end
end
