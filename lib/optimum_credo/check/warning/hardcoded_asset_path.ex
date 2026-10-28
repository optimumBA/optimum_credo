defmodule OptimumCredo.Check.Warning.HardcodedAssetPath do
  @moduledoc """
  Finds `src`/`href` attributes whose string literal starts with a static asset prefix
  such as `/images/` in HEEx templates.

  Templates are read from `~H` sigils in Elixir files. A raw `.heex` `Credo.SourceFile` is also
  scanned when one is handed to the check directly, but stock `mix credo` does not do that: it
  parses every selected file as Elixir, marks `.heex` files invalid and drops them before any
  check runs (even with a `.heex` glob in `included`). In a normal run only `~H` sigils are seen. Reported: quoted values (`src="/images/a.png"`) and a brace
  expression that is only a string literal (`src={"/images/a.png"}`) on any tag, including
  components such as `<.link href=...>`. Not reported: other expressions (`src={~p"/images/a.png"}`,
  `src={@src}`), external URLs, and anything inside HTML comments, HEEx/EEx comments,
  `<script>`/`<style>` bodies, `{...}` body interpolation or plain text between tags.
  Other sigils (`~L`, `~E`) are not scanned. The tokenizer is conservative, not a full HEEx
  parser.

  ## Parameters

  - `prefixes`: path prefixes treated as static assets.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [prefixes: ["/images/", "/assets/", "/css/", "/js/", "/fonts/"]],
    explanations: [
      check: """
      Reference static assets through verified routes (`~p"/images/logo.png"`) or
      `static_path/2`, not a hard-coded string in `src` or `href`. Only HEEx text is
      inspected. Opt-in, low priority.

      ## Bad

      ```heex
      <img src="/images/logo.png" />
      ```

      ## Good

      ```heex
      <img src={~p"/images/logo.png"} />
      ```
      """,
      params: [prefixes: "Path prefixes considered static assets."]
    ]

  alias OptimumCredo.OptimumIdiomsSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    prefixes = Params.get(params, :prefixes, __MODULE__)

    for tag <- OptimumIdiomsSupport.heex_tags(source_file),
        {name, value, line} <- tag.attrs,
        String.downcase(name) in ["src", "href"],
        path = literal_path(value),
        Enum.any?(prefixes, &String.starts_with?(path, &1)) do
      format_issue(issue_meta,
        message: "Hard-coded asset path #{inspect(path)}; use `~p` or `static_path/2`.",
        line_no: line
      )
    end
  end

  # A quoted attribute value, or a brace expression that is exactly one string literal.
  defp literal_path({:string, path}), do: path

  defp literal_path({:expr, expression}) do
    case Regex.run(~r/\A\s*"([^"\\#]*)"\s*\z/, expression) do
      [_all, path] -> path
      nil -> nil
    end
  end

  defp literal_path(_value), do: nil
end
