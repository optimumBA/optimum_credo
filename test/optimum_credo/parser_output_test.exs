defmodule OptimumCredo.ParserOutputTest do
  use Credo.Test.Case, async: false
  import ExUnit.CaptureIO

  test "parsing inspected source does not print deprecation warnings" do
    source =
      to_source_file(
        """
        defmodule ParserProbe do
          use ExUnit.Case, async: false
          def value, do: 'legacy'
          # def old, do: 'legacy'
          # def older, do: 'legacy'
        end
        """,
        "test/parser_probe_test.exs"
      )

    for check <- [
          OptimumCredo.Check.Warning.CommentedOutCode,
          OptimumCredo.Check.Warning.AsyncFalseWithoutComment
        ] do
      assert capture_io(:stderr, fn -> check.run(source, []) end) == ""
    end
  end
end
