defmodule OptimumCredo.Check.Warning.UnsafeAtomConversionTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.UnsafeAtomConversion

  defp run(body, params \\ [], path \\ "lib/my_app_web/controllers/post_controller.ex") do
    """
    defmodule MyAppWeb.PostController do
      def index(conn, params) do
        #{body}
      end
    end
    """
    |> to_source_file(path)
    |> run_check(UnsafeAtomConversion, params)
  end

  test "it reports each atom-creating conversion" do
    for call <- [
          ~s|String.to_atom(params["sort_by"])|,
          ~s|List.to_atom(params["sort_by"])|,
          ~s|:erlang.binary_to_atom(params["sort_by"])|,
          ~s|:erlang.binary_to_atom(params["sort_by"], :utf8)|,
          ~s|:erlang.list_to_atom(params["sort_by"])|,
          ~s{params["sort_by"] |> String.to_atom()},
          ~s|Enum.map(params["keys"], &String.to_atom/1)|,
          ~S|String.to_atom("prefix_#{params["sort_by"]}")|
        ] do
      call
      |> run()
      |> assert_issue()
    end
  end

  test "it reports the line and function" do
    ~s|String.to_atom(params["sort_by"])|
    |> run()
    |> assert_issue(fn issue ->
      assert issue.line_no == 3
      assert issue.trigger == "String.to_atom"
    end)
  end

  test "it accepts existing-atom conversions and unrelated functions" do
    """
    String.to_existing_atom(params["sort_by"])
    List.to_existing_atom(params["sort_by"])
    :erlang.binary_to_existing_atom(params["sort_by"], :utf8)
    String.to_integer(params["page"])
    Atom.to_string(:ok)
    """
    |> run()
    |> refute_issues()
  end

  test "it accepts literal strings" do
    ~s|String.to_atom("admin")|
    |> run()
    |> refute_issues()

    ~s|:erlang.binary_to_atom("admin", :utf8)|
    |> run()
    |> refute_issues()
  end

  test "it accepts module attribute initialisers" do
    """
    defmodule MyApp.Types do
      @types Enum.map(["a", "b"], &String.to_atom/1)
      @type_name String.to_atom(Application.get_env(:my_app, :type))

      def types, do: @types
    end
    """
    |> to_source_file("lib/my_app/types.ex")
    |> run_check(UnsafeAtomConversion)
    |> refute_issues()
  end

  test "it still reports a conversion in a function next to an attribute" do
    """
    defmodule MyApp.Types do
      @types [:a, :b]

      def convert(name), do: String.to_atom(name)
    end
    """
    |> to_source_file("lib/my_app/types.ex")
    |> run_check(UnsafeAtomConversion)
    |> assert_issue(fn issue -> assert issue.line_no == 4 end)
  end

  test "it honours sobelow_skip and credo disable comments on the same or previous line" do
    """
    String.to_atom(params["a"]) # sobelow_skip ["DOS.StringToAtom"]
    # sobelow_skip ["DOS.StringToAtom"]
    String.to_atom(params["b"])
    # credo:disable-for-next-line OptimumCredo.Check.Warning.UnsafeAtomConversion
    String.to_atom(params["c"])
    """
    |> run()
    |> refute_issues()
  end

  test "a suppression comment two lines away does not apply" do
    """
    # sobelow_skip ["DOS.StringToAtom"]
    x = 1
    String.to_atom(params["a"])
    """
    |> run()
    |> assert_issue()
  end

  test "it ignores strings, comments and heredocs" do
    ~S'''
    # String.to_atom(params["a"])
    "String.to_atom(params)"
    '''
    |> run()
    |> refute_issues()
  end

  test "it skips config/ and priv/repo/ and honours allow_in_paths" do
    body = ~s|String.to_atom(params["a"])|

    body
    |> run([], "config/runtime.exs")
    |> refute_issues()

    body
    |> run([], "priv/repo/seeds.exs")
    |> refute_issues()

    body
    |> run([], "priv/repo/migrations/20260101_a.exs")
    |> refute_issues()

    body
    |> run([allow_in_paths: ["lib/my_app/dsl/"]], "lib/my_app/dsl/builder.ex")
    |> refute_issues()

    body
    |> run([allow_in_paths: ["lib/other/"]], "lib/my_app/dsl/builder.ex")
    |> assert_issue()

    body
    |> run([], "test/my_app/post_test.exs")
    |> assert_issue()
  end

  describe "review regressions" do
    test "a literal piped in is a fixed atom, a piped variable is not" do
      ~s{"admin" |> String.to_atom()}
      |> run()
      |> refute_issues()

      "List.to_atom([97, 98])"
      |> run()
      |> refute_issues()

      ~s{params["role"] |> String.to_atom()}
      |> run()
      |> assert_issue()
    end

    test "conversions inside unquote run at expansion time" do
      ~s|quote do: foo(unquote(String.to_atom(name)))|
      |> run()
      |> refute_issues()
    end

    test "a trailing sobelow_skip comment does not cover the next line" do
      """
      a = String.to_atom(params["a"]) # sobelow_skip ["DOS.StringToAtom"]
      b = String.to_atom(params["b"])
      """
      |> run()
      |> assert_issue(fn issue -> assert issue.line_no == 4 end)
    end

    test "a comment-only skip line covers the next line, if it names the right rule" do
      """
      # sobelow_skip ["DOS.StringToAtom"]
      a = String.to_atom(params["a"])
      """
      |> run()
      |> refute_issues()

      """
      # sobelow_skip
      a = String.to_atom(params["a"])
      """
      |> run()
      |> refute_issues()

      """
      # sobelow_skip ["XSS.Raw"]
      a = String.to_atom(params["a"])
      """
      |> run()
      |> assert_issue()
    end

    test "a sobelow_skip comment above a function head covers the whole function" do
      """
      defmodule MyApp.Parser do
        # sobelow_skip ["DOS.StringToAtom"]
        def f(x) do
          a = String.to_atom(x)
          a
        end

        def g(x), do: String.to_atom(x)
      end
      """
      |> to_source_file("lib/my_app/parser.ex")
      |> run_check(UnsafeAtomConversion, [])
      |> assert_issue(fn issue -> assert issue.line_no == 8 end)
    end

    test "the allowed attribute initialiser still applies, a read of the attribute does not matter" do
      """
      @types String.to_atom("a")
      String.to_atom(@types)
      """
      |> run()
      |> assert_issue()
    end
  end

  test "valid source ending in a string keeps code and comments separate" do
    source = ~S|value = String.to_atom(params["kind"])
text = "String.to_atom(params[\"safe\"])"|

    for ending <- ["", "\n"] do
      source
      |> Kernel.<>(ending)
      |> to_source_file("lib/my_app/example.ex")
      |> run_check(UnsafeAtomConversion)
      |> assert_issue(fn issue -> assert issue.line_no == 1 end)
    end
  end
end
