defmodule OptimumCredo.Check.Readability.ModulePathMismatchTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.ModulePathMismatch

  @moduletag :tmp_dir

  defp run(source, filename, params \\ []) do
    source
    |> to_source_file(filename)
    |> run_check(ModulePathMismatch, params)
  end

  test "accepts nested modules that mirror the path" do
    "defmodule MyApp.Billing.Invoice do\nend"
    |> run("lib/my_app/billing/invoice.ex")
    |> refute_issues()
  end

  test "reports a module defined under the wrong directory" do
    "defmodule MyApp.ScreenshotHelper do\nend"
    |> run("lib/my_app_web/controllers/helper.ex")
    |> assert_issue(fn issue ->
      assert issue.line_no == 1
      assert issue.message =~ "lib/my_app/screenshot_helper.ex"
    end)
  end

  test "reports a wrong file name and a deeper module than the path" do
    "defmodule MyApp.Billing do\nend"
    |> run("lib/my_app/invoice.ex")
    |> assert_issue()

    "defmodule MyApp.Billing.Invoice do\nend"
    |> run("lib/my_app/billing.ex")
    |> assert_issue()
  end

  test "underscores acronyms and camel case segments like Macro.underscore/1" do
    "defmodule MyApp.PageHTML do\nend"
    |> run("lib/my_app/page_html.ex")
    |> refute_issues()

    "defmodule MyApp.PageHTML do\nend"
    |> run("lib/my_app/page_h_t_m_l.ex")
    |> assert_issue()
  end

  test "accepts the Phoenix layer directories below a web root" do
    for {module, path} <- [
          {"MyAppWeb.PageController", "lib/my_app_web/controllers/page_controller.ex"},
          {"MyAppWeb.UserLive.Index", "lib/my_app_web/live/user_live/index.ex"},
          {"MyAppWeb.CoreComponents", "lib/my_app_web/components/core_components.ex"},
          {"MyAppWeb.Router", "lib/my_app_web/router.ex"},
          {"MyAppWeb.Layouts", "apps/my_app_web/lib/my_app_web/components/layouts.ex"}
        ] do
      "defmodule #{module} do\nend"
      |> run(path)
      |> refute_issues()
    end
  end

  test "layer directories are only optional below a web root and when configured" do
    "defmodule MyApp.PageController do\nend"
    |> run("lib/my_app/controllers/page_controller.ex")
    |> assert_issue()

    "defmodule MyAppWeb.PageController do\nend"
    |> run("lib/my_app_web/controllers/page_controller.ex", web_layer_dirs: [])
    |> assert_issue()
  end

  test "works in umbrella layouts" do
    "defmodule Core.Accounts do\nend"
    |> run("apps/core/lib/core/accounts.ex")
    |> refute_issues()

    "defmodule Core.Users do\nend"
    |> run("apps/core/lib/core/accounts.ex")
    |> assert_issue()
  end

  test "accepts nested modules and top-level modules in the file's namespace" do
    """
    defmodule MyApp.Invoice do
      defmodule Line do
      end

      defmodule Other.Deep do
      end
    end

    defmodule MyApp.Invoice.Totals do
    end
    """
    |> run("lib/my_app/invoice.ex")
    |> refute_issues()
  end

  test "reports an unrelated additional top-level module at its own line" do
    """
    defmodule MyApp.Invoice do
    end

    defmodule MyApp.Other do
    end
    """
    |> run("lib/my_app/invoice.ex")
    |> assert_issue(fn issue ->
      assert issue.line_no == 4
      assert issue.message =~ "MyApp.Other is neither named for this file"
    end)
  end

  test "the module that matches the path anchors the file even when it is not first" do
    """
    defmodule MyApp.Invoice.Helper do
    end

    defmodule MyApp.Invoice do
    end
    """
    |> run("lib/my_app/invoice.ex")
    |> refute_issues()

    """
    defmodule Other.Thing do
    end

    defmodule MyApp.Invoice do
    end
    """
    |> run("lib/my_app/invoice.ex")
    |> assert_issue(fn issue -> assert issue.line_no == 1 end)
  end

  test "reports only the first module when none matches the path" do
    """
    defmodule MyApp.Wrong do
    end

    defmodule MyApp.Wrong.Child do
    end
    """
    |> run("lib/my_app/invoice.ex")
    |> assert_issue(fn issue ->
      assert issue.line_no == 1
      assert issue.message =~ "expected lib/my_app/wrong.ex"
    end)
  end

  test "additional_modules: :report requires every top-level module to match" do
    source = """
    defmodule MyApp.Invoice do
    end

    defmodule MyApp.Invoice.Totals do
    end
    """

    source
    |> run("lib/my_app/invoice.ex", additional_modules: :report)
    |> assert_issue()

    source
    |> run("lib/my_app/invoice.ex", additional_modules: :nested)
    |> refute_issues()
  end

  test "additional_modules: :ignore only compares the first module" do
    source = """
    defmodule MyApp.Invoice do
    end

    defmodule Unrelated do
    end
    """

    source
    |> run("lib/my_app/invoice.ex", additional_modules: :ignore)
    |> refute_issues()

    "defmodule Wrong do\nend\ndefmodule MyApp.Invoice do\nend"
    |> run("lib/my_app/invoice.ex", additional_modules: :ignore)
    |> assert_issue()
  end

  test "allowed_modules exempt a module and its children, including a leading Elixir." do
    source = "defmodule MyApp.Legacy.Thing.Deep do\nend"

    source
    |> run("lib/my_app/x.ex", allowed_modules: ["MyApp.Legacy.Thing"])
    |> refute_issues()

    source
    |> run("lib/my_app/x.ex", allowed_modules: [MyApp.Legacy.Thing])
    |> refute_issues()

    source
    |> run("lib/my_app/x.ex", allowed_modules: ["Elixir.MyApp.Legacy"])
    |> refute_issues()

    source
    |> run("lib/my_app/x.ex", allowed_modules: ["MyApp.Legacy.Thin"])
    |> assert_issue()

    """
    defmodule MyApp.Invoice do
    end

    defmodule MyApp.Scratch do
    end
    """
    |> run("lib/my_app/invoice.ex", allowed_modules: ["MyApp.Scratch"])
    |> refute_issues()
  end

  test "an invalid additional_modules value raises instead of picking a policy" do
    assert_raise ArgumentError, ~r/invalid additional_modules/, fn ->
      "defmodule A do\nend"
      |> to_source_file("lib/a.ex")
      |> ModulePathMismatch.run(additional_modules: :sometimes)
    end
  end

  test "accepts Phoenix generated files, application roots and nested web roots" do
    for {module, path} <- [
          {"MyApp", "lib/my_app.ex"},
          {"MyApp.Application", "lib/my_app/application.ex"},
          {"MyApp.Repo", "lib/my_app/repo.ex"},
          {"MyAppWeb", "lib/my_app_web.ex"},
          {"MyAppWeb.Endpoint", "lib/my_app_web/endpoint.ex"},
          {"MyAppWeb.PageHTML", "lib/my_app_web/controllers/page_html.ex"},
          {"MyAppWeb.ErrorJSON", "lib/my_app_web/controllers/error_json.ex"},
          {"MyAppWeb.UserSocket", "lib/my_app_web/channels/user_socket.ex"},
          {"MyAppWeb.Layouts", "lib/my_app_web/components/layouts.ex"},
          {"MyOrg.MyAppWeb.PageController",
           "lib/my_org/my_app_web/controllers/page_controller.ex"},
          {"MyApp.Accounts.User", "apps\\my_app\\lib\\my_app\\accounts\\user.ex"}
        ] do
      "defmodule #{module} do\nend"
      |> run(path)
      |> refute_issues()
    end
  end

  test "a layer directory is not optional when it is the last path segment before the file" do
    "defmodule MyAppWeb do\nend"
    |> run("lib/my_app_web/live.ex")
    |> assert_issue()
  end

  test "finds the project lib directory when an ancestor is also called lib", %{tmp_dir: tmp} do
    project = Path.join([tmp, "lib", "ci", "app"])
    File.mkdir_p!(project)

    project
    |> Path.join("mix.exs")
    |> File.write!("")

    path = Path.join([project, "lib", "my_app", "invoice.ex"])

    "defmodule MyApp.Invoice do\nend"
    |> run(path)
    |> refute_issues()
  end

  test "ignore_paths accepts regexes and backslash fragments" do
    source = "defmodule Wrong.Name do\nend"

    source
    |> run("lib/my_app/legacy/thing.ex", ignore_paths: [~r/legacy/])
    |> refute_issues()

    source
    |> run("lib/my_app/legacy/thing.ex", ignore_paths: ["my_app\\legacy"])
    |> refute_issues()
  end

  test "scopes to .ex files under lib and skips mix tasks and ignore_paths" do
    source = "defmodule Wrong.Name do\nend"

    source
    |> run("test/support/helper.ex")
    |> refute_issues()

    source
    |> run("lib/my_app/script.exs")
    |> refute_issues()

    source
    |> run("lib/mix/tasks/my.task.ex")
    |> refute_issues()

    source
    |> run("lib/my_app/legacy/thing.ex", ignore_paths: ["legacy/"])
    |> refute_issues()

    source
    |> run("lib/my_app/legacy/thing.ex")
    |> assert_issue()
  end

  test "ignores dynamic module names and files without a module" do
    "defmodule __MODULE__.Child do\nend"
    |> run("lib/my_app/x.ex")
    |> refute_issues()

    "IO.puts(\"defmodule Wrong.Name\")"
    |> run("lib/my_app/x.ex")
    |> refute_issues()
  end
end
