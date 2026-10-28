defmodule OptimumCredo.Check.Readability.UnusedTypesTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.UnusedTypes

  test "it should NOT report used type definitions" do
    """
    defmodule MyModule do
      @type conn :: Plug.Conn.t()
      @type params :: map()

      @spec index(conn(), params()) :: conn()
      def index(conn, _params), do: conn
    end
    """
    |> to_source_file()
    |> run_check(UnusedTypes)
    |> refute_issues()
  end

  test "it should report unused type definitions" do
    """
    defmodule MyModule do
      @type short_id :: String.t()
      @type conn :: Plug.Conn.t()

      @spec index(conn()) :: conn()
      def index(conn), do: conn
    end
    """
    |> to_source_file()
    |> run_check(UnusedTypes)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Unused type definition: short_id"
    end)
  end

  test "it should report multiple unused types" do
    """
    defmodule MyModule do
      @type unused_one :: String.t()
      @type conn :: Plug.Conn.t()
      @type unused_two :: integer()

      @spec index(conn()) :: conn()
      def index(conn), do: conn
    end
    """
    |> to_source_file()
    |> run_check(UnusedTypes)
    |> assert_issues(fn issues ->
      assert length(issues) == 2
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &String.contains?(&1, "unused_one"))
      assert Enum.any?(messages, &String.contains?(&1, "unused_two"))
    end)
  end

  test "it should detect type usage in function bodies" do
    """
    defmodule MyModule do
      @type user_id :: String.t()

      def process_user do
        user_id() |> String.length()
      end
    end
    """
    |> to_source_file()
    |> run_check(UnusedTypes)
    |> refute_issues()
  end

  test "it should detect type usage in private function specs" do
    """
    defmodule MyModule do
      @type internal_data :: map()

      @spec process_data(internal_data()) :: :ok
      defp process_data(_data), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(UnusedTypes)
    |> refute_issues()
  end

  test "it should handle complex type definitions" do
    """
    defmodule MyModule do
      @type complex_type :: {:ok, String.t()} | {:error, atom()}
      @type unused_complex :: %{name: String.t(), age: integer()}

      @spec process(complex_type()) :: :ok
      def process({:ok, _}), do: :ok
      def process({:error, _}), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(UnusedTypes)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Unused type definition: unused_complex"
    end)
  end

  test "it should handle modules without type definitions" do
    """
    defmodule MyModule do
      def simple_function, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(UnusedTypes)
    |> refute_issues()
  end

  test "it should handle modules with only unused types" do
    """
    defmodule MyModule do
      @type unused_one :: String.t()
      @type unused_two :: integer()

      def simple_function, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(UnusedTypes)
    |> assert_issues(fn issues ->
      assert length(issues) == 2
    end)
  end

  test "it should handle type usage in function bodies with guards" do
    """
    defmodule MyModule do
      @type user_data :: map()

      @spec process(user_data()) :: :ok
      def process(data) when is_map(data) do
        :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(UnusedTypes)
    |> refute_issues()
  end

  test "it should detect usage in return type specifications" do
    """
    defmodule MyModule do
      @type result :: {:ok, String.t()}

      @spec get_data() :: result()
      def get_data, do: {:ok, "data"}
    end
    """
    |> to_source_file()
    |> run_check(UnusedTypes)
    |> refute_issues()
  end

  test "it should handle nested type usage" do
    """
    defmodule MyModule do
      @type inner :: String.t()
      @type outer :: {:wrapper, inner()}

      @spec wrap(String.t()) :: outer()
      def wrap(str), do: {:wrapper, str}
    end
    """
    |> to_source_file()
    |> run_check(UnusedTypes)
    |> refute_issues()
  end

  describe "false-positive regressions" do
    test "does not report the conventional t type" do
      """
      defmodule MyApp.Schema do
        use Ecto.Schema

        @type t :: %__MODULE__{}

        schema "things" do
          field :name, :string
        end
      end
      """
      |> to_source_file()
      |> run_check(UnusedTypes)
      |> refute_issues()
    end

    test "reports t when it is not in ignored_types" do
      """
      defmodule MyApp.Schema do
        @type t :: %__MODULE__{}
      end
      """
      |> to_source_file()
      |> run_check(UnusedTypes, ignored_types: [])
      |> assert_issue(&(&1.message =~ "Unused type definition: t"))
    end

    test "sees usage inside compile-time conditionals" do
      """
      defmodule MyApp.Hook do
        @type socket :: Phoenix.LiveView.Socket.t()

        if Application.compile_env(:my_app, :sandbox) do
          @spec on_mount(atom(), socket()) :: {:cont, socket()}
          def on_mount(_name, socket), do: {:cont, socket}
        else
          @spec on_mount(atom(), socket()) :: {:cont, socket()}
          def on_mount(_name, socket), do: {:cont, socket}
        end
      end
      """
      |> to_source_file()
      |> run_check(UnusedTypes)
      |> refute_issues()
    end

    test "sees usage in parametrized types, callbacks and rescue bodies" do
      """
      defmodule MyApp.Behaviour do
        @type pair(a) :: {a, a}
        @type ids :: pair(integer())
        @type reason :: term()

        @callback fetch(ids()) :: :ok

        def run(x) do
          x
        rescue
          _ -> reason()
        end
      end
      """
      |> to_source_file()
      |> run_check(UnusedTypes)
      |> refute_issues()
    end

    test "does not let a nested module's specs use the outer module's types" do
      """
      defmodule MyApp.Outer do
        @type id :: integer()

        defmodule Inner do
          @spec f(id()) :: id()
          def f(x), do: x
        end
      end
      """
      |> to_source_file()
      |> run_check(UnusedTypes)
      |> assert_issue(&(&1.message =~ "Unused type definition: id"))
    end

    test "checks modules whose body is a single expression" do
      """
      defmodule MyApp.Tiny do
        @type unused :: integer()
      end
      """
      |> to_source_file()
      |> run_check(UnusedTypes)
      |> assert_issue(&(&1.message =~ "Unused type definition: unused"))
    end

    test "counts bare type references in specs and type bodies" do
      """
      defmodule MyApp.Bare do
        @type user :: map()
        @type id :: integer()
        @type users :: [user]
        @opaque handle :: id
        @callback load(handle) :: users

        @spec get(id) :: user
        def get(_id), do: %{}
      end
      """
      |> to_source_file()
      |> run_check(UnusedTypes)
      |> refute_issues()
    end

    test "counts bare references in parameterised aliases, annotations and bounds" do
      """
      defmodule MyApp.Bounds do
        @type item :: integer()
        @type limit :: integer()
        @type pair(a) :: {a, a}
        @type items :: pair(item)
        @spec cap(n :: limit, x) :: x when x: items
        def cap(_n, x), do: x
      end
      """
      |> to_source_file()
      |> run_check(UnusedTypes)
      |> refute_issues()
    end

    test "type parameters and when keys do not rescue unused types of the same name" do
      """
      defmodule MyApp.Shadow do
        @type a :: integer()
        @type value :: term()
        @type pair(a) :: {a, a}
        @type box :: pair(integer())

        @spec wrap(value) :: box when value: var
        def wrap(v), do: v
      end
      """
      |> to_source_file()
      |> run_check(UnusedTypes)
      |> assert_issues(fn issues ->
        assert issues
               |> Enum.map(& &1.message)
               |> Enum.sort() == [
                 "Unused type definition: a",
                 "Unused type definition: value"
               ]
      end)
    end

    test "arbitrary runtime variables and spec function names are not type references" do
      """
      defmodule MyApp.Runtime do
        @type user :: map()
        @type get :: integer()

        @spec get(integer()) :: integer()
        def get(x) do
          user = x
          user
        end
      end
      """
      |> to_source_file()
      |> run_check(UnusedTypes)
      |> assert_issues(fn issues -> assert length(issues) == 2 end)
    end

    test "bare references in nested modules are scoped to their own module" do
      """
      defmodule MyApp.Outer do
        @type id :: integer()

        defmodule Inner do
          @type name :: binary()

          @spec f(id, name) :: name
          def f(_id, name), do: name
        end
      end
      """
      |> to_source_file()
      |> run_check(UnusedTypes)
      |> assert_issue(&(&1.message == "Unused type definition: id"))
    end
  end
end
