defmodule OptimumCredo.Check.Readability.ExtractableSpecTypesTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.ExtractableSpecTypes

  test "it should NOT report when types are already extracted" do
    """
    defmodule MyController do
      @type conn :: Plug.Conn.t()
      @type params :: map()

      @spec show(conn(), params()) :: conn()
      def show(conn, _params), do: conn

      @spec index(conn()) :: conn()
      def index(conn), do: conn
    end
    """
    |> to_source_file()
    |> run_check(ExtractableSpecTypes)
    |> refute_issues()
  end

  test "it should report extractable Plug.Conn.t() type" do
    """
    defmodule MyController do
      @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
      def show(conn, _params), do: conn
    end
    """
    |> to_source_file()
    |> run_check(ExtractableSpecTypes)
    |> assert_issues(fn issues ->
      assert length(issues) == 2
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &String.contains?(&1, "Plug.Conn.t()"))
      assert Enum.any?(messages, &String.contains?(&1, "map()"))
    end)
  end

  test "it should report extractable map() type" do
    """
    defmodule MyController do
      @type conn :: Plug.Conn.t()

      @spec show(conn(), map()) :: conn()
      def show(conn, _params), do: conn
    end
    """
    |> to_source_file()
    |> run_check(ExtractableSpecTypes)
    |> assert_issue(fn issue ->
      assert issue.message =~
               "Extract common type 'map()' to semantic alias: '@type params :: map()'"
    end)
  end

  test "it should report extractable String.t() type" do
    """
    defmodule MyModule do
      @spec process_text(String.t()) :: String.t()
      def process_text(text), do: text
    end
    """
    |> to_source_file()
    |> run_check(ExtractableSpecTypes)
    |> assert_issue(fn issue ->
      assert issue.message =~
               "Extract common type 'String.t()' to semantic alias: '@type text :: String.t()'"
    end)
  end

  test "it should suggest appropriate type names for common types" do
    """
    defmodule MyModule do
      @spec process(keyword(), integer(), Phoenix.LiveView.Socket.t()) :: atom()
      def process(_opts, _count, _socket), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ExtractableSpecTypes)
    |> assert_issues(fn issues ->
      assert length(issues) == 4
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &String.contains?(&1, "@type opts :: keyword()"))
      assert Enum.any?(messages, &String.contains?(&1, "@type count :: integer()"))

      assert Enum.any?(
               messages,
               &String.contains?(&1, "@type socket :: Phoenix.LiveView.Socket.t()")
             )

      assert Enum.any?(messages, &String.contains?(&1, "@type status :: atom()"))
    end)
  end

  test "it should handle custom module types" do
    """
    defmodule MyModule do
      @spec process(MyApp.User.t(), MyApp.Company.t()) :: :ok
      def process(_user, _company), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ExtractableSpecTypes)
    |> assert_issues(fn issues ->
      assert length(issues) == 2
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &String.contains?(&1, "@type user :: MyApp.User.t()"))
      assert Enum.any?(messages, &String.contains?(&1, "@type company :: MyApp.Company.t()"))
    end)
  end

  test "it should NOT suggest extraction for types that don't match common patterns" do
    """
    defmodule MyModule do
      @spec process(pos_integer(), non_neg_integer()) :: boolean()
      def process(_a, _b), do: true
    end
    """
    |> to_source_file()
    |> run_check(ExtractableSpecTypes)
    |> refute_issues()
  end

  test "it should handle Ecto.Changeset.t() type" do
    """
    defmodule MyModule do
      @spec validate(Ecto.Changeset.t()) :: Ecto.Changeset.t()
      def validate(changeset), do: changeset
    end
    """
    |> to_source_file()
    |> run_check(ExtractableSpecTypes)
    |> assert_issue(fn issue ->
      assert issue.message =~
               "Extract common type 'Ecto.Changeset.t()' to semantic alias: '@type changeset :: Ecto.Changeset.t()'"
    end)
  end

  test "it should handle multiple extractable types in same spec" do
    """
    defmodule MyController do
      @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
      def create(conn, params), do: conn

      @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
      def update(conn, params), do: conn
    end
    """
    |> to_source_file()
    |> run_check(ExtractableSpecTypes)
    |> assert_issues(fn issues ->
      assert length(issues) == 2
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &String.contains?(&1, "Plug.Conn.t()"))
      assert Enum.any?(messages, &String.contains?(&1, "map()"))
    end)
  end

  test "it should NOT report when type is already defined with suggested name" do
    """
    defmodule MyController do
      @type conn :: Plug.Conn.t()

      @spec show(Plug.Conn.t()) :: Plug.Conn.t()
      def show(conn), do: conn
    end
    """
    |> to_source_file()
    |> run_check(ExtractableSpecTypes)
    |> refute_issues()
  end

  test "it should handle complex nested types" do
    """
    defmodule MyModule do
      @spec process(list(), tuple()) :: {:ok, binary()} | {:error, atom()}
      def process(_list, _tuple), do: {:ok, "result"}
    end
    """
    |> to_source_file()
    |> run_check(ExtractableSpecTypes)
    |> assert_issues(fn issues ->
      assert length(issues) == 4
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &String.contains?(&1, "list()"))
      assert Enum.any?(messages, &String.contains?(&1, "tuple()"))
      assert Enum.any?(messages, &String.contains?(&1, "binary()"))
      assert Enum.any?(messages, &String.contains?(&1, "atom()"))
    end)
  end

  test "it should handle modules without specs" do
    """
    defmodule MyModule do
      def simple_function, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ExtractableSpecTypes)
    |> refute_issues()
  end

  describe "false-positive regressions" do
    test "does not crash on or report __MODULE__.t() and Erlang module types" do
      """
      defmodule MyModule do
        @spec first(__MODULE__.t()) :: __MODULE__.Nested.t()
        def first(value), do: value

        @spec table(:ets.t()) :: :ok
        def table(_table), do: :ok
      end
      """
      |> to_source_file()
      |> run_check(ExtractableSpecTypes)
      |> refute_issues()
    end

    test "does not ask to extract a type the module already aliases under another name" do
      """
      defmodule MyModule do
        @type attrs :: map()

        @spec create(attrs()) :: :ok
        def create(_attrs), do: :ok

        @spec update(map()) :: :ok
        def update(_attrs), do: :ok
      end
      """
      |> to_source_file()
      |> run_check(ExtractableSpecTypes)
      |> refute_issues()
    end

    test "sees types defined outside the conditional that holds the specs" do
      """
      defmodule MyModule do
        @type params :: map()

        if Mix.env() == :test do
          @spec run(map()) :: :ok
          def run(_params), do: :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(ExtractableSpecTypes)
      |> refute_issues()
    end

    test "checks nested modules on their own" do
      """
      defmodule Outer do
        @type params :: map()

        defmodule Inner do
          @spec run(map()) :: :ok
          def run(_params), do: :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(ExtractableSpecTypes)
      |> assert_issue(&(&1.message =~ "Extract common type 'map()'"))
    end
  end

  test "suggested aliases for built-in types compile instead of redefining built-ins" do
    fixtures = [
      {"list()", BuiltinListAliasFixture},
      {"tuple()", BuiltinTupleAliasFixture},
      {"pid()", BuiltinPidAliasFixture},
      {"reference()", BuiltinReferenceAliasFixture},
      {"binary()", BuiltinBinaryAliasFixture},
      {"MyApp.Map.t()", RemoteMapAliasFixture},
      {"MyApp.Keyword.t()", RemoteKeywordAliasFixture},
      {"MyApp.Timeout.t()", RemoteTimeoutAliasFixture}
    ]

    for {type, fixture} <- fixtures do
      [issue] =
        """
        defmodule Example do
          @spec echo(#{type}) :: #{type}
          def echo(value), do: value
        end
        """
        |> to_source_file()
        |> run_check(ExtractableSpecTypes)

      [_first, declaration] = Regex.run(~r/'(@type[^']+)'$/, issue.message)

      try do
        assert [{^fixture, _binary}] =
                 Code.compile_string("defmodule #{inspect(fixture)} do\n#{declaration}\nend")
      after
        :code.purge(fixture)
        :code.delete(fixture)
      end
    end
  end
end
