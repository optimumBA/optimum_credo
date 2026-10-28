defmodule OptimumCredo.Check.Readability.TestPathMismatch do
  @moduledoc """
  Finds `*_test.exs` files whose path or module name does not mirror the code they test.

  `test/my_app/billing/invoice_test.exs` should define
  `MyApp.Billing.InvoiceTest` and, when `require_test_counterpart` is on, test an
  existing `lib/my_app/billing/invoice.ex` (or a `lib/my_app/billing/invoice/` directory,
  as Phoenix LiveView tests cover several modules). The first top-level module is compared;
  the same Phoenix layer-directory allowance as `ModulePathMismatch` applies below
  `test/*_web/`.

  Skipped: `test/support/**`, `test/**/features/**`, `test/**/integration/**`,
  `test/mix/tasks/**`, and files matching `ignore_paths`. Only files ending in
  `_test.exs` below a `test` directory are inspected.

  A test whose module name differs from its path is still accepted when the `lib/` file at
  the exact mirrored path defines the tested module (a project keeping `helpers/` or
  `services/` directories that are not part of the module name); the lib file is then the
  one `ModulePathMismatch` reports.

  This is a static heuristic. The counterpart lookup uses the filesystem relative to
  the checked file's project root (the part of the path before `test/`), so it
  reflects the working tree, not compiled modules. Tests of macros-generated or
  differently named code can be silenced with `ignore_paths` or by turning the
  counterpart requirement off.

  ## Parameters

  - `ignore_paths`: path fragments (substring match) to skip.
  - `require_test_counterpart`: when true (default) the mirrored `lib/` file must exist.
  - `web_layer_dirs`: layer directories that may be omitted below a `*_web` root.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [
      ignore_paths: [],
      require_test_counterpart: true,
      web_layer_dirs: ["controllers", "live", "components", "channels", "plugs"]
    ],
    explanations: [
      check: """
      A test file mirrors its subject: `lib/my_app/x.ex` is tested by
      `test/my_app/x_test.exs`, and the test module is named `<Module>Test`.

      ## Bad

      ```elixir
      # test/my_app/invoice_test.exs
      defmodule MyApp.BillingTest do
      end
      ```

      ## Good

      ```elixir
      # test/my_app/invoice_test.exs
      defmodule MyApp.InvoiceTest do
      end
      ```

      Feature, integration, and support tests are exempt by directory. The counterpart
      lookup reads the working tree.
      """,
      params: [
        ignore_paths: "Path fragments to skip.",
        require_test_counterpart: "Require an existing lib/ file at the mirrored path.",
        web_layer_dirs: "Layer directories that may be omitted below a `*_web` root."
      ]
    ]

  alias OptimumCredo.OptimumStructureSupport

  @exempt_dirs ["support", "features", "integration"]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{filename: filename} = source_file, params) do
    ignore_paths = Params.get(params, :ignore_paths, __MODULE__)

    with true <- is_binary(filename) and String.ends_with?(filename, "_test.exs"),
         {root, [_head | _tail] = rest} <- OptimumStructureSupport.split_at_dir(filename, "test"),
         false <- exempt?(rest) or OptimumStructureSupport.path_matches?(filename, ignore_paths) do
      issue_meta = IssueMeta.for(source_file, params)
      ast = Credo.SourceFile.ast(source_file)

      module_issues(ast, root, rest, params, issue_meta) ++
        counterpart_issues(ast, root, rest, params, issue_meta)
    else
      _other -> []
    end
  end

  defp exempt?(["mix", "tasks" | _rest]), do: true
  defp exempt?(rest), do: Enum.any?(rest, &(&1 in @exempt_dirs))

  defp module_issues(ast, root, rest, params, issue_meta) do
    case OptimumStructureSupport.primary_module(ast) do
      {segments, line} ->
        name = Enum.map_join(segments, ".", &Atom.to_string/1)

        stem =
          rest
          |> Enum.join("/")
          |> String.replace_suffix("_test.exs", "")

        accepted = accepted_paths(stem, params)

        cond do
          not String.ends_with?(name, "Test") ->
            [issue(issue_meta, line, "Test module #{name} should end in Test.")]

          subject_path(name) in accepted ->
            []

          mirrors_defining_counterpart?(root, stem, name) ->
            []

          true ->
            [
              issue(
                issue_meta,
                line,
                "Test module #{name} does not match its path test/#{Enum.join(rest, "/")}."
              )
            ]
        end

      nil ->
        []
    end
  end

  defp accepted_paths(stem, params) do
    layer_dirs =
      params
      |> Params.get(:web_layer_dirs, __MODULE__)
      |> OptimumStructureSupport.to_strings()

    stem
    |> String.split("/")
    |> OptimumStructureSupport.module_paths(layer_dirs)
  end

  defp subject_path(name) do
    name
    |> String.replace_suffix("Test", "")
    |> Macro.underscore()
  end

  # A test that mirrors the exact path of the `lib/` file defining its subject follows the
  # file layout; that file's own name/path disagreement is `ModulePathMismatch`'s to report.
  defp mirrors_defining_counterpart?(root, stem, test_name) do
    subject = String.replace_suffix(test_name, "Test", "")
    path = Path.join(root ++ ["lib", stem <> ".ex"])

    with true <- File.regular?(path),
         {:ok, source} <- File.read(path),
         {:ok, ast} <- Code.string_to_quoted(source) do
      ast
      |> OptimumStructureSupport.modules()
      |> Enum.any?(&(Enum.map_join(&1.segments, ".", fn s -> Atom.to_string(s) end) == subject))
    else
      _other -> false
    end
  end

  defp counterpart_issues(ast, root, rest, params, issue_meta) do
    stem =
      rest
      |> Enum.join("/")
      |> String.replace_suffix("_test.exs", "")

    required? = Params.get(params, :require_test_counterpart, __MODULE__)

    if required? and not counterpart?(root, stem) do
      line =
        ast
        |> OptimumStructureSupport.primary_module()
        |> then(&if(&1, do: elem(&1, 1), else: 1))

      [issue(issue_meta, line, "No lib/#{stem}.ex exists for this test file.")]
    else
      []
    end
  end

  # `lib/<stem>.ex`, or a `lib/<stem>/` directory (Phoenix tests `user_live_test.exs` cover
  # the `user_live/index.ex` and `user_live/show.ex` modules).
  defp counterpart?(root, stem) do
    base = Path.join(root ++ ["lib", stem])
    File.regular?(base <> ".ex") or File.dir?(base)
  end

  defp issue(issue_meta, line, message),
    do: format_issue(issue_meta, message: message, line_no: line)
end
