defmodule OptimumCredo.Check.Readability.GettextDomain do
  @moduledoc """
  Finds Gettext calls without an explicit domain in `lib/`.

  Bare `gettext/1`, `gettext_noop/1`, `ngettext/3`, `pgettext/2` and `npgettext/4` calls
  all use the `default` domain. Projects that split translations per feature expect
  `dgettext("domain", "message")` so strings land in the right `.po` file.

  **Gated by `ash: true`**, because the convention comes from the Ash project this rule was
  collected from. The check does nothing unless you set `ash: true`.

  Reported (files under `lib/` only):

  - local (imported) calls to the bare functions above;
  - `dgettext`, `dngettext`, `dpgettext`, `dnpgettext`, `dgettext_noop` and `dngettext_noop`
    whose first argument is a string
    literal that is not in `allowed_domains`, when `allowed_domains` is non-empty.

  `dpgettext` already carries a domain, so it is validated like `dgettext` rather than reported
  as bare. Remote calls such as `Gettext.gettext(MyApp.Gettext, "...")`, and domains passed as
  variables, are not inspected. Typespecs that mention these names are not calls.

  `with_locale` is **not** in the default `bare_functions`: it picks a locale, not a text
  domain, so `dgettext` is no replacement for it (the lookups inside the block are what carry
  a domain, and those are checked on their own). The original rule collection names it, so
  you can add `:with_locale` to `bare_functions`; it is then reported with a message that
  says this instead of advising `dgettext`.

  ## Parameters

  - `ash`: default `false`; set `true` to enable.
  - `allowed_domains`: domain strings accepted by the `d*` functions; empty accepts any
    literal domain.
  - `bare_functions`: functions reported when called without a domain. Default
    `[:gettext, :ngettext, :pgettext, :npgettext, :gettext_noop]`.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [
      ash: false,
      allowed_domains: [],
      bare_functions: [:gettext, :ngettext, :pgettext, :npgettext, :gettext_noop]
    ],
    explanations: [
      check: """
      Use a per-feature Gettext domain.

      ## Bad

      ```elixir
      gettext("Save")
      ```

      ## Good

      ```elixir
      dgettext("accounts", "Save")
      ```

      Set `ash: true` to enable the check, and `allowed_domains` to restrict the domain names.
      """,
      params: [
        ash: "Enable the Ash heuristics (default false).",
        allowed_domains: "Accepted domain strings; empty accepts any literal.",
        bare_functions: "Gettext functions that must not be called without a domain."
      ]
    ]

  alias OptimumCredo.OptimumDataSupport

  @domain_functions [
    :dgettext,
    :dngettext,
    :dpgettext,
    :dnpgettext,
    :dgettext_noop,
    :dngettext_noop
  ]
  @type_attributes [:spec, :callback, :macrocallback, :type, :typep, :opaque]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    if Params.get(params, :ash, __MODULE__) == true and
         OptimumDataSupport.in_dir?(source_file, "lib/") do
      issue_meta = IssueMeta.for(source_file, params)
      bare = Params.get(params, :bare_functions, __MODULE__)

      allowed =
        params
        |> Params.get(:allowed_domains, __MODULE__)
        |> Enum.map(&to_string/1)

      source_file
      |> Credo.SourceFile.ast()
      |> local_calls()
      |> Enum.flat_map(&problem(&1, bare, allowed))
      |> Enum.map(fn {message, function, meta} ->
        format_issue(issue_meta,
          message: message,
          trigger: Atom.to_string(function),
          line_no: OptimumDataSupport.line(meta)
        )
      end)
    else
      []
    end
  end

  defp local_calls(ast) do
    {_ast, calls} = Macro.prewalk(ast, [], &collect_call/2)

    Enum.reverse(calls)
  end

  # A definition head is not a call: keep its arguments, drop its name.
  defp collect_call({definition, meta, [head | rest]}, acc)
       when definition in [:def, :defp, :defmacro, :defmacrop] do
    {{definition, meta, [head_arguments(head) | rest]}, acc}
  end

  # Typespecs name functions without calling them.
  defp collect_call({:@, _meta, [{attribute, _tuple_meta, _args}]}, acc)
       when attribute in @type_attributes do
    {nil, acc}
  end

  defp collect_call({function, meta, args} = node, acc)
       when is_atom(function) and is_list(args) do
    {node, [{function, meta, args} | acc]}
  end

  defp collect_call(node, acc), do: {node, acc}

  defp head_arguments({:when, _meta, [head | guards]}), do: [head_arguments(head), guards]
  defp head_arguments({_name, _meta, args}) when is_list(args), do: args
  defp head_arguments(other), do: other

  defp problem({function, meta, args}, bare, allowed) do
    cond do
      function in @domain_functions ->
        domain_problem(function, meta, args, allowed)

      function == :with_locale and function in bare ->
        [
          {"`with_locale` sets the locale, not a domain; it has no `dgettext` replacement. " <>
             "Review the lookups inside it, or remove it from `bare_functions`.", function, meta}
        ]

      function in bare ->
        [
          {"Bare `#{function}` uses the default domain; use the `d*` variant with a domain.",
           function, meta}
        ]

      true ->
        []
    end
  end

  defp domain_problem(function, meta, [domain | _tail], [_head | _tail2] = allowed)
       when is_binary(domain) do
    if domain in allowed,
      do: [],
      else: [
        {"Gettext domain #{inspect(domain)} is not one of #{inspect(allowed)}.", function, meta}
      ]
  end

  defp domain_problem(_function, _meta, _args, _allowed), do: []
end
