defmodule OptimumCredo.Check.Readability.TestPathMismatchTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.TestPathMismatch

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    for lib <- [
          "lib/my_app/billing/invoice.ex",
          "lib/my_app_web/controllers/page_controller.ex",
          "lib/my_app_web/live/user_live/index.ex"
        ] do
      path = Path.join(dir, lib)

      path
      |> Path.dirname()
      |> File.mkdir_p!()

      File.write!(path, "")
    end

    :ok
  end

  defp run(source, dir, relative, params \\ []) do
    source
    |> to_source_file(Path.join(dir, relative))
    |> run_check(TestPathMismatch, params)
  end

  test "accepts a mirrored path, module name and counterpart", %{tmp_dir: dir} do
    "defmodule MyApp.Billing.InvoiceTest do\nend"
    |> run(dir, "test/my_app/billing/invoice_test.exs")
    |> refute_issues()
  end

  test "reports a module name that does not mirror the path", %{tmp_dir: dir} do
    "defmodule MyApp.Billing.PaymentTest do\nend"
    |> run(dir, "test/my_app/billing/invoice_test.exs")
    |> assert_issue(fn issue ->
      assert issue.message =~ "does not match its path"
      assert issue.line_no == 1
    end)
  end

  test "reports a module name without the Test suffix", %{tmp_dir: dir} do
    "defmodule MyApp.Billing.Invoice do\nend"
    |> run(dir, "test/my_app/billing/invoice_test.exs")
    |> assert_issue(fn issue -> assert issue.message =~ "should end in Test" end)
  end

  test "reports a test without a lib counterpart and honors the parameter", %{tmp_dir: dir} do
    source = "defmodule MyApp.Billing.RefundTest do\nend"
    path = "test/my_app/billing/refund_test.exs"

    source
    |> run(dir, path)
    |> assert_issue(fn issue -> assert issue.message =~ "lib/my_app/billing/refund.ex" end)

    source
    |> run(dir, path, require_test_counterpart: false)
    |> refute_issues()
  end

  test "accepts Phoenix layer directories below a web root", %{tmp_dir: dir} do
    "defmodule MyAppWeb.PageControllerTest do\nend"
    |> run(dir, "test/my_app_web/controllers/page_controller_test.exs")
    |> refute_issues()

    "defmodule MyAppWeb.UserLive.IndexTest do\nend"
    |> run(dir, "test/my_app_web/live/user_live/index_test.exs")
    |> refute_issues()
  end

  test "exempts support, features, integration, mix tasks and ignored paths", %{tmp_dir: dir} do
    source = "defmodule Whatever.NameTest do\nend"

    for path <- [
          "test/support/thing_test.exs",
          "test/my_app/features/signup_test.exs",
          "test/integration/flow_test.exs",
          "test/mix/tasks/demo_test.exs",
          "test/legacy/old_test.exs"
        ] do
      source
      |> run(dir, path, ignore_paths: ["legacy/"])
      |> refute_issues()
    end
  end

  test "only inspects *_test.exs files below a test directory", %{tmp_dir: dir} do
    source = "defmodule Whatever.Name do\nend"

    source
    |> run(dir, "test/test_helper.exs")
    |> refute_issues()

    source
    |> run(dir, "lib/my_app/x_test.exs")
    |> refute_issues()

    source
    |> run(dir, "test/my_app/x_test.ex")
    |> refute_issues()
  end

  test "ignores dynamic module names but still checks the counterpart", %{tmp_dir: dir} do
    "defmodule __MODULE__.Test do\nend"
    |> run(dir, "test/my_app/billing/invoice_test.exs")
    |> refute_issues()

    "IO.puts(1)"
    |> run(dir, "test/my_app/missing_test.exs")
    |> assert_issue(fn issue -> assert issue.message =~ "No lib/my_app/missing.ex" end)
  end

  test "accepts a counterpart directory such as Phoenix LiveView modules", %{tmp_dir: dir} do
    "defmodule MyAppWeb.UserLiveTest do\nend"
    |> run(dir, "test/my_app_web/live/user_live_test.exs")
    |> refute_issues()

    "defmodule MyAppWeb.GhostLiveTest do\nend"
    |> run(dir, "test/my_app_web/live/ghost_live_test.exs")
    |> assert_issue(fn issue -> assert issue.message =~ "lib/my_app_web/live/ghost_live.ex" end)
  end

  test "reports the counterpart at the module line", %{tmp_dir: dir} do
    "# header\n\ndefmodule MyApp.Billing.RefundTest do\nend"
    |> run(dir, "test/my_app/billing/refund_test.exs")
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "supports umbrella apps and backslash paths", %{tmp_dir: dir} do
    path = Path.join(dir, "apps/core/lib/core/accounts.ex")

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, "")

    "defmodule Core.AccountsTest do\nend"
    |> run(dir, "apps/core/test/core/accounts_test.exs")
    |> refute_issues()

    "defmodule Core.UsersTest do\nend"
    |> run(dir, "apps/core/test/core/users_test.exs")
    |> assert_issue(fn issue -> assert issue.message =~ "No lib/core/users.ex" end)

    "defmodule Core.AccountsTest do\nend"
    |> run(dir, "apps\\core\\test\\core\\accounts_test.exs")
    |> refute_issues()
  end

  test "uses the project root even when a parent directory is named test", %{tmp_dir: dir} do
    project = Path.join([dir, "test", "ci", "app"])

    project
    |> Path.join("lib/my_app")
    |> File.mkdir_p!()

    project
    |> Path.join("mix.exs")
    |> File.write!("")

    project
    |> Path.join("lib/my_app/billing.ex")
    |> File.write!("")

    "defmodule MyApp.BillingTest do\nend"
    |> run(dir, "test/ci/app/test/my_app/billing_test.exs")
    |> refute_issues()
  end

  test "accepts nested web roots with layer directories", %{tmp_dir: dir} do
    path = Path.join(dir, "lib/my_org/my_app_web/controllers/page_controller.ex")

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, "")

    "defmodule MyOrg.MyAppWeb.PageControllerTest do\nend"
    |> run(dir, "test/my_org/my_app_web/controllers/page_controller_test.exs")
    |> refute_issues()
  end

  test "ignore_paths accepts regexes", %{tmp_dir: dir} do
    "defmodule Wrong.NameTest do\nend"
    |> run(dir, "test/my_app/x_test.exs", ignore_paths: [~r/my_app\/x_test/])
    |> refute_issues()
  end

  test "accepts a test mirroring the path of the lib file that defines its subject", %{
    tmp_dir: dir
  } do
    path = Path.join(dir, "lib/my_app/helpers/slug_helper.ex")

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, "defmodule MyApp.SlugHelper do\nend\n")

    "defmodule MyApp.SlugHelperTest do\nend"
    |> run(dir, "test/my_app/helpers/slug_helper_test.exs")
    |> refute_issues()
  end

  test "still reports a differing module when the mirrored lib file defines another module", %{
    tmp_dir: dir
  } do
    path = Path.join(dir, "lib/my_app/helpers/slug_helper.ex")

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(path, "defmodule MyApp.OtherHelper do\nend\n")

    "defmodule MyApp.SlugHelperTest do\nend"
    |> run(dir, "test/my_app/helpers/slug_helper_test.exs")
    |> assert_issue(fn issue -> assert issue.message =~ "does not match its path" end)
  end
end
