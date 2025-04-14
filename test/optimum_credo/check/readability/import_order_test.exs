defmodule OptimumCredo.Check.Readability.ImportOrderTest do
  use Credo.Test.Case

  alias OptimumCredo.Check.Readability.ImportOrder

  test "it should NOT report properly ordered imports" do
    """
    defmodule CredoSampleModule do
      import Apple
      import Banana
      import Cherry

      import Data.One
      import Data.Two
    end
    """
    |> to_source_file()
    |> run_check(ImportOrder)
    |> refute_issues()
  end

  test "it should report imports that are out of order within the same group" do
    """
    defmodule CredoSampleModule do
      import Cherry
      import Apple
      import Banana
    end
    """
    |> to_source_file()
    |> run_check(ImportOrder)
    |> assert_issue()
  end

  test "it should check multi-part import ordering" do
    """
    defmodule CredoSampleModule do
      import Data.Two
      import Data.One
    end
    """
    |> to_source_file()
    |> run_check(ImportOrder)
    |> assert_issue()
  end
end
