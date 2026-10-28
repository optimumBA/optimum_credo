defmodule OptimumCredo.Check.Warning.ExternalCallInMigrationTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.ExternalCallInMigration

  @path "priv/repo/migrations/20260101000000_sync.exs"

  defp run(body, params \\ [], path \\ @path) do
    """
    defmodule MyApp.Repo.Migrations.Sync do
      use Ecto.Migration

      def up do
        #{body}
      end
    end
    """
    |> to_source_file(path)
    |> run_check(ExternalCallInMigration, params)
  end

  test "it reports HTTP clients and other default external modules" do
    for call <- [
          ~s|Req.get!("https://example.test")|,
          ~s|HTTPoison.post("https://example.test", "")|,
          "Tesla.get(client, \"/x\")",
          "Finch.request(req, MyApp.Finch)",
          "ExAws.request(op)",
          "Stripe.Customer.create(%{})",
          "Swoosh.Mailer.deliver(email)",
          ~s|:httpc.request(~c"https://example.test")|,
          ":hackney.get(url)"
        ] do
      call
      |> run()
      |> assert_issue()
    end
  end

  test "it reports the call location and module name" do
    "Req.Request.new()"
    |> run()
    |> assert_issue(fn issue ->
      assert issue.line_no == 5
      assert issue.trigger == "Req.Request"
    end)
  end

  test "it reports calls nested in anonymous functions and pipes" do
    "url |> Req.get!() |> then(fn r -> Req.post!(r.url) end)"
    |> run()
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "it does not report database work, lookalike modules, strings or comments" do
    """
    execute("UPDATE users SET a = 1")
    Ecto.Migration.flush()
    Requests.get(1)
    Reqs.get(1)
    MyApp.Req.get(1)
    IO.puts("Req.get! is not called")
    # Req.get!("https://example.test")
    """
    |> run()
    |> refute_issues()
  end

  test "it honours external_modules including erlang modules and prefixes" do
    "Acme.Client.fetch()"
    |> run(external_modules: ["Acme"])
    |> assert_issue()

    "Acme.Client.fetch()"
    |> run(external_modules: [Acme.Client])
    |> assert_issue()

    "Req.get!(1)"
    |> run(external_modules: ["Acme"])
    |> refute_issues()

    ":inets.start()"
    |> run(external_modules: [":inets"])
    |> assert_issue()
  end

  test "it only checks migrations and honours ignore_files" do
    body = ~s|Req.get!("https://example.test")|

    body
    |> run([], "lib/my_app/client.ex")
    |> refute_issues()

    body
    |> run([], "priv/repo/seeds.exs")
    |> refute_issues()

    body
    |> run(ignore_files: ["20260101000000_sync.exs"])
    |> refute_issues()
  end

  describe "review regressions" do
    test "it follows an alias to an external module" do
      """
      alias Req, as: Http
      Http.get!("https://example.com")
      """
      |> run()
      |> assert_issue(fn issue -> assert issue.message =~ "Req.get!" end)
    end

    test "a local module that reuses an external name through an alias is not external" do
      """
      alias MyApp.Internal.Client, as: Req
      Req.get!("https://example.com")
      """
      |> run()
      |> refute_issues()
    end

    test "strings, comments and variables named like clients are not calls" do
      """
      # Req.get!("https://example.com")
      req = %{get: 1}
      IO.puts("Req.get!(x) via HTTPoison")
      """
      |> run()
      |> refute_issues()
    end
  end
end
