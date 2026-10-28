defmodule OptimumCredo.Check.Readability.GettextDomainTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.GettextDomain

  defp run(body, params \\ [ash: true], path \\ "lib/my_app_web/live/post_live.ex") do
    """
    defmodule MyAppWeb.PostLive do
      use Gettext, backend: MyAppWeb.Gettext

      def render(assigns) do
        #{body}
      end
    end
    """
    |> to_source_file(path)
    |> run_check(GettextDomain, params)
  end

  test "it reports bare gettext calls" do
    for call <- [
          ~s|gettext("Save")|,
          ~s|ngettext("one", "many", count)|,
          ~s|pgettext("button", "Save")|,
          ~s|npgettext("button", "one", "many", count)|
        ] do
      call
      |> run()
      |> assert_issue()
    end
  end

  test "it reports the line and function" do
    ~s|gettext("Save")|
    |> run()
    |> assert_issue(fn issue ->
      assert issue.line_no == 5
      assert issue.trigger == "gettext"
      assert issue.message =~ "Bare `gettext`"
    end)
  end

  test "it accepts calls with a domain" do
    """
    dgettext("posts", "Save")
    dngettext("posts", "one", "many", count)
    dpgettext("posts", "button", "Save")
    dnpgettext("posts", "button", "one", "many", count)
    dgettext(domain, "Save")
    """
    |> run()
    |> refute_issues()
  end

  test "it validates literal domains against allowed_domains" do
    params = [ash: true, allowed_domains: ["posts", :accounts]]

    ~s|dgettext("posts", "Save")|
    |> run(params)
    |> refute_issues()

    ~s|dgettext("accounts", "Save")|
    |> run(params)
    |> refute_issues()

    ~s|dgettext("default", "Save")|
    |> run(params)
    |> assert_issue(fn issue -> assert issue.message =~ "\"default\"" end)

    ~s|dpgettext("errors", "button", "Save")|
    |> run(params)
    |> assert_issue()

    ~s|dgettext(domain, "Save")|
    |> run(params)
    |> refute_issues()

    ~s|dgettext("anything", "Save")|
    |> run()
    |> refute_issues()
  end

  test "it ignores remote calls, definitions, imports, strings and comments" do
    """
    Gettext.gettext(MyAppWeb.Gettext, "Save")
    MyAppWeb.Gettext.gettext("Save")
    # gettext("Save")
    "gettext(\\"Save\\")"
    """
    |> run()
    |> refute_issues()

    """
    defmodule MyAppWeb.Gettext do
      import Gettext, only: [gettext: 1]
      def gettext(message), do: message
      defp pgettext(a, b) when is_binary(a), do: {a, b}
    end
    """
    |> to_source_file("lib/my_app_web/gettext.ex")
    |> run_check(GettextDomain, ash: true)
    |> refute_issues()
  end

  test "it honours bare_functions" do
    ~s|with_locale("bs", fn -> :ok end)|
    |> run(ash: true, bare_functions: [:gettext])
    |> refute_issues()

    ~s|gettext("Save")|
    |> run(ash: true, bare_functions: [:gettext])
    |> assert_issue()
  end

  test "it only checks lib/ and is disabled unless ash: true" do
    call = ~s|gettext("Save")|

    call
    |> run([ash: true], "test/post_live_test.exs")
    |> refute_issues()

    call
    |> run([ash: true], "priv/repo/seeds.exs")
    |> refute_issues()

    call
    |> run([])
    |> refute_issues()

    call
    |> run(ash: false)
    |> refute_issues()
  end

  describe "review regressions" do
    test "with_locale is not a bare lookup by default" do
      ~s|with_locale("bs", fn -> :ok end)|
      |> run()
      |> refute_issues()
    end

    test "with_locale configured as bare says it is no dgettext case" do
      ~s|with_locale("bs", fn -> :ok end)|
      |> run(ash: true, bare_functions: [:with_locale])
      |> assert_issue(fn issue ->
        assert issue.message =~ "sets the locale"
        refute issue.message =~ "use the `d*` variant"
      end)
    end

    test "typespecs and definition heads that name gettext functions are not calls" do
      """
      defmodule MyAppWeb.Translate do
        @callback gettext(String.t()) :: String.t()
        @spec ngettext(String.t(), String.t(), integer()) :: String.t()
        def gettext(msgid), do: msgid
      end
      """
      |> run_source(ash: true)
      |> refute_issues()
    end

    test "gettext_noop is bare and dgettext_noop is validated against allowed domains" do
      ~s|gettext_noop("Save")|
      |> run()
      |> assert_issue()

      ~s|dgettext_noop("posts", "Save")|
      |> run(ash: true, allowed_domains: ["posts"])
      |> refute_issues()

      ~s|dgettext_noop("other", "Save")|
      |> run(ash: true, allowed_domains: ["posts"])
      |> assert_issue()
    end

    test "a file outside lib/ is not checked" do
      ~s|gettext("Save")|
      |> run([ash: true], "test/my_app_web/post_live_test.exs")
      |> refute_issues()
    end
  end

  defp run_source(source, params) do
    source
    |> to_source_file("lib/my_app_web/translate.ex")
    |> run_check(GettextDomain, params)
  end
end
