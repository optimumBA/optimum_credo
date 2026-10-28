defmodule OptimumCredo.Check.Readability.GenericModuleName do
  @moduledoc """
  Finds modules whose last name segment is a generic catch-all such as `Helpers` or `Utils`.

  Modules should be named for the noun they model (`Billing.Invoice`, not
  `Billing.Helpers`). The last segment of each `defmodule` name is compared,
  case-sensitively, with `banned_names`; `MyApp.Utils` is reported, `MyApp.StringUtils`
  and `MyApp.Utilities.Invoice` are not.

  This is a naming heuristic with no semantic understanding: whether a module is
  really a grab-bag is a human judgement. Allow deliberate exceptions with
  `allowed_modules` (full names, optionally with a leading `Elixir.`). Modules with
  dynamic names are skipped.

  ## Parameters

  - `banned_names`: generic last segments to report (strings or atoms).
  - `allowed_modules`: full module names that are accepted.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [
      banned_names: ~w(Common Helper Helpers Misc Stuff Util Utilities Utils),
      allowed_modules: []
    ],
    explanations: [
      check: """
      Name modules for what they are, not for being a collection of leftovers.

      ## Bad

      ```elixir
      defmodule MyApp.Billing.Helpers do
      end
      ```

      ## Good

      ```elixir
      defmodule MyApp.Billing.InvoiceFormatter do
      end
      ```

      Only the last segment is compared with `banned_names`. This is a heuristic; use
      `allowed_modules` for intentional names.
      """,
      params: [
        banned_names: "Generic last segments to report.",
        allowed_modules: "Full module names that are accepted."
      ]
    ]

  alias OptimumCredo.OptimumStructureSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    banned =
      params
      |> Params.get(:banned_names, __MODULE__)
      |> OptimumStructureSupport.to_strings()

    allowed =
      params
      |> Params.get(:allowed_modules, __MODULE__)
      |> allowed_names()

    source_file
    |> Credo.SourceFile.ast()
    |> OptimumStructureSupport.modules()
    |> Enum.flat_map(&check(&1, banned, allowed, issue_meta))
  end

  defp check(%{segments: segments, line: line}, banned, allowed, issue_meta) do
    names = Enum.map(segments, &Atom.to_string/1)
    full = Enum.join(names, ".")
    last = List.last(names)

    if last in banned and full not in allowed do
      [
        format_issue(issue_meta,
          message:
            "Module name #{full} is generic; name it for what it models instead of #{last}.",
          line_no: line
        )
      ]
    else
      []
    end
  end

  defp allowed_names(modules) do
    modules
    |> OptimumStructureSupport.to_strings()
    |> Enum.map(&String.replace_prefix(&1, "Elixir.", ""))
  end
end
