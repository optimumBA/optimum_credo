defmodule OptimumCredo.Check.Warning.CallerModuleAttributes do
  @moduledoc """
  Finds generic module attributes in quoted code that a library macro injects into
  the caller's module.

  Module attributes such as `@opts`, `@app`, and `@pos` live in the module that
  compiles the quoted code. Two libraries that inject the same generic attribute
  can overwrite each other's state or make a later read fail. Give private
  attributes an owner-specific name, or explicitly allow documented caller
  configuration attributes.

  This is a static heuristic. It inspects literal attribute AST inside `quote`
  blocks and literal `Module.get_attribute/2`, `Module.put_attribute/3`, and
  `Module.register_attribute/3` calls targeting `__MODULE__`. It does not execute
  macros or resolve dynamic targets. A `defmodule` nested inside a quote owns its
  own attributes and is skipped. `unquote` and `unquote_splicing` expressions are
  not expanded; the check can miss caller AST that those expressions construct.

  ## Parameters

  - `required_prefix`: optional string or atom. Attributes beginning with this
    prefix followed by `_` are treated as owner-specific. If omitted, the check
    infers the prefix from the first segment of the lexical module name. For
    example, `Boundary.Definition` accepts `@__boundary_definition_opts__`.
  - `allow_attributes`: explicit list of intentional caller attributes, such as
    `[:my_library_config]`.

  A leading underscore alone is not an owner namespace: `@_opts` can still
  collide with another library's `@_opts`. Underscores around an owner-specific
  name are accepted. Built-in language and compiler hook attributes are always
  allowed.
  """

  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    param_defaults: [required_prefix: nil, allow_attributes: []],
    explanations: [
      check: """
      Avoid injecting generic module attributes such as `@opts`, `@pos`, or `@app`
      into the caller from a quote. Those attributes belong to the caller's module
      and can collide with another macro. Use an owner-specific name, optionally
      wrapped in leading/trailing underscores, or explicitly allow intentional
      caller configuration.

      Built-in language and compiler attributes (including `@before_compile`,
      `@on_definition`, `@doc`, and `@spec`) are allowed. A `defmodule` nested in a
      quote owns its own attributes and is ignored.

      This check only reads literal quote AST. It does not expand arbitrary macros
      or infer dynamic `Module.*` targets. It also does not inspect AST returned by
      `unquote` or `unquote_splicing`.

      ## Bad

      ```elixir
      defmacro __using__(opts) do
        quote do
          @opts unquote(opts)
          @app :demo
        end
      end
      ```

      ## Good

      ```elixir
      defmacro __using__(opts) do
        quote do
          @__my_library_opts__ unquote(opts)
          @__my_library_app__ :demo
        end
      end
      ```

      If the attribute is part of a documented caller API, add it to
      `allow_attributes` in the Credo configuration.
      """,
      params: [
        required_prefix:
          "Optional owner prefix. Attributes beginning with this prefix and `_` are accepted.",
        allow_attributes:
          "Attribute names that are intentional documented caller configuration, as atoms or strings."
      ]
    ]

  @builtin_attributes MapSet.new(~w(
    after_compile after_verify before_compile behaviour callback macrocallback
    compile deprecated derive dialyzer doc enforce_keys external_resource file
    impl moduledoc on_definition on_load opaque optional_callbacks protocol
    spec type typep typedoc vsn
  )a)

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    required_prefix = Params.get(params, :required_prefix, __MODULE__)
    allow_attributes = Params.get(params, :allow_attributes, __MODULE__)

    source_file
    |> Credo.SourceFile.ast()
    |> scan_source(nil)
    |> Enum.uniq_by(fn {attribute, line, _lexical_prefix} -> {attribute, line} end)
    |> Enum.reject(fn {attribute, _line, lexical_prefix} ->
      prefix = required_prefix || lexical_prefix
      allowed_attribute?(attribute, prefix, allow_attributes)
    end)
    |> Enum.map(fn {attribute, line, _lexical_prefix} ->
      format_issue(issue_meta,
        message:
          "Avoid injecting generic module attribute @#{attribute} into the caller. " <>
            "Use an owner-specific name, or allow this " <>
            "documented caller attribute explicitly.",
        line_no: line
      )
    end)
  end

  defp scan_source({:quote, _meta, args}, lexical_prefix) do
    args
    |> quote_body()
    |> scan_quoted()
    |> Enum.map(fn {attribute, line} -> {attribute, line, lexical_prefix} end)
  end

  defp scan_source({:defmodule, _meta, [name, [do: body]]}, lexical_prefix) do
    scan_source(body, module_prefix(name, lexical_prefix))
  end

  defp scan_source(term, lexical_prefix) when is_tuple(term) do
    direct_caller_attribute =
      case module_attribute_call(term, &explicit_expansion_caller?/1) do
        {attribute, line} -> [{attribute, line, lexical_prefix}]
        nil -> []
      end

    nested =
      term
      |> Tuple.to_list()
      |> Enum.flat_map(&scan_source(&1, lexical_prefix))

    direct_caller_attribute ++ nested
  end

  defp scan_source(list, lexical_prefix) when is_list(list),
    do: Enum.flat_map(list, &scan_source(&1, lexical_prefix))

  defp scan_source(_term, _lexical_prefix), do: []

  defp scan_quoted({:defmodule, _meta, _args}), do: []
  defp scan_quoted({:unquote, _meta, _args}), do: []
  defp scan_quoted({:unquote_splicing, _meta, _args}), do: []

  defp scan_quoted(term) when is_tuple(term) do
    [quoted_attribute(term), module_attribute_call(term, &quoted_caller_module?/1)]
    |> Enum.reject(&is_nil/1)
    |> Kernel.++(
      term
      |> Tuple.to_list()
      |> Enum.flat_map(&scan_quoted/1)
    )
  end

  defp scan_quoted(list) when is_list(list), do: Enum.flat_map(list, &scan_quoted/1)
  defp scan_quoted(_term), do: []

  defp quote_body(args) do
    Enum.find_value(args, fn
      options when is_list(options) -> Keyword.get(options, :do)
      _other -> nil
    end)
  end

  defp quoted_attribute({:@, meta, [{attribute, _attribute_meta, _context}]})
       when is_atom(attribute) do
    {attribute, meta[:line] || 1}
  end

  defp quoted_attribute(_term), do: nil

  defp module_attribute_call(
         {{:., _dot_meta, [module, function]}, meta, [target, attribute | _rest]},
         target_predicate
       )
       when function in [:get_attribute, :put_attribute, :register_attribute] and
              is_atom(attribute) do
    if module_attribute_api?(module) and target_predicate.(target) do
      {attribute, meta[:line] || 1}
    end
  end

  defp module_attribute_call(_term, _target_predicate), do: nil

  defp allowed_attribute?(attribute, required_prefix, allow_attributes) do
    attribute_name = Atom.to_string(attribute)

    attribute in @builtin_attributes or
      owner_specific_attribute?(attribute_name, required_prefix) or
      attribute_name in normalize_attributes(allow_attributes)
  end

  defp owner_specific_attribute?(attribute_name, required_prefix) do
    prefix = normalize_prefix(required_prefix)
    normalized_name = String.trim(attribute_name, "_")

    prefix != "" and String.starts_with?(normalized_name, prefix <> "_")
  end

  defp normalize_prefix(nil), do: ""
  defp normalize_prefix(prefix) when is_atom(prefix), do: Atom.to_string(prefix)
  defp normalize_prefix(prefix) when is_binary(prefix), do: prefix

  defp normalize_attributes(attributes) do
    attributes
    |> List.wrap()
    |> Enum.flat_map(fn
      attribute when is_atom(attribute) -> [Atom.to_string(attribute)]
      attribute when is_binary(attribute) -> [attribute]
      _other -> []
    end)
  end

  defp module_prefix({:__aliases__, _meta, [root]}, parent_prefix) when is_atom(root) do
    parent_prefix ||
      root
      |> Atom.to_string()
      |> Macro.underscore()
  end

  defp module_prefix({:__aliases__, _meta, [root | _rest]}, _parent_prefix) when is_atom(root) do
    root
    |> Atom.to_string()
    |> Macro.underscore()
  end

  defp module_prefix(module, _parent_prefix) when is_atom(module) do
    module
    |> Module.split()
    |> List.first()
    |> Macro.underscore()
  end

  defp module_prefix(_name, parent_prefix), do: parent_prefix

  defp module_attribute_api?({:__aliases__, _meta, [:Module]}), do: true
  defp module_attribute_api?(Module), do: true
  defp module_attribute_api?(_module), do: false

  defp quoted_caller_module?({:__MODULE__, _meta, _context}), do: true

  defp quoted_caller_module?(target), do: explicit_expansion_caller?(target)

  defp explicit_expansion_caller?(
         {{:., _meta, [{:__CALLER__, _caller_meta, _context}, :module]}, _dot_meta, []}
       ),
       do: true

  defp explicit_expansion_caller?({:., _meta, [{:__CALLER__, _caller_meta, _context}, :module]}),
    do: true

  defp explicit_expansion_caller?(_target), do: false
end
