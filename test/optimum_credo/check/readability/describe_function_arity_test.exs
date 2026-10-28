defmodule OptimumCredo.Check.Readability.DescribeFunctionArityTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.DescribeFunctionArity

  defp run(code, file, params \\ []) do
    code
    |> to_source_file(file)
    |> run_check(DescribeFunctionArity, params)
  end

  @unit "test/my_app/accounts_test.exs"

  test "reports unit describes that are not function/arity" do
    """
    defmodule AccountsTest do
      use ExUnit.Case
      describe "registering a user" do
      end
      describe "register_user" do
      end
    end
    """
    |> run(@unit)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "accepts function/arity including ? and ! names" do
    """
    defmodule AccountsTest do
      use ExUnit.Case
      describe "register_user/1" do
      end
      describe "valid?/2" do
      end
      describe "get!/1" do
      end
    end
    """
    |> run(@unit)
    |> refute_issues()
  end

  test "route form is accepted in web tests but not in unit tests" do
    code = """
    defmodule FooLiveTest do
      use ExUnit.Case
      describe "/register" do
      end
    end
    """

    code
    |> run("test/my_app_web/live/foo_live_test.exs")
    |> refute_issues()

    code
    |> run(@unit)
    |> assert_issue()
  end

  test "web tests still report free-form describes" do
    """
    defmodule FooLiveTest do
      use ExUnit.Case
      describe "when signed in" do
      end
    end
    """
    |> run("test/my_app_web/live/foo_live_test.exs")
    |> assert_issue(fn issue -> assert issue.message =~ "route" end)
  end

  test "skips support, features, integration and non-test files" do
    code = """
    defmodule XTest do
      describe "anything goes" do
      end
    end
    """

    for file <- [
          "test/support/x_test.exs",
          "test/features/x_test.exs",
          "test/integration/x_test.exs",
          "lib/x.ex"
        ] do
      code
      |> run(file)
      |> refute_issues()
    end
  end

  test "ignores interpolated names and strings that look like describes" do
    """
    defmodule AccountsTest do
      use ExUnit.Case
      @name "describe"
      for n <- [1] do
        describe "run \#{n}/1" do
        end
      end
      def x, do: "describe \\"free form\\""
    end
    """
    |> run(@unit)
    |> refute_issues()
  end

  test "allowed_patterns and unit_paths params" do
    code = """
    defmodule AccountsTest do
      describe "when admin" do
      end
    end
    """

    code
    |> run(@unit)
    |> assert_issue()

    code
    |> run(@unit, allowed_patterns: ["^when "])
    |> refute_issues()

    code
    |> run(@unit, unit_paths: ["test/other/"])
    |> refute_issues()

    code
    |> run(@unit, unit_paths: ["test/my_app/"])
    |> assert_issue()
  end

  test "web tests accept an HTTP verb before the route" do
    code = """
    defmodule PageControllerTest do
      describe "GET /users" do
        test "works", do: :ok
      end
      describe "POST /users/:id" do
        test "works", do: :ok
      end
      describe "index/2" do
        test "works", do: :ok
      end
      describe "loose words" do
        test "works", do: :ok
      end
    end
    """

    code
    |> run("test/my_app_web/controllers/page_controller_test.exs")
    |> assert_issue(fn issue -> assert issue.line_no == 11 end)

    code
    |> run(@unit)
    |> assert_issues(fn issues -> assert length(issues) == 3 end)
  end

  test "custom patterns may be Regex values" do
    """
    defmodule AccountsTest do
      describe "when admin" do
        test "works", do: :ok
      end
    end
    """
    |> run(@unit, allowed_patterns: [~r/^when /])
    |> refute_issues()
  end

  test "non-literal describe names and quoted describes are ignored" do
    """
    defmodule AccountsTest do
      describe @name do
        test "works", do: :ok
      end
      describe "x \#{y}" do
        test "works", do: :ok
      end
      defmacro shared do
        quote do
          describe "loose" do
            test "works", do: :ok
          end
        end
      end
    end
    """
    |> run(@unit)
    |> refute_issues()
  end

  test "function/arity may carry a qualifier and on_mount hooks are accepted" do
    """
    defmodule MyApp.UserAuthTest do
      describe "parse/2 with blanks", do: :ok
      describe "on_mount :ensure_authenticated", do: :ok
      describe "parse with blanks", do: :ok
      describe "on_mount", do: :ok
    end
    """
    |> run(@unit)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [4, 5]
    end)
  end
end
