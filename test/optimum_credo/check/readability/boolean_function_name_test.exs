defmodule OptimumCredo.Check.Readability.BooleanFunctionNameTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.BooleanFunctionName

  defp run(source, params \\ []) do
    source
    |> to_source_file()
    |> run_check(BooleanFunctionName, params)
  end

  test "reports literal booleans, comparisons, negation and guards" do
    """
    defmodule Demo do
      def active(_user), do: true
      def admin(user), do: user.role == :admin
      defp empty(list), do: not Enum.any?(list)
      def missing(value), do: is_nil(value)
      def listed(item, list), do: item in list
      def both(a, b), do: a > 1 and b < 2
    end
    """
    |> run()
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [2, 3, 4, 5, 6, 7]
      assert hd(issues).message =~ "active"
    end)
  end

  test "reports multi-clause functions only when every clause is boolean" do
    source = """
    defmodule Demo do
      def allowed(:admin), do: true
      def allowed(_role), do: false

      def mixed(:a), do: true
      def mixed(:b), do: :maybe
    end
    """

    source
    |> run()
    |> assert_issue(fn issue ->
      assert issue.line_no == 2
      assert issue.message =~ "allowed"
    end)
  end

  test "reports boolean branches of if, case and cond with a final expression" do
    """
    defmodule Demo do
      def a(x) do
        y = x + 1
        if y > 1, do: true, else: false
      end

      def b(x) do
        case x do
          :a -> true
          _other -> false
        end
      end

      def c(x) do
        cond do
          x > 1 -> true
          true -> false
        end
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [2, 7, 14] end)
  end

  test "does not report names with ? or !, calls, non-boolean branches or if without else" do
    ~S"""
    defmodule Demo do
      def admin?(user), do: user.role == :admin
      def check!(user), do: user.role == :admin
      def delegated(user), do: Roles.admin?(user)
      def value(x), do: x && true
      def maybe(x), do: if(x, do: true)
      def partial(x), do: if(x, do: true, else: nil)
      def either(x), do: x or other()
      def no_body(x, y \\ 1)
      def result(_x), do: :ok
      defmacro macro_check(x), do: x == 1
    end
    """
    |> run()
    |> refute_issues()
  end

  test "skips @impl callbacks and ignore_functions" do
    source = """
    defmodule Demo do
      @impl true
      def handle_call(:ping, _from, state), do: state == 1

      def legacy_flag(x), do: x == 1
    end
    """

    source
    |> run()
    |> assert_issue(fn issue -> assert issue.message =~ "legacy_flag" end)

    source
    |> run(ignore_functions: [:legacy_flag])
    |> refute_issues()
  end

  test "ignores strings and quoted code" do
    ~S'''
    defmodule Demo do
      def text, do: "def active(_user), do: true"
      defmacro build do
        quote do
          def active(_user), do: true
        end
      end
    end
    '''
    |> run()
    |> refute_issues()
  end

  test "same-named functions of different arity are judged separately" do
    """
    defmodule Demo do
      def check(a), do: a == 1
      def check(a, b), do: {a, b}
    end
    """
    |> to_source_file()
    |> run_check(BooleanFunctionName)
    |> assert_issue(fn issue ->
      assert issue.message =~ "check/1"
      assert issue.line_no == 2
    end)
  end

  test "parenless zero-arity functions are inspected" do
    "defmodule Demo do\n  def enabled, do: false\nend"
    |> to_source_file()
    |> run_check(BooleanFunctionName)
    |> assert_issue(fn issue -> assert issue.message =~ "enabled/0" end)
  end

  test "a clause that returns nil is not ignored" do
    """
    defmodule Demo do
      def active(1), do: true
      def active(_other), do: nil
    end
    """
    |> to_source_file()
    |> run_check(BooleanFunctionName)
    |> refute_issues()
  end

  test "rescue, catch and after blocks make a clause non-boolean" do
    """
    defmodule Demo do
      def ready(x) do
        x == 1
      rescue
        _ -> :error
      end

      def done(x) do
        x == 1
      after
        :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(BooleanFunctionName)
    |> refute_issues()
  end

  test "bodiless heads with default arguments do not hide a boolean body" do
    """
    defmodule Demo do
      def admin(user, strict \\\\ false)
      def admin(user, _strict), do: user.role == :admin
    end
    """
    |> to_source_file()
    |> run_check(BooleanFunctionName)
    |> assert_issue(fn issue -> assert issue.message =~ "admin/2" end)
  end
end
