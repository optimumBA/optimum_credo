defmodule OptimumCredo.Check.Warning.TestWithoutAssertionTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.TestWithoutAssertion

  @file_name "test/my_app/thing_test.exs"

  defp run(code, params \\ [], file \\ @file_name) do
    code
    |> to_source_file(file)
    |> run_check(TestWithoutAssertion, params)
  end

  test "reports empty and assertion-free tests" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "empty" do
      end
      test "creates", %{conn: conn} do
        Accounts.create_user(conn)
      end
    end
    """
    |> run()
    |> assert_issues(fn issues ->
      assert length(issues) == 2
      assert Enum.any?(issues, &(&1.message =~ "creates"))
    end)
  end

  test "accepts assert, refute, assert_* and raise/catch forms" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a", do: assert(1 == 1)
      test "b", do: refute(false)
      test "c" do
        assert_receive {:done, _}
      end
      test "d" do
        assert_raise ArgumentError, fn -> raise ArgumentError end
      end
      test "e" do
        catch_error(raise "x")
      end
      test "f" do
        ExUnit.Assertions.assert(true)
        Helpers.assert_ok(1)
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "assertions in for/Enum.each count" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        for x <- [1, 2], do: assert(x > 0)
        Enum.each([1], fn x -> assert x end)
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "assertions inside quote or strings do not count; setup assertions do not count" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      describe "x/1" do
        setup do
          assert true
          :ok
        end
        test "quoted" do
          quote do
            assert 1 == 1
          end
          "assert 1 == 1"
        end
      end
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.message =~ "quoted" end)
  end

  test "pending tests without a body and variables named assert-like are not tests" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "pending"
      test "vars" do
        assertions = 1
        assertions
      end
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.message =~ "vars" end)
  end

  test "assertion_helpers accept custom helpers" do
    code = """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        verify_user(1)
      end
    end
    """

    code
    |> run()
    |> assert_issue()

    code
    |> run(assertion_helpers: [:verify_user])
    |> refute_issues()
  end

  test "treat_bang_call_as_assertion" do
    code = """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        Accounts.create_user!(%{})
      end
    end
    """

    code
    |> run()
    |> assert_issue()

    code
    |> run(treat_bang_call_as_assertion: true)
    |> refute_issues()
  end

  test "ignores non-test files" do
    """
    defmodule Thing do
      def test(a, do: b), do: b
      def x, do: test("a", do: 1)
    end
    """
    |> run([], "lib/thing.ex")
    |> refute_issues()
  end

  test "a helper only exempts a test whose whole body is a single call to it" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "single" do
        verify_user(1)
      end
      test "piped" do
        1 |> build() |> verify_user()
      end
      test "among other statements" do
        user = build()
        verify_user(user)
      end
      test "assigned" do
        result = verify_user(1)
      end
    end
    """
    |> run(assertion_helpers: [:verify_user])
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [9, 13] end)
  end

  test "qualified helpers match the resolved receiver" do
    code = """
    defmodule ThingTest do
      use ExUnit.Case
      alias MyApp.Checks, as: C
      alias Other.Checks, as: D
      test "a", do: C.verify(1)
      test "b", do: D.verify(1)
      test "c", do: Checks.verify(1)
    end
    """

    code
    |> run(assertion_helpers: ["MyApp.Checks.verify"])
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [6, 7] end)

    code
    |> run(assertion_helpers: [{MyApp.Checks, :verify}])
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "on_exit, flunk, Mox expectations and verify! count as assertions" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        on_exit(fn -> :ok end)
      end
      test "b", do: flunk("no")
      test "c" do
        Mox.expect(MyMock, :call, fn -> :ok end)
        run()
      end
      test "d" do
        run()
        Mox.verify!()
      end
    end
    """
    |> run()
    |> refute_issues()

    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        expect(MyMock, :call, fn -> :ok end)
        run()
      end
    end
    """
    |> run(treat_mock_expectations_as_assertions: false)
    |> assert_issue()
  end

  test "negation and comparison operators are not bang calls" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        !ready?()
        1 != 2
        not false
      end
    end
    """
    |> run(treat_bang_call_as_assertion: true)
    |> assert_issue()
  end

  test "tests with interpolated or variable names are still checked" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      for n <- [1, 2] do
        test "case \#{n}" do
          run(unquote(n))
        end
      end
      test @name do
        run()
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "refutable pattern matches can fail and count; bare variables do not" do
    code = """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        {:error, _} = Accounts.create_user(%{})
      end
      test "b" do
        user = Accounts.create_user(%{})
      end
      test "c" do
        _ = Accounts.create_user(%{})
      end
      test "d" do
        %{id: _} = Accounts.create_user(%{})
      end
    end
    """

    code
    |> run()
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [6, 9] end)

    code
    |> run(treat_match_as_assertion: false)
    |> assert_issues(fn issues -> assert length(issues) == 4 end)
  end

  test "nil assertion-helper modules match a helper in any module" do
    source = """
    defmodule ThingTest do
      use ExUnit.Case
      test "checks a user" do
        MyApp.Checks.verify_user(1)
      end
    end
    """

    source
    |> run(assertion_helpers: [{nil, :verify_user}])
    |> refute_issues()

    source
    |> run(assertion_helpers: [{Other.Checks, :verify_user}])
    |> assert_issue()
  end
end
