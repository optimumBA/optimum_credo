defmodule OptimumCredo.Check.Warning.EnvVarWithoutFailureTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.EnvVarWithoutFailure

  defp prod(body, params \\ [], path \\ "config/runtime.exs") do
    """
    import Config

    if config_env() == :prod do
      #{body}
    end
    """
    |> to_source_file(path)
    |> run_check(EnvVarWithoutFailure, params)
  end

  test "it reports a bare System.get_env in the prod block" do
    ~s|client_id = System.get_env("GITHUB_CLIENT_ID")|
    |> prod()
    |> assert_issue(fn issue ->
      assert issue.line_no == 4
      assert issue.message =~ "GITHUB_CLIENT_ID"
    end)
  end

  test "it reports get_env used directly as a config value or piped" do
    ~s|config :my_app, client_id: System.get_env("CLIENT_ID")|
    |> prod()
    |> assert_issue()

    "config :my_app, client_id: System.get_env(\"CLIENT_ID\") |> String.trim()"
    |> prod()
    |> assert_issue()
  end

  test "it reports every unhandled call" do
    """
    a = System.get_env("A")
    b = System.get_env("B") || raise "B missing"
    c = System.get_env("C")
    """
    |> prod()
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [4, 6] end)
  end

  test "it handles fetch_env!, || fallbacks and raise" do
    """
    a = System.fetch_env!("A")
    b = System.get_env("B") || raise "environment variable B is missing"
    c = System.get_env("C") || "fallback"
    d = System.get_env("D", "default")
    """
    |> prod()
    |> refute_issues()
  end

  test "it handles an explicit check and raise" do
    """
    secret = System.get_env("SECRET")

    if is_nil(secret) do
      raise "SECRET is missing"
    end

    case System.get_env("OTHER") do
      nil -> raise "OTHER is missing"
      value -> value
    end

    System.get_env("THIRD") |> case do
      nil -> raise "THIRD is missing"
      value -> value
    end
    """
    |> prod()
    |> refute_issues()
  end

  test "a later raise that does not use the variable does not count" do
    """
    secret = System.get_env("SECRET")
    other = System.get_env("OTHER")
    if is_nil(other), do: raise("OTHER is missing")
    """
    |> prod()
    |> assert_issue(fn issue -> assert issue.message =~ "SECRET" end)
  end

  test "it accepts presence tests and calls that crash on nil" do
    """
    if System.get_env("ENABLE_X") do
      config :my_app, x: true
    end

    port = System.get_env("PORT") |> String.to_integer()
    key = Base.decode64!(System.get_env("KEY"))
    """
    |> prod()
    |> refute_issues()
  end

  test "it honours optional_vars" do
    ~s|x = System.get_env("OPTIONAL")|
    |> prod(optional_vars: ["OPTIONAL"])
    |> refute_issues()

    ~s|x = System.get_env("OPTIONAL")|
    |> prod(optional_vars: ["OTHER"])
    |> assert_issue()
  end

  test "the phx.new DNS_CLUSTER_QUERY is optional by default" do
    ~s|config :app, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")|
    |> prod()
    |> refute_issues()

    ~s|config :app, :host, System.get_env("PHX_HOST")|
    |> prod()
    |> assert_issue()
  end

  test "custom optional_vars replace the DNS_CLUSTER_QUERY default" do
    statement = ~s|config :app, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")|

    statement
    |> prod(optional_vars: ["OTHER"])
    |> assert_issue()

    statement
    |> prod(optional_vars: ["DNS_CLUSTER_QUERY", "OTHER"])
    |> refute_issues()
  end

  test "it supports case config_env() and ignores other environments" do
    """
    import Config

    case config_env() do
      :prod -> x = System.get_env("A")
      :dev -> y = System.get_env("B")
    end

    if config_env() == :dev do
      z = System.get_env("C")
    end

    w = System.get_env("D")
    """
    |> to_source_file("config/runtime.exs")
    |> run_check(EnvVarWithoutFailure)
    |> assert_issue(fn issue -> assert issue.message =~ "\"A\"" end)
  end

  test "it ignores strings and comments, and only reads config/runtime.exs" do
    ~s|# x = System.get_env("A")\ny = "System.get_env(\\"A\\")"|
    |> prod()
    |> refute_issues()

    ~s|x = System.get_env("A")|
    |> prod([], "config/prod.exs")
    |> refute_issues()

    ~s|x = System.get_env("A")|
    |> prod([], "lib/runtime.exs")
    |> refute_issues()

    ~s|x = System.get_env("A")|
    |> prod([], "apps/web/config/runtime.exs")
    |> assert_issue()
  end

  defp runtime(source) do
    source
    |> to_source_file("config/runtime.exs")
    |> run_check(EnvVarWithoutFailure, [])
  end

  describe "review regressions" do
    test "comparisons, nil checks and presence tests do not leak a nil setting" do
      """
      config :my_app, debug: System.get_env("DEBUG") == "true"
      config :my_app, mode: System.get_env("MODE") in ["a", "b"]
      config :my_app, set?: not is_nil(System.get_env("SET"))
      if host = System.get_env("HOST"), do: config(:my_app, host: host)

      smtp = System.get_env("SMTP")
      if smtp, do: config(:my_app, smtp: smtp)
      """
      |> prod()
      |> refute_issues()
    end

    test "System.get_env/0 returns the environment and a dynamic key is reported anonymously" do
      "config :my_app, env: System.get_env()"
      |> prod()
      |> refute_issues()

      "config :my_app, value: System.get_env(name)"
      |> prod()
      |> assert_issue(fn issue ->
        assert issue.message =~ "System.get_env/1 in the prod config"
      end)
    end

    test "a variable that is only assigned is still reported" do
      """
      token = System.get_env("TOKEN")
      config :my_app, token: token
      """
      |> prod()
      |> assert_issue(fn issue -> assert issue.line_no == 4 end)
    end

    test "only conditions that imply production select the branch" do
      for condition <- [
            "config_env() != :prod",
            "not (config_env() == :prod)",
            "config_env() == :dev or config_env() == :prod",
            "config_env() in [:dev, :prod]",
            "config_env() == :test"
          ] do
        """
        import Config

        if #{condition} do
          a = System.get_env("A")
        end
        """
        |> runtime()
        |> refute_issues()
      end

      for condition <- [
            "config_env() == :prod and enabled?",
            "config_env() in [:prod]",
            "config_env() === :prod"
          ] do
        """
        import Config

        if #{condition} do
          a = System.get_env("A")
        end
        """
        |> runtime()
        |> assert_issue()
      end
    end

    test "the else branch of a prod condition and other files are not read" do
      """
      import Config

      if config_env() == :prod do
        a = System.fetch_env!("A")
      else
        b = System.get_env("B")
      end
      """
      |> runtime()
      |> refute_issues()

      ~s|a = System.get_env("A")|
      |> prod([], "config/dev.exs")
      |> refute_issues()
    end

    test "optional_vars silences a variable by name" do
      ~s|a = System.get_env("A")|
      |> prod(optional_vars: ["A"])
      |> refute_issues()
    end
  end
end
