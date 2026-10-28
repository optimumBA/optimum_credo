defmodule OptimumCredo.Check.Warning.AuthorizeFalseWithoutCommentTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.AuthorizeFalseWithoutComment

  defp run(source, params \\ [ash: true], path \\ "lib/my_app/blog.ex") do
    source
    |> to_source_file(path)
    |> run_check(AuthorizeFalseWithoutComment, params)
  end

  test "it reports authorize?: false without a comment" do
    """
    defmodule MyApp.Blog do
      def list, do: Ash.read!(Post, authorize?: false)

      def get(id) do
        Ash.get!(Post, id,
          authorize?: false,
          load: [:comments]
        )
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [2, 6] end)
  end

  test "it accepts a same-line comment" do
    """
    defmodule MyApp.Blog do
      def list, do: Ash.read!(Post, authorize?: false) # background job
      def get(id), do: Ash.get!(Post, id, authorize?: false)  # sync, no actor
    end
    """
    |> run()
    |> refute_issues()
  end

  test "a comment on the preceding line or a different line does not count" do
    """
    defmodule MyApp.Blog do
      # system job
      def list, do: Ash.read!(Post, authorize?: false)
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "it ignores strings, heredocs, sigils, comments and other values" do
    ~S'''
    defmodule MyApp.Blog do
      @moduledoc """
      Pass `authorize?: false` only when needed.
      """

      def a, do: "authorize?: false"
      def b, do: ~s(authorize?: false)
      # Ash.read!(Post, authorize?: false)
      def c, do: Ash.read!(Post, authorize?: true)
      def d, do: Ash.read!(Post, authorize?: false_flag)
      def e, do: Ash.read!(Post, authorize?: false)
    end
    '''
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 11 end)
  end

  test "it ignores test, seeds, fixtures files and Fixtures modules" do
    source = "defmodule MyApp.Blog do\n  def list, do: Ash.read!(Post, authorize?: false)\nend\n"

    source
    |> run([ash: true], "test/my_app/blog_test.exs")
    |> refute_issues()

    source
    |> run([ash: true], "priv/repo/seeds.exs")
    |> refute_issues()

    source
    |> run([ash: true], "priv/repo/seeds/dev.exs")
    |> refute_issues()

    source
    |> run([ash: true], "lib/my_app/blog_fixtures.ex")
    |> refute_issues()

    source
    |> run([ash: true], "lib/my_app/blog.ex")
    |> assert_issue()

    source
    |> String.replace("MyApp.Blog", "MyApp.BlogFixtures")
    |> run()
    |> refute_issues()
  end

  test "it honours ignore_paths" do
    source = "Ash.read!(Post, authorize?: false)\n"

    source
    |> run([ash: true, ignore_paths: ["lib/jobs/"]], "lib/jobs/sync.ex")
    |> refute_issues()

    source
    |> run([ash: true, ignore_paths: []], "test/blog_test.exs")
    |> assert_issue()
  end

  test "it is disabled unless ash: true" do
    source = "Ash.read!(Post, authorize?: false)\n"

    source
    |> run([])
    |> refute_issues()

    source
    |> run(ash: false)
    |> refute_issues()
  end

  describe "review regressions" do
    test "a # inside a string earlier on the line does not hide the missing comment" do
      ~S"""
      defmodule MyApp.Blog do
        def a, do: Ash.read!(Post, tag: "#a", authorize?: false)
        def b, do: Ash.read!(Post, tag: "#b", authorize?: false) # background job
      end
      """
      |> run()
      |> assert_issue(fn issue -> assert issue.line_no == 2 end)
    end

    test "authorize?: false in strings, heredocs, sigils and comments is not code" do
      ~S|
      defmodule MyApp.Blog do
        @moduledoc """
        Pass authorize?: false only with a reason.
        """

        # Ash.read!(Post, authorize?: false)
        def a, do: "authorize?: false"
        def b, do: ~s(authorize?: false)
      end
      |
      |> run()
      |> refute_issues()
    end

    test "authorize?: true or a variable is not reported" do
      "defmodule MyApp.Blog do\n  def a, do: Ash.read!(Post, authorize?: skip?)\nend\n"
      |> run()
      |> refute_issues()
    end
  end
end
