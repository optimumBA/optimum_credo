defmodule OptimumCredo.Check.Readability.TypeParenthesesConsistencyTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.TypeParenthesesConsistency

  defp run(source, params \\ []) do
    source
    |> to_source_file()
    |> run_check(TypeParenthesesConsistency, params)
  end

  test "accepts the default style: bare definitions and parenthesized references" do
    """
    defmodule Demo do
      @type t :: %__MODULE__{name: String.t(), tags: [atom()], meta: map()}
      @typep id :: pos_integer()
      @opaque token :: binary()
      @type result(a) :: {:ok, a} | {:error, term()}

      @callback load(id()) :: {:ok, t()} | :error
      @spec run(t(), keyword()) :: result(t())
      def run(_t, _opts), do: :ok
    end
    """
    |> run()
    |> refute_issues()
  end

  test "reports a definition with parentheses under definition_style :bare" do
    """
    defmodule Demo do
      @type t() :: map()
      @typep id() :: integer()
    end
    """
    |> run()
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [2, 3]
      assert hd(issues).message =~ "without parentheses"
    end)
  end

  test "reports bare built-in, local, and remote references under reference_style :parens" do
    """
    defmodule Demo do
      @type t :: map
      @type id :: integer
      @spec run(t, id) :: String.t
      def run(_t, _id), do: ""
    end
    """
    |> run()
    |> assert_issues(fn issues ->
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &(&1 =~ "reference map with"))
      assert Enum.any?(messages, &(&1 =~ "reference integer with"))
      assert Enum.any?(messages, &(&1 =~ "reference t with"))
      assert Enum.any?(messages, &(&1 =~ "reference id with"))
      assert Enum.any?(messages, &(&1 =~ "String.t()"))
    end)
  end

  test "finds references nested in unions, lists, tuples, maps, functions and constraints" do
    """
    defmodule Demo do
      @type t :: {:ok, [map]} | %{optional(atom()) => list} | (term -> binary)
      @spec run(a) :: a when a: term
      def run(a), do: a
    end
    """
    |> run()
    |> assert_issues(fn issues ->
      assert issues
             |> Enum.map(
               &(~r/reference (\w+)/
                 |> Regex.run(&1.message, capture: :all_but_first)
                 |> hd())
             )
             |> Enum.sort() ==
               ["binary", "list", "map", "term", "term"]
    end)
  end

  test "does not report type variables, annotations, binary patterns, or unknown bare names" do
    """
    defmodule Demo do
      @type pair(a, b) :: {a, b}
      @type wrapper(item) :: list(item)
      @spec identity(a) :: a when a: var
      @spec put(key :: atom(), value) :: :ok when value: term()
      @spec bits(<<_::binary>>) :: <<_::8>>
      @spec other(item) :: unknown_type
      def identity(a), do: a
    end
    """
    |> run()
    |> refute_issues()
  end

  test "parenthesized definitions and bare references with the opposite styles" do
    source = """
    defmodule Demo do
      @type t() :: map
      @type id :: String.t()
      @spec run(t()) :: String.t()
    end
    """

    source
    |> run(definition_style: :parens, reference_style: :bare)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [3, 3, 4, 4]
      assert Enum.any?(issues, &(&1.message =~ "id with parentheses"))
      assert Enum.any?(issues, &(&1.message =~ "String.t without parentheses"))
    end)
  end

  test "reference_style :bare accepts bare remote and built-in references" do
    """
    defmodule Demo do
      @type t() :: %{name: String.t, id: integer}
    end
    """
    |> run(definition_style: :parens, reference_style: :bare)
    |> refute_issues()
  end

  test "string style values work and unknown values raise instead of falling back" do
    "defmodule D do\n  @type t() :: map()\nend"
    |> run(definition_style: "bare")
    |> assert_issue()

    source = to_source_file("defmodule D do\n  @type t() :: map()\nend")

    assert_raise ArgumentError, ~r/invalid definition_style :nonsense/, fn ->
      TypeParenthesesConsistency.run(source, definition_style: :nonsense)
    end

    assert_raise ArgumentError, ~r/invalid reference_style "weird"/, fn ->
      TypeParenthesesConsistency.run(source, reference_style: "weird")
    end
  end

  test "type variables that share a name with a local type are not references" do
    """
    defmodule D do
      @type t :: map()
      @type wrapper(t) :: [t]
      @type pair(a, t) :: {a, t}
      @spec first(wrapper(t)) :: t when t: term()
      def first([head | _tail]), do: head
    end
    """
    |> run()
    |> refute_issues()
  end

  test "a local type is still reported where it is not shadowed by a variable" do
    """
    defmodule D do
      @type t :: map()
      @type wrapper(a) :: [a]
      @type list_of_t :: [t]
      @spec build(wrapper(a)) :: t when a: term()
      def build(_value), do: %{}
    end
    """
    |> run()
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [4, 5]
    end)
  end

  test "reports nested, remote and callback references on the right line" do
    """
    defmodule D do
      @callback run(
                  map,
                  keyword
                ) :: {:ok, String.t} | :error
    end
    """
    |> run()
    |> assert_issues(fn issues ->
      assert issues
             |> Enum.map(& &1.line_no)
             |> Enum.sort() == [3, 4, 5]
    end)
  end

  test "ignores strings, docs and non-type attributes" do
    ~S'''
    defmodule Demo do
      @moduledoc "@type t() :: map"
      @typedoc "A map"
      @attr map
      def text, do: "@spec run(map) :: String.t"
    end
    '''
    |> run()
    |> refute_issues()
  end
end
