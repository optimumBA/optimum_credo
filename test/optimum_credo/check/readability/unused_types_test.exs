defmodule OptimumCredo.Check.Readability.UnusedTypesTest do
  use Credo.Test.Case

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
end
