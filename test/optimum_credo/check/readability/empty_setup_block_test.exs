defmodule OptimumCredo.Check.Readability.EmptySetupBlockTest do
  use Credo.Test.Case

  alias OptimumCredo.Check.Readability.EmptySetupBlock

  test "it should report setup do :ok end in a test file" do
    """
    defmodule MyTest do
      use ExUnit.Case

      setup do
        :ok
      end

      test "something", do: assert(true)
    end
    """
    |> to_source_file("foo_test.exs")
    |> run_check(EmptySetupBlock)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Empty `setup` block"
    end)
  end

  test "it should report setup do end (parses to nil body)" do
    """
    defmodule MyTest do
      use ExUnit.Case

      setup do
      end

      test "something", do: assert(true)
    end
    """
    |> to_source_file("foo_test.exs")
    |> run_check(EmptySetupBlock)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Empty `setup` block"
    end)
  end

  test "it should report setup do {:ok, %{}} end" do
    """
    defmodule MyTest do
      use ExUnit.Case

      setup do
        {:ok, %{}}
      end

      test "something", do: assert(true)
    end
    """
    |> to_source_file("foo_test.exs")
    |> run_check(EmptySetupBlock)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Empty `setup` block"
    end)
  end

  test "it should report setup context do :ok end (with-argument variant)" do
    """
    defmodule MyTest do
      use ExUnit.Case

      setup context do
        :ok
      end

      test "something", do: assert(true)
    end
    """
    |> to_source_file("foo_test.exs")
    |> run_check(EmptySetupBlock)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Empty `setup` block"
    end)
  end

  test "it should report empty setup in test/support/ files" do
    """
    defmodule MyApp.DataCase do
      use ExUnit.CaseTemplate

      setup do
        :ok
      end
    end
    """
    |> to_source_file("test/support/data_case.ex")
    |> run_check(EmptySetupBlock)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Empty `setup` block"
    end)
  end

  test "it should NOT report setup with a real body" do
    """
    defmodule MyTest do
      use ExUnit.Case

      setup do
        user = create_user()
        %{user: user}
      end

      test "something", do: assert(true)
    end
    """
    |> to_source_file("foo_test.exs")
    |> run_check(EmptySetupBlock)
    |> refute_issues()
  end

  test "it should NOT report setup :external_function (atom shorthand)" do
    """
    defmodule MyTest do
      use ExUnit.Case

      setup :create_user

      test "something", do: assert(true)
    end
    """
    |> to_source_file("foo_test.exs")
    |> run_check(EmptySetupBlock)
    |> refute_issues()
  end

  test "it should NOT report empty setup in a non-test lib file" do
    """
    defmodule MyModule do
      def setup do
        :ok
      end
    end
    """
    |> to_source_file("lib/my_module.ex")
    |> run_check(EmptySetupBlock)
    |> refute_issues()
  end

  test "it should report the correct line number" do
    """
    defmodule MyTest do
      use ExUnit.Case

      setup do
        :ok
      end

      test "something", do: assert(true)
    end
    """
    |> to_source_file("foo_test.exs")
    |> run_check(EmptySetupBlock)
    |> assert_issue(fn issue ->
      assert issue.line_no == 4
    end)
  end
end
