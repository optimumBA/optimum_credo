defmodule OptimumCredo.Check.Readability.ModuleOrganizationTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.ModuleOrganization

  test "it should NOT report properly organized module with blank lines" do
    """
    defmodule MyModule do
      use Supervisor
      
      import Telemetry.Metrics
      
      alias MyApp.SomeModule
      
      require Logger
      
      def start_link, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ModuleOrganization)
    |> refute_issues()
  end

  test "it should report missing blank line between use and import" do
    """
    defmodule MyModule do
      use Supervisor
      import Telemetry.Metrics
      
      alias MyApp.SomeModule
    end
    """
    |> to_source_file()
    |> run_check(ModuleOrganization)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Missing blank line between use and import statements"
    end)
  end

  test "it should report missing blank line between import and alias" do
    """
    defmodule MyModule do
      use Supervisor
      
      import Telemetry.Metrics
      alias MyApp.SomeModule
    end
    """
    |> to_source_file()
    |> run_check(ModuleOrganization)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Missing blank line between import and alias statements"
    end)
  end

  test "it should report missing blank line between alias and require" do
    """
    defmodule MyModule do
      use Supervisor
      
      import Telemetry.Metrics
      
      alias MyApp.SomeModule
      require Logger
    end
    """
    |> to_source_file()
    |> run_check(ModuleOrganization)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Missing blank line between alias and require statements"
    end)
  end

  test "it should report multiple missing blank lines" do
    """
    defmodule MyModule do
      use Supervisor
      use GenServer
      import Telemetry.Metrics
      alias MyApp.SomeModule
      require Logger
    end
    """
    |> to_source_file()
    |> run_check(ModuleOrganization)
    |> assert_issues(fn issues ->
      messages = Enum.map(issues, & &1.message)
      assert "Missing blank line between use and import statements" in messages
      assert "Missing blank line between import and alias statements" in messages
      assert "Missing blank line between alias and require statements" in messages
    end)
  end

  test "it should NOT report issues for modules with only one statement type" do
    """
    defmodule MyModule do
      use Supervisor
      use GenServer
      
      def start_link, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(ModuleOrganization)
    |> refute_issues()
  end

  test "it should NOT report issues for modules with non-consecutive statement types" do
    """
    defmodule MyModule do
      use Supervisor
      
      @moduledoc "Some doc"
      
      import Telemetry.Metrics
      
      def start_link, do: :ok
      
      alias MyApp.SomeModule
    end
    """
    |> to_source_file()
    |> run_check(ModuleOrganization)
    |> refute_issues()
  end

  test "it should handle modules with single statement blocks" do
    """
    defmodule MyModule do
      use Supervisor
    end
    """
    |> to_source_file()
    |> run_check(ModuleOrganization)
    |> refute_issues()
  end
end
