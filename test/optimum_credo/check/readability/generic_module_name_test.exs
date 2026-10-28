defmodule OptimumCredo.Check.Readability.GenericModuleNameTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.GenericModuleName

  test "reports default generic last segments" do
    for name <- ~w(Helpers Helper Utils Util Utilities Misc Common Stuff) do
      "defmodule MyApp.Billing.#{name} do\nend"
      |> to_source_file()
      |> run_check(GenericModuleName)
      |> assert_issue(fn issue -> assert issue.message =~ "MyApp.Billing.#{name}" end)
    end
  end

  test "reports a top-level generic module and nested relative modules" do
    """
    defmodule Utils do
      defmodule Helpers do
      end
    end
    """
    |> to_source_file()
    |> run_check(GenericModuleName)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [1, 2] end)
  end

  test "ignores specific names, generic words in other positions and dynamic names" do
    """
    defmodule MyApp.StringUtils do
    end

    defmodule MyApp.Utils.Invoice do
    end

    defmodule MyApp.TestHelpers do
    end

    defmodule __MODULE__.Helpers do
    end
    """
    |> to_source_file()
    |> run_check(GenericModuleName)
    |> refute_issues()
  end

  test "ignores strings and atoms that look like generic modules" do
    ~S'''
    defmodule MyApp.Invoice do
      @moduledoc "defmodule MyApp.Utils"
      def helpers, do: [:Helpers, "MyApp.Helpers"]
    end
    '''
    |> to_source_file()
    |> run_check(GenericModuleName)
    |> refute_issues()
  end

  test "banned_names replaces the default list" do
    source = "defmodule MyApp.Manager do\nend\n\ndefmodule MyApp.Utils do\nend"

    source
    |> to_source_file()
    |> run_check(GenericModuleName, banned_names: ["Manager"])
    |> assert_issue(fn issue -> assert issue.message =~ "MyApp.Manager" end)

    source
    |> to_source_file()
    |> run_check(GenericModuleName, banned_names: [:Manager, "Utils"])
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "allowed_modules accepts full names only" do
    source = "defmodule MyApp.Utils do\nend\n\ndefmodule Other.Utils do\nend"

    source
    |> to_source_file()
    |> run_check(GenericModuleName, allowed_modules: ["MyApp.Utils"])
    |> assert_issue(fn issue -> assert issue.message =~ "Other.Utils" end)
  end

  test "composes the full name of nested modules before comparing allowed_modules" do
    source = """
    defmodule MyApp.Billing do
      defmodule Helpers do
      end

      defmodule __MODULE__.Utils do
      end
    end
    """

    source
    |> to_source_file()
    |> run_check(GenericModuleName)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &(&1.message =~ "MyApp.Billing.Helpers")) == [
               true,
               false
             ]

      assert Enum.any?(issues, &(&1.message =~ "MyApp.Billing.Utils"))
    end)

    source
    |> to_source_file()
    |> run_check(GenericModuleName, allowed_modules: ["MyApp.Billing.Helpers"])
    |> assert_issue(fn issue -> assert issue.message =~ "MyApp.Billing.Utils" end)
  end

  test "accepts atoms and Elixir. prefixed allowed names and reports the module line" do
    source = "\n\ndefmodule MyApp.Helpers do\nend"

    source
    |> to_source_file()
    |> run_check(GenericModuleName, allowed_modules: [MyApp.Helpers])
    |> refute_issues()

    source
    |> to_source_file()
    |> run_check(GenericModuleName)
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "an absolute Elixir. name inside a module is not prefixed with its parent" do
    "defmodule MyApp.Billing do\n  defmodule Elixir.Other.Utils do\n  end\nend"
    |> to_source_file()
    |> run_check(GenericModuleName)
    |> assert_issue(fn issue -> assert issue.message =~ "Other.Utils is generic" end)
  end
end
