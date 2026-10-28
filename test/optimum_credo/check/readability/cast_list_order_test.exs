defmodule OptimumCredo.Check.Readability.CastListOrderTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.CastListOrder

  test "reports unsorted cast and validate_required lists, direct and piped" do
    """
    defmodule User do
      import Ecto.Changeset

      def changeset(user, attrs) do
        user
        |> cast(attrs, [:name, :email, :age])
        |> validate_required([:name, :email, :age])
      end
    end
    """
    |> to_source_file()
    |> run_check(CastListOrder)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [6, 7]
      assert hd(issues).message =~ "email before name"
    end)
  end

  test "reports remote Changeset calls and string lists" do
    """
    defmodule User do
      def a(user, attrs), do: Ecto.Changeset.cast(user, attrs, [:b, :a, :c])
      def b(user, attrs), do: Changeset.validate_required(user, ["b", "a", "c"])
    end
    """
    |> to_source_file()
    |> run_check(CastListOrder)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "accepts sorted, short, variable, mixed and keyword lists" do
    """
    defmodule User do
      import Ecto.Changeset

      def changeset(user, attrs) do
        user
        |> cast(attrs, [:age, :email, :name])
        |> cast(attrs, [:z, :a])
        |> cast(attrs, @fields)
        |> cast(attrs, [:b, "a", :c])
        |> cast(attrs, [:a, :b, :c], empty_values: [:z, :y, :x])
        |> validate_required([:email, :name, :zip])
      end
    end
    """
    |> to_source_file()
    |> run_check(CastListOrder)
    |> refute_issues()
  end

  test "ignores other functions, other remote modules, strings and quoted code" do
    ~S'''
    defmodule User do
      import Ecto.Changeset

      def run do
        put_change(cs, :names, [:c, :b, :a])
        Ecto.Type.cast([:c, :b, :a], 1)
        "cast(attrs, [:c, :b, :a])"
      end
    end
    '''
    |> to_source_file()
    |> run_check(CastListOrder)
    |> refute_issues()
  end

  test "functions and min_run parameters" do
    source = """
    defmodule User do
      import Ecto.Changeset

      def a(cs), do: validate_length(cs, [:b, :a])
    end
    """

    source
    |> to_source_file()
    |> run_check(CastListOrder)
    |> refute_issues()

    source
    |> to_source_file()
    |> run_check(CastListOrder, functions: [:validate_length], min_run: 2)
    |> assert_issue()
  end

  test "unqualified calls need an Ecto.Changeset import by default" do
    source = """
    defmodule Parser do
      def run(input), do: cast(input, %{}, [:b, :a, :c])
    end
    """

    source
    |> to_source_file()
    |> run_check(CastListOrder)
    |> refute_issues()

    source
    |> to_source_file()
    |> run_check(CastListOrder, local_calls: :always)
    |> assert_issue()
  end

  test "an import with options, or a configured use, brings local calls into scope" do
    imported = """
    defmodule User do
      import Ecto.Changeset, only: [cast: 3]

      def run(user), do: cast(user, %{}, [:b, :a, :c])
    end
    """

    used = """
    defmodule User do
      use MyApp.Schema

      def run(user), do: cast(user, %{}, [:b, :a, :c])
    end
    """

    imported
    |> to_source_file()
    |> run_check(CastListOrder)
    |> assert_issue()

    used
    |> to_source_file()
    |> run_check(CastListOrder)
    |> refute_issues()

    used
    |> to_source_file()
    |> run_check(CastListOrder, changeset_imports: ["MyApp.Schema"])
    |> assert_issue()
  end

  test "importing another module does not enable local calls, local_calls: :never disables them" do
    """
    defmodule User do
      import Ecto.Query

      def run(user), do: cast(user, %{}, [:b, :a, :c])
    end
    """
    |> to_source_file()
    |> run_check(CastListOrder)
    |> refute_issues()

    """
    defmodule User do
      import Ecto.Changeset

      def run(user), do: [cast(user, %{}, [:b, :a, :c]), Ecto.Changeset.cast(user, %{}, [:b, :a, :c])]
    end
    """
    |> to_source_file()
    |> run_check(CastListOrder, local_calls: :never)
    |> assert_issue(fn issue -> assert issue.line_no == 4 end)
  end

  test "a remote call of another library's Changeset-less module is ignored regardless of scope" do
    """
    defmodule User do
      def run(user), do: Parser.cast(user, %{}, [:b, :a, :c])
    end
    """
    |> to_source_file()
    |> run_check(CastListOrder, local_calls: :always)
    |> refute_issues()
  end

  test "an invalid local_calls value raises" do
    assert_raise ArgumentError, ~r/invalid local_calls/, fn ->
      "defmodule A do\nend"
      |> to_source_file()
      |> CastListOrder.run(local_calls: :sometimes)
    end
  end

  test "reports the line of the call for multi-line piped lists" do
    """
    defmodule User do
      import Ecto.Changeset

      def changeset(user, attrs) do
        user
        |> cast(attrs, [
          :name,
          :email,
          :age
        ])
      end
    end
    """
    |> to_source_file()
    |> run_check(CastListOrder)
    |> assert_issue(fn issue -> assert issue.line_no == 6 end)
  end
end
