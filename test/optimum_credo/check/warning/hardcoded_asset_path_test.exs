defmodule OptimumCredo.Check.Warning.HardcodedAssetPathTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.HardcodedAssetPath

  test "reports hard-coded asset paths in ~H with accurate lines" do
    ~S'''
    defmodule MyAppWeb.Components do
      def logo(assigns) do
        ~H"""
        <img src="/images/logo.png" />
        <link rel="stylesheet" href="/assets/app.css">
        <script src='/js/app.js'></script>
        <img src="/fonts/a.woff2" /><img src="/css/a.css" />
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(HardcodedAssetPath)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [4, 5, 6, 7, 7] end)
  end

  test "allows verified routes, dynamic values, external URLs and other paths" do
    ~S'''
    defmodule MyAppWeb.Components do
      def logo(assigns) do
        ~H"""
        <img src={~p"/images/logo.png"} />
        <img src={@src} />
        <img src="https://cdn.example.com/images/a.png" />
        <a href="/users">Users</a>
        <a data-src="/images/a.png">x</a>
        <img srcset="/images/a.png 2x" />
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(HardcodedAssetPath)
    |> refute_issues()
  end

  test "ignores strings outside templates and non-H sigils" do
    ~S'''
    defmodule MyApp.Mailer do
      def html, do: "<img src=\"/images/logo.png\" />"
      def raw, do: ~s(<img src="/images/logo.png" />)
      # <img src="/images/logo.png" />
    end
    '''
    |> to_source_file()
    |> run_check(HardcodedAssetPath)
    |> refute_issues()
  end

  test "prefixes param" do
    source = ~S'''
    defmodule MyAppWeb.Components do
      def a(assigns), do: ~H"<img src='/images/a.png'/><img src='/static/a.png'/>"
    end
    '''

    source
    |> to_source_file()
    |> run_check(HardcodedAssetPath, prefixes: ["/static/"])
    |> assert_issue(fn issue -> assert issue.message =~ "/static/a.png" end)
  end

  test "reads .heex files" do
    "<div>\n<img src=\"/images/a.png\" />\n</div>"
    |> Credo.SourceFile.parse("lib/my_app_web/page.html.heex")
    |> run_check(HardcodedAssetPath)
    |> assert_issue(fn issue -> assert issue.line_no == 2 end)
  end

  test "ignores examples in HTML comments, HEEx comments, script/style bodies and plain text" do
    ~S'''
    defmodule MyAppWeb.Components do
      def page(assigns) do
        ~H"""
        <!-- <img src="/images/a.png"> -->
        <%!-- <img src="/images/b.png"> --%>
        <%# <img src="/images/b2.png"> %>
        <script>var s = '<img src="/images/c.png">'</script>
        <style>a { background: url("/images/x.png") } /* href="/css/x" */</style>
        <p>write src="/images/d.png" like so</p>
        <p>{"src=\"/images/e.png\""}</p>
        <img src="/images/real.png">
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(HardcodedAssetPath)
    |> assert_issue(fn issue ->
      assert issue.line_no == 11
      assert issue.message =~ "real.png"
    end)
  end

  test "the same exclusions apply to standalone .heex files, with real line numbers" do
    """
    <!--
      <img src="/images/a.png">
    -->
    <%!-- <img src="/images/b.png"> --%>
    <script>
      document.write('<img src="/images/c.png">')
    </script>
    <img
      alt="logo"
      src="/images/real.png"
    >
    """
    |> Credo.SourceFile.parse("lib/my_app_web/page.html.heex")
    |> run_check(HardcodedAssetPath)
    |> assert_issue(fn issue -> assert issue.line_no == 10 end)
  end

  test "reads components, string-literal expressions and attributes after > in values" do
    ~S'''
    defmodule MyAppWeb.Components do
      def page(assigns) do
        ~H"""
        <.link href="/assets/doc.pdf" title="a > b">doc</.link>
        <img src={"/images/lit.png"} />
        <img src={"/images/" <> @name} />
        <img src={~p"/images/ok.png"} />
        <a href="/images">bare directory</a>
        <img SRC="/images/upper.png" />
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(HardcodedAssetPath)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [4, 5, 9] end)
  end
end
