defmodule OptimumCredo.Check.Warning.WebNamespaceInCoreTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.WebNamespaceInCore

  @moduletag :tmp_dir

  @core_file "lib/demo_app/drops.ex"

  test "reports a remote call into the inferred web namespace" do
    """
    defmodule DemoApp.Drops do
      def notify(payload), do: DemoAppWeb.Endpoint.broadcast("drops", "created", payload)
    end
    """
    |> to_source_file(@core_file)
    |> run_check(WebNamespaceInCore)
    |> assert_issue(fn issue ->
      assert issue.line_no == 2
      assert issue.message =~ "DemoAppWeb.Endpoint"
    end)
  end

  test "reports alias, import, and multi-alias forms" do
    """
    defmodule DemoApp.Drops do
      alias DemoAppWeb.Router.Helpers
      import DemoAppWeb.Gettext
      alias DemoAppWeb.{Endpoint, Layouts}
    end
    """
    |> to_source_file(@core_file)
    |> run_check(WebNamespaceInCore)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &(&1.message =~ "DemoAppWeb")) == [
               true,
               true,
               true,
               true
             ]

      assert Enum.map(issues, & &1.line_no) == [2, 3, 4, 4]
    end)
  end

  test "reports files directly under lib/ using the file name as the app" do
    """
    defmodule DemoApp do
      def url, do: DemoAppWeb.Endpoint.url()
    end
    """
    |> to_source_file("lib/demo_app.ex")
    |> run_check(WebNamespaceInCore)
    |> assert_issue()
  end

  test "reports in umbrella layouts" do
    """
    defmodule DemoApp.Drops do
      def url, do: DemoAppWeb.Endpoint.url()
    end
    """
    |> to_source_file("apps/demo_app/lib/demo_app/drops.ex")
    |> run_check(WebNamespaceInCore)
    |> assert_issue()
  end

  test "ignores web files, tests, priv, mix tasks and the web root module" do
    source = """
    defmodule DemoAppWeb.PageController do
      def index, do: DemoAppWeb.Endpoint.url()
    end
    """

    for filename <- [
          "lib/demo_app_web/controllers/page_controller.ex",
          "lib/demo_app_web.ex",
          "test/demo_app/drops_test.exs",
          "priv/repo/seeds.ex",
          "lib/mix/tasks/demo.ex",
          "apps/demo_app_web/lib/demo_app_web/router.ex"
        ] do
      source
      |> to_source_file(filename)
      |> run_check(WebNamespaceInCore)
      |> refute_issues()
    end
  end

  test "ignores similarly named modules, strings, atoms and non-web references" do
    """
    defmodule DemoApp.Drops do
      @moduledoc "Never call DemoAppWeb.Endpoint from here"
      def run do
        send(self(), :DemoAppWeb)
        DemoAppWebhook.deliver("DemoAppWeb.Endpoint")
        Phoenix.PubSub.broadcast(DemoApp.PubSub, "drops", :created)
      end
    end
    """
    |> to_source_file(@core_file)
    |> run_check(WebNamespaceInCore)
    |> refute_issues()
  end

  test "does not inspect quote bodies or the name of a nested web module" do
    """
    defmodule DemoApp.Drops do
      defmacro __using__(_opts) do
        quote do
          alias DemoAppWeb.Endpoint
        end
      end
    end
    """
    |> to_source_file(@core_file)
    |> run_check(WebNamespaceInCore)
    |> refute_issues()
  end

  test "allowed_modules permits a module and its children" do
    """
    defmodule DemoApp.Drops do
      def run do
        DemoAppWeb.Endpoint.broadcast("a", "b", %{})
        DemoAppWeb.Endpoint.Subscriber.join()
        DemoAppWeb.Router.url()
      end
    end
    """
    |> to_source_file(@core_file)
    |> run_check(WebNamespaceInCore, allowed_modules: ["DemoAppWeb.Endpoint"])
    |> assert_issue(fn issue -> assert issue.message =~ "DemoAppWeb.Router" end)
  end

  test "explicit web_namespace overrides inference and path scoping" do
    source = """
    defmodule Shop.Orders do
      def run, do: Storefront.Endpoint.url()
    end
    """

    source
    |> to_source_file("lib/shop/orders.ex")
    |> run_check(WebNamespaceInCore, web_namespace: "Storefront")
    |> assert_issue()

    source
    |> to_source_file("lib/storefront/orders.ex")
    |> run_check(WebNamespaceInCore, web_namespace: "Storefront")
    |> refute_issues()

    source
    |> to_source_file("lib/shop/orders.ex")
    |> run_check(WebNamespaceInCore)
    |> refute_issues()
  end

  test "multi-alias expansion honors allowed_modules for each child" do
    """
    defmodule DemoApp.Drops do
      alias DemoAppWeb.{Endpoint, Layouts}
    end
    """
    |> to_source_file(@core_file)
    |> run_check(WebNamespaceInCore, allowed_modules: ["DemoAppWeb.Endpoint"])
    |> assert_issue(fn issue ->
      assert issue.message =~ "DemoAppWeb.Layouts"
      refute issue.message =~ "Endpoint"
    end)
  end

  test "reports a use of an alias that points at a web module once, at the alias line" do
    """
    defmodule DemoApp.Drops do
      alias DemoAppWeb.Endpoint

      def run, do: Endpoint.broadcast("a", "b", %{})
    end
    """
    |> to_source_file(@core_file)
    |> run_check(WebNamespaceInCore)
    |> assert_issue(fn issue -> assert issue.line_no == 2 end)
  end

  test "resolves aliases to a parent of the web namespace and `as:` renames" do
    """
    defmodule MyOrg.DemoApp.Drops do
      alias MyOrg, as: Org
      alias MyOrg.DemoApp, as: Core

      def run do
        Org.DemoAppWeb.Endpoint.url()
        Core.Accounts.list()
      end
    end
    """
    |> to_source_file("lib/demo_app/drops.ex")
    |> run_check(WebNamespaceInCore)
    |> assert_issue(fn issue ->
      assert issue.line_no == 6
      assert issue.message =~ "MyOrg.DemoAppWeb.Endpoint"
    end)
  end

  test "infers a nested root namespace from the module name" do
    source = """
    defmodule MyOrg.DemoApp.Drops do
      def url, do: MyOrg.DemoAppWeb.Endpoint.url()
    end
    """

    source
    |> to_source_file("lib/demo_app/drops.ex")
    |> run_check(WebNamespaceInCore)
    |> assert_issue()

    source
    |> to_source_file("lib/my_org/demo_app/drops.ex")
    |> run_check(WebNamespaceInCore)
    |> assert_issue(fn issue -> assert issue.message =~ "MyOrg.DemoAppWeb.Endpoint" end)

    source
    |> to_source_file("apps/demo/lib/my_org/demo_app/drops.ex")
    |> run_check(WebNamespaceInCore)
    |> assert_issue()
  end

  test "a nested web root directory is a web file" do
    "defmodule MyOrg.DemoAppWeb.PageController do\n  def i, do: MyOrg.DemoAppWeb.Endpoint.url()\nend"
    |> to_source_file("lib/my_org/demo_app_web/controllers/page_controller.ex")
    |> run_check(WebNamespaceInCore)
    |> refute_issues()

    "defmodule MyOrg.DemoApp.Drops do\n  def i, do: MyOrg.DemoAppWeb.Endpoint.url()\nend"
    |> to_source_file("lib/my_org/demo_app/drops.ex")
    |> run_check(WebNamespaceInCore, web_namespace: "MyOrg.DemoAppWeb")
    |> assert_issue()

    "defmodule MyOrg.DemoAppWeb.Telemetry do\n  def i, do: MyOrg.DemoAppWeb.Endpoint.url()\nend"
    |> to_source_file("lib/my_org/demo_app_web/telemetry.ex")
    |> run_check(WebNamespaceInCore, web_namespace: "MyOrg.DemoAppWeb")
    |> refute_issues()
  end

  test "skips the generated OTP application module unless allow_application is false" do
    source = """
    defmodule DemoApp.Application do
      def start(_type, _args) do
        children = [DemoAppWeb.Telemetry, DemoAppWeb.Endpoint]
        Supervisor.start_link(children, strategy: :one_for_one)
      end

      def config_change(changed, _new, removed) do
        DemoAppWeb.Endpoint.config_change(changed, removed)
      end
    end
    """

    source
    |> to_source_file("lib/demo_app/application.ex")
    |> run_check(WebNamespaceInCore)
    |> refute_issues()

    source
    |> to_source_file("lib/demo_app/application.ex")
    |> run_check(WebNamespaceInCore, allow_application: false)
    |> assert_issues(fn issues -> assert length(issues) == 3 end)
  end

  test "a web module defined in a core path is not itself a core dependency" do
    "defmodule DemoAppWeb.Misplaced do\n  def i, do: DemoAppWeb.Endpoint.url()\nend"
    |> to_source_file("lib/demo_app/misplaced.ex")
    |> run_check(WebNamespaceInCore)
    |> refute_issues()
  end

  test "allowed_modules accepts atoms, Elixir. prefixes and aliases to allowed modules" do
    """
    defmodule DemoApp.Drops do
      alias DemoAppWeb.Endpoint

      def run, do: Endpoint.broadcast("a", "b", %{})
    end
    """
    |> to_source_file(@core_file)
    |> run_check(WebNamespaceInCore, allowed_modules: [DemoAppWeb.Endpoint, "Elixir.Other"])
    |> refute_issues()
  end

  test "handles Windows separators, absolute paths and a lib ancestor directory", %{tmp_dir: tmp} do
    source = "defmodule DemoApp.Drops do\n  def i, do: DemoAppWeb.Endpoint.url()\nend"

    source
    |> to_source_file("apps\\demo_app\\lib\\demo_app\\drops.ex")
    |> run_check(WebNamespaceInCore)
    |> assert_issue()

    project = Path.join([tmp, "lib", "ci", "demo"])
    File.mkdir_p!(project)

    project
    |> Path.join("mix.exs")
    |> File.write!("")

    source
    |> to_source_file(Path.join([project, "lib", "demo_app", "drops.ex"]))
    |> run_check(WebNamespaceInCore)
    |> assert_issue()
  end

  test "web_namespace accepts a list and every entry is checked" do
    "defmodule Shop.Orders do\n  def i, do: [Storefront.Endpoint.url(), Admin.Router.url()]\nend"
    |> to_source_file("lib/shop/orders.ex")
    |> run_check(WebNamespaceInCore, web_namespace: ["Storefront", "Admin"])
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "does not report the defmodule name of a nested module" do
    """
    defmodule DemoApp.Drops do
      defmodule DemoAppWeb.Nested do
      end
    end
    """
    |> to_source_file(@core_file)
    |> run_check(WebNamespaceInCore)
    |> refute_issues()
  end
end
