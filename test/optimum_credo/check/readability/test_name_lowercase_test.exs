defmodule OptimumCredo.Check.Readability.TestNameLowercaseTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.TestNameLowercase

  @file_name "test/my_app/accounts_test.exs"

  defp run(code, params \\ [], file \\ @file_name) do
    code
    |> to_source_file(file)
    |> run_check(TestNameLowercase, params)
  end

  test "reports uppercase test and describe names" do
    """
    defmodule AccountsTest do
      describe "Registering" do
        test "Returns an error" do
        end
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "accepts lowercase, backtick, digit, slash starts and interpolation starts" do
    """
    defmodule AccountsTest do
      describe "register_user/1" do
        test "returns an error", do: :ok
        test "`Accounts.get/1` returns a user", do: :ok
        test "404 for missing", do: :ok
        test "\#{@prefix} works", do: :ok
      end
      describe "/Register" do
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "acronyms are accepted by default and flaggable via allow_acronyms" do
    code = """
    defmodule AccountsTest do
      test "API returns json", do: :ok
      test "A user can log in", do: :ok
    end
    """

    code
    |> run()
    |> assert_issue(fn issue -> assert issue.message =~ "A user" end)

    code
    |> run(allow_acronyms: false)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "allowed_prefixes and path scoping" do
    code = """
    defmodule AccountsTest do
      test "OAuth flow", do: :ok
    end
    """

    code
    |> run()
    |> assert_issue()

    code
    |> run(allowed_prefixes: ["OAuth"])
    |> refute_issues()

    code
    |> run([], "test/support/helper_test.exs")
    |> refute_issues()

    code
    |> run([], "lib/accounts.ex")
    |> refute_issues()
  end

  test "strings mentioning test do not matter" do
    """
    defmodule Helper do
      def a, do: ~s(test "Upper")
    end
    """
    |> run()
    |> refute_issues()
  end

  test "qualified function references and leading whitespace" do
    """
    defmodule AccountsTest do
      describe "Accounts.create_user/1" do
        test "Accounts.create_user/1 works", do: :ok
        test "  Loud start", do: :ok
      end
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 4 end)
  end

  test "names in macro-generated tests and tests without a literal start" do
    """
    defmodule AccountsTest do
      for kind <- [:a] do
        test "Bad \#{kind}", do: :ok
        test "\#{kind} Fine", do: :ok
      end
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "ignores quoted test definitions" do
    """
    defmodule AccountsTest do
      defmacro shared do
        quote do
          test "Bad name", do: :ok
        end
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "a leading CamelCase identifier is accepted, a capitalised word is not" do
    code = """
    defmodule AccountsTest do
      test "PubSub partials stay raw", do: :ok
      describe "WebSocket connection" do
        test "Javascript is not executed", do: :ok
      end
    end
    """

    code
    |> run()
    |> assert_issue(fn issue -> assert issue.message =~ "Javascript" end)

    code
    |> run(allow_camel_case: false)
    |> assert_issues(fn issues -> assert length(issues) == 3 end)

    code
    |> run(allowed_prefixes: ["Javascript"])
    |> refute_issues()
  end
end
