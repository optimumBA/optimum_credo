defmodule OptimumCredo.Check.Warning.DescribeWithoutErrorCaseTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.DescribeWithoutErrorCase

  @file_name "test/my_app/accounts_test.exs"

  defp run(code, params \\ [], file \\ @file_name) do
    code
    |> to_source_file(file)
    |> run_check(DescribeWithoutErrorCase, params)
  end

  test "reports a describe with only happy paths" do
    """
    defmodule AccountsTest do
      describe "get_user/1" do
        test "returns the user", do: assert(get_user(1))
        test "returns the name", do: assert(get_user(1).name)
      end
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 2 end)
  end

  test "accepts sad path hinted by name, atom, status, or raise" do
    """
    defmodule AccountsTest do
      describe "a/1" do
        test "works", do: assert(true)
        test "returns an error for blanks", do: assert(true)
      end
      describe "b/1" do
        test "works", do: assert(true)
        test "other", do: assert {:error, _} = b(nil)
      end
      describe "c/1" do
        test "works", do: assert(true)
        test "other", do: assert json_response(conn, 404)
      end
      describe "d/1" do
        test "works", do: assert(true)
        test "other", do: assert_raise(ArgumentError, fn -> d(1) end)
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "skips small describes and honours min_tests" do
    code = """
    defmodule AccountsTest do
      describe "a/1" do
        test "works", do: assert(true)
      end
    end
    """

    code
    |> run()
    |> refute_issues()

    code
    |> run(min_tests: 1)
    |> assert_issue()
  end

  test "error_words and error_atoms are configurable" do
    code = """
    defmodule AccountsTest do
      describe "a/1" do
        test "works", do: assert(true)
        test "is blocked", do: assert(true)
      end
    end
    """

    code
    |> run()
    |> assert_issue()

    code
    |> run(error_words: ["blocked"])
    |> refute_issues()
  end

  test "ignores error text in strings or quotes and non-test files" do
    code = """
    defmodule AccountsTest do
      describe "a/1" do
        test "works", do: assert("error" == "error")
        test "also", do: quote(do: {:error, 1})
      end
    end
    """

    code
    |> run()
    |> assert_issue()

    code
    |> run([], "lib/a.ex")
    |> refute_issues()

    code
    |> run([], "test/support/a_test.exs")
    |> refute_issues()
  end

  test "an unrelated 4xx/5xx integer is not a status literal" do
    """
    defmodule AccountsTest do
      describe "charge/1" do
        test "bills 500 cents", do: assert(charge(500) == :billed)
        test "bills 404 cents", do: assert(charge(404) == :billed)
      end
    end
    """
    |> run()
    |> assert_issue()
  end

  test "statuses in status positions are sad paths" do
    for sad <- [
          "assert json_response(conn, 404)",
          "assert_error_sent 500, fn -> get(conn, \"/\") end",
          "assert conn.status == 403",
          "assert %{status: 422} = conn"
        ] do
      """
      defmodule AccountsTest do
        describe "show/1" do
          test "returns the user", do: assert(get_user(1))
          test "other" do
            #{sad}
          end
        end
      end
      """
      |> run()
      |> refute_issues()
    end
  end

  test "helper calls, variables and attributes named after errors count" do
    for sad <- ["assert_forbidden(conn)", "errors_on(changeset)", "create(@invalid_attrs)"] do
      """
      defmodule AccountsTest do
        describe "create/1" do
          test "creates", do: assert(create(%{}))
          test "other" do
            #{sad}
          end
        end
      end
      """
      |> run()
      |> refute_issues()
    end
  end

  test "describe shorter than min_tests and non-literal describe names" do
    """
    defmodule AccountsTest do
      describe "one/1" do
        test "a", do: assert(true)
      end
      describe "two/1" do
        test "a", do: assert(true)
        test "b", do: assert(true)
      end
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)
  end

  test "absence wording in a test name is a sad path" do
    """
    defmodule AccountsTest do
      describe "get_user/1" do
        test "returns the user", do: assert get_user(1)
        test "returns nil for non-existent id", do: refute get_user(0)
      end
      describe "get_token/1" do
        test "returns the token", do: assert get_token(1)
        test "does not exist for an expired token", do: refute get_token(0)
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "substrings of notifications, notes, existing and does-broadcast are not sad paths" do
    """
    defmodule PostsTest do
      describe "notify/1" do
        test "returns the notes", do: assert(notes())
        test "does broadcast the post", do: assert(broadcast())
      end
      describe "tags/1" do
        test "keeps existing tags", do: assert(tags())
        test "lists notifications", do: assert(notifications())
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "identifiers are matched by whole word too" do
    """
    defmodule PostsTest do
      describe "a/1" do
        test "works", do: assert(notification_count() == 1)
        test "also works", do: assert(existing_user())
      end
    end
    """
    |> run()
    |> assert_issue()
  end

  test "genuine phrases, plurals and the bare word not are sad paths" do
    """
    defmodule PostsTest do
      describe "a/1" do
        test "works", do: assert(true)
        test "Not Found for a stranger", do: assert(true)
      end
      describe "b/1" do
        test "works", do: assert(true)
        test "redirects if user is not authenticated", do: assert(true)
      end
      describe "c/1" do
        test "works", do: assert(true)
        test "rejects bad input", do: assert(true)
      end
      describe "d/1" do
        test "works", do: assert(true)
        test "doesn't exist anywhere", do: assert(true)
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "custom error_words are strings matched as whole words" do
    code = """
    defmodule PostsTest do
      describe "a/1" do
        test "works", do: assert(true)
        test "has a glitch", do: assert(true)
      end
    end
    """

    code
    |> run(error_words: ["glitch"])
    |> refute_issues()

    code
    |> run(error_words: ["glit"])
    |> assert_issue()
  end

  test "a justified describe boundary applies only to that group" do
    ~S"""
    defmodule ExampleTest do
      describe "total formatter" do
        @describetag error_path_exemption: "Formatting is total; absent values use defaults."
        test "formats a value", do: assert(format(1))
        test "formats another", do: assert(format(2))
      end
      describe "save/1" do
        test "saves a value", do: assert(save(1))
        test "saves another", do: assert(save(2))
      end
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 7 end)
  end

  test "blank, boolean, module and test-level reasons do not exempt a describe" do
    for reason <- [~s("   "), "true", "nil"] do
      """
      defmodule ExampleTest do
        @moduletag error_path_exemption: "Not scoped to a describe."
        describe "save/1" do
          @describetag error_path_exemption: #{reason}
          test "saves a value" do
            @describetag error_path_exemption: "Not at describe level."
            assert(save(1))
          end
          test "saves another", do: assert(save(2))
        end
      end
      """
      |> run()
      |> assert_issue()
    end
  end
end
