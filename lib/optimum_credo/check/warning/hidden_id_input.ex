defmodule OptimumCredo.Check.Warning.HiddenIdInput do
  @moduledoc """
  Finds hidden `*_id` form inputs in HEEx templates.

  Values submitted by the client are not authorisation. A hidden `user_id` or `account_id`
  that the server trusts lets any user act on someone else's record. This is a hint, not a
  vulnerability finding: the server may re-derive and verify the id, in which case the field
  can be added to `allowed_fields`.

  Reads `<input>` and `<.input>` tags inside `~H` sigils (a raw `.heex` source file is scanned only
  when handed to the check directly; stock `mix credo` drops `.heex` files as unparseable), with `type`
  exactly `"hidden"` (any case). The field is the quoted `name`, else the `field={@form[:user_id]}`
  expression, else (when neither is present) the quoted `id`. A bare `id` field and
  `hidden_input/3` helper calls are not reported; attribute values built dynamically cannot be
  seen. Tags inside HTML or HEEx comments, `<script>`/`<style>` bodies and text are ignored;
  `data-type="hidden"` is not a `type`.

  ## Parameters

  - `allowed_fields`: field names (such as `"locale_id"`) to accept.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [allowed_fields: []],
    explanations: [
      check: """
      Do not rely on hidden `*_id` inputs for authorisation. Derive the owner from the
      session/socket and scope queries by it. Reported for `<input type="hidden">` and
      `<.input type="hidden">` whose name, id or field ends in `_id`. Partial heuristic;
      Sobelow and review cover the semantics. Opt-in, low priority.
      """,
      params: [allowed_fields: "Hidden field names accepted as written."]
    ]

  alias OptimumCredo.OptimumIdiomsSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    allowed =
      params
      |> Params.get(:allowed_fields, __MODULE__)
      |> Enum.map(&to_string/1)

    for %{name: name, attrs: attrs, line: line} <- OptimumIdiomsSupport.heex_tags(source_file),
        name in ["input", ".input"],
        hidden?(attrs),
        field = hidden_id_field(attrs),
        field not in allowed do
      format_issue(issue_meta,
        message:
          "Hidden input #{inspect(field)} is client-controlled; do not use it for authorisation.",
        line_no: line
      )
    end
  end

  defp hidden?(attrs) do
    Enum.any?(attrs, fn
      {"type", {:string, type}, _line} ->
        type
        |> String.trim()
        |> String.downcase() == "hidden"

      _attr ->
        false
    end)
  end

  defp hidden_id_field(attrs) do
    candidate =
      Enum.find_value(attrs, &named(&1, "name")) || Enum.find_value(attrs, &field_expression/1) ||
        Enum.find_value(attrs, &named(&1, "id"))

    candidate
    |> strip_form()
    |> id_field()
  end

  defp named({name, {:string, value}, _line}, name), do: value
  defp named(_attr, _name), do: nil

  defp field_expression({"field", {:expr, expression}, _line}) do
    case Regex.run(~r/\[:([a-z0-9_]+)\]\s*\z/, expression) do
      [_all, field] -> field
      nil -> nil
    end
  end

  defp field_expression(_attr), do: nil

  defp strip_form(nil), do: nil

  defp strip_form(name) do
    name
    |> String.trim()
    |> String.split(["[", "]"], trim: true)
    |> List.last()
  end

  defp id_field(field) when is_binary(field),
    do: if(String.ends_with?(field, "_id") and field != "_id", do: field)

  defp id_field(nil), do: nil
end
