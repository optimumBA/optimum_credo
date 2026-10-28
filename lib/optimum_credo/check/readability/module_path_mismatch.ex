defmodule OptimumCredo.Check.Readability.ModulePathMismatch do
  @moduledoc """
  Finds files under `lib/` whose module names do not mirror the file path.

  `lib/my_app/billing/invoice.ex` should define `MyApp.Billing.Invoice`. Modules with
  dynamic names, `lib/mix/tasks/**`, `.exs` files, and files matching `ignore_paths` are
  skipped. Modules defined inside another module are always accepted, since their full
  name is a child of the enclosing module.

  Phoenix generates web modules into layer directories that are not part of the
  module name (`lib/my_app_web/controllers/page_controller.ex` defines
  `MyAppWeb.PageController`). For a `*_web` directory (the first one below `lib/`, or the
  second one below a nested root namespace such as `lib/my_org/my_app_web/`), a leading
  layer directory from `web_layer_dirs` is therefore optional.

  Files that deliberately hold several top-level modules are handled by
  `additional_modules`:

  - `:nested` (default): the module that matches the path is the file's module and every
    other top-level module must live in its namespace (`MyApp.Invoice.Line` next to
    `MyApp.Invoice`). Unrelated top-level modules are reported at their own line. When no
    module matches the path, only the first module is reported.
  - `:report`: every top-level module must match the path exactly.
  - `:ignore`: only the first top-level module is compared.

  This is a static path heuristic. Umbrella projects work because the `lib` segment next to
  a `mix.exs` (or else the first one) is the root. Acronym segments follow
  `Macro.underscore/1`, so `MyApp.OAuth` expects `o_auth.ex`; use `ignore_paths` or
  `allowed_modules` for such files. Files whose path has no `lib` segment are ignored.

  ## Parameters

  - `ignore_paths`: path fragments (substring match on the normalized path) or regexes to skip.
  - `web_layer_dirs`: layer directories that may be omitted below a `*_web` root.
  - `additional_modules`: `:nested` (default), `:report`, or `:ignore`, see above.
  - `allowed_modules`: module names (and their children) that never need to match the path.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [
      ignore_paths: [],
      web_layer_dirs: ["controllers", "live", "components", "channels", "plugs"],
      additional_modules: :nested,
      allowed_modules: []
    ],
    explanations: [
      check: """
      The module namespace should mirror the directory and the file name should mirror
      the module, as `mix phx.gen.*` would generate it.

      ## Bad

      ```elixir
      # lib/my_app_web/controllers/helper.ex
      defmodule MyApp.ScreenshotHelper do
      end
      ```

      ## Good

      ```elixir
      # lib/my_app/screenshot_helper.ex
      defmodule MyApp.ScreenshotHelper do
      end
      ```

      Top-level modules in the same file must live in the namespace of the module that
      matches the path (`additional_modules: :nested`). Use `ignore_paths` or
      `allowed_modules` for intentional exceptions.
      """,
      params: [
        ignore_paths: "Path fragments or regexes to skip.",
        web_layer_dirs: "Layer directories that may be omitted below a `*_web` root.",
        additional_modules: "`:nested` (default), `:report`, or `:ignore` for extra modules.",
        allowed_modules: "Module names (and children) exempt from the path rule."
      ]
    ]

  alias OptimumCredo.OptimumStructureSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{filename: filename} = source_file, params) do
    ignore_paths = Params.get(params, :ignore_paths, __MODULE__)

    mode =
      params
      |> Params.get(:additional_modules, __MODULE__)
      |> mode!()

    with {_root, [_head | _tail] = rest} <- OptimumStructureSupport.split_at_dir(filename, "lib"),
         true <- String.ends_with?(filename, ".ex"),
         false <- mix_task?(rest) or OptimumStructureSupport.path_matches?(filename, ignore_paths),
         ast = Credo.SourceFile.ast(source_file),
         {_segments, _line} <- OptimumStructureSupport.primary_module(ast) do
      path_issues(source_file, ast, rest, mode, params)
    else
      _other -> []
    end
  end

  defp path_issues(source_file, ast, rest, mode, params) do
    accepted = accepted_paths(rest, params)

    allowed =
      params
      |> Params.get(:allowed_modules, __MODULE__)
      |> allowed_names()

    top_level =
      ast
      |> OptimumStructureSupport.modules()
      |> Enum.reject(& &1.nested?)

    issue_meta = IssueMeta.for(source_file, params)

    top_level
    |> mismatches(accepted, allowed, mode)
    |> Enum.map(fn {kind, module} -> issue(issue_meta, kind, module) end)
  end

  defp accepted_paths(rest, params) do
    layer_dirs =
      params
      |> Params.get(:web_layer_dirs, __MODULE__)
      |> OptimumStructureSupport.to_strings()

    rest
    |> Enum.join("/")
    |> Path.rootname(".ex")
    |> String.split("/")
    |> OptimumStructureSupport.module_paths(layer_dirs)
  end

  defp mode!(mode) when mode in [:nested, :report, :ignore], do: mode
  defp mode!("nested"), do: :nested
  defp mode!("report"), do: :report
  defp mode!("ignore"), do: :ignore

  defp mode!(mode) do
    raise ArgumentError,
          "invalid additional_modules #{inspect(mode)} for #{inspect(__MODULE__)}; " <>
            "use :nested, :report or :ignore"
  end

  defp allowed_names(names) do
    names
    |> OptimumStructureSupport.to_strings()
    |> Enum.map(&String.replace_prefix(&1, "Elixir.", ""))
  end

  defp mismatches(top_level, accepted, allowed, :ignore) do
    case top_level do
      [first | _tail] ->
        if allowed?(first, allowed) or matches?(first, accepted),
          do: [],
          else: [{:primary, first}]

      [] ->
        []
    end
  end

  defp mismatches(top_level, accepted, allowed, mode) do
    checked = Enum.reject(top_level, &allowed?(&1, allowed))
    anchor = Enum.find(checked, &matches?(&1, accepted)) || List.first(checked)

    Enum.flat_map(checked, fn module ->
      cond do
        matches?(module, accepted) -> []
        module == anchor -> [{:primary, module}]
        mode == :nested and descendant?(module.segments, anchor.segments) -> []
        true -> [{:additional, module}]
      end
    end)
  end

  defp allowed?(%{segments: segments}, allowed), do: allowed?(segments, allowed)

  defp allowed?(segments, allowed) when is_list(segments) do
    name = Enum.map_join(segments, ".", &Atom.to_string/1)
    Enum.any?(allowed, &(name == &1 or String.starts_with?(name, &1 <> ".")))
  end

  defp matches?(%{segments: segments}, accepted), do: module_path(segments) in accepted

  defp module_path(segments) do
    segments
    |> Enum.map_join(".", &Atom.to_string/1)
    |> Macro.underscore()
  end

  defp descendant?(segments, anchor),
    do: length(segments) > length(anchor) and List.starts_with?(segments, anchor)

  defp issue(issue_meta, :primary, module) do
    format_issue(issue_meta,
      message:
        "Module #{name(module)} does not match its path; " <>
          "expected lib/#{module_path(module.segments)}.ex.",
      line_no: module.line
    )
  end

  defp issue(issue_meta, :additional, module) do
    format_issue(issue_meta,
      message:
        "Module #{name(module)} is neither named for this file nor nested under its module; " <>
          "move it to lib/#{module_path(module.segments)}.ex, nest it, or list it in allowed_modules.",
      line_no: module.line
    )
  end

  defp name(%{segments: segments}), do: Enum.map_join(segments, ".", &Atom.to_string/1)

  defp mix_task?(["mix", "tasks" | _rest]), do: true
  defp mix_task?(_rest), do: false
end
