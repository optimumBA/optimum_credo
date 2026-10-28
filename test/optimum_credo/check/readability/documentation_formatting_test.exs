defmodule OptimumCredo.Check.Readability.DocumentationFormattingTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.DocumentationFormatting

  test "it should NOT report properly formatted documentation with blank lines" do
    """
    defmodule MyModule do
      @doc \"\"\"
      Returns the index URL.

      ## Examples

      iex> index_url()
      "http://localhost:4000/index.md"
      \"\"\"
      def index_url, do: "http://localhost:4000/index.md"
    end
    """
    |> to_source_file()
    |> run_check(DocumentationFormatting)
    |> refute_issues()
  end

  test "it should report missing blank line after Examples header" do
    """
    defmodule MyModule do
      @doc \"\"\"
      Returns the index URL.

      ## Examples
      iex> index_url()
      "http://localhost:4000/index.md"
      \"\"\"
      def index_url, do: "http://localhost:4000/index.md"
    end
    """
    |> to_source_file()
    |> run_check(DocumentationFormatting)
    |> assert_issue(fn issue ->
      assert issue.message =~
               "Missing blank line after documentation section header (## Examples)"
    end)
  end

  test "it should report missing blank line after Parameters header" do
    """
    defmodule MyModule do
      @doc \"\"\"
      Creates a new user.

      ## Parameters
      - name: The user's name
      - email: The user's email
      \"\"\"
      def create_user(name, email), do: %{name: name, email: email}
    end
    """
    |> to_source_file()
    |> run_check(DocumentationFormatting)
    |> assert_issue(fn issue ->
      assert issue.message =~
               "Missing blank line after documentation section header (## Parameters)"
    end)
  end

  test "it should handle multiple section headers" do
    """
    defmodule MyModule do
      @doc \"\"\"
      A complex function with multiple sections.

      ## Parameters
      - input: The input value

      ## Examples
      iex> complex_function("test")
      :ok

      ## Returns
      Always returns :ok
      \"\"\"
      def complex_function(input), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(DocumentationFormatting)
    |> assert_issues(fn issues ->
      assert length(issues) == 3
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &String.contains?(&1, "## Parameters"))
      assert Enum.any?(messages, &String.contains?(&1, "## Examples"))
      assert Enum.any?(messages, &String.contains?(&1, "## Returns"))
    end)
  end

  test "it should NOT report issues when there are already blank lines" do
    """
    defmodule MyModule do
      @doc \"\"\"
      A well-formatted function.

      ## Parameters

      - input: The input value

      ## Examples

      iex> well_formatted("test")
      :ok

      ## Returns

      Always returns :ok
      \"\"\"
      def well_formatted(input), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(DocumentationFormatting)
    |> refute_issues()
  end

  test "it should handle headers with different formatting" do
    """
    defmodule MyModule do
      @doc \"\"\"
      Function with various header formats.

      ## Usage
      Call this function directly

      ##Options
      No options available

      ## Notes
      This is important
      \"\"\"
      def various_headers, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(DocumentationFormatting)
    |> assert_issues(fn issues ->
      assert length(issues) == 2
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &String.contains?(&1, "## Usage"))
      assert Enum.any?(messages, &String.contains?(&1, "## Notes"))
    end)
  end

  test "it should NOT report issues for documentation without section headers" do
    """
    defmodule MyModule do
      @doc \"\"\"
      Simple function documentation without headers.
      Just a plain description.
      \"\"\"
      def simple_function, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(DocumentationFormatting)
    |> refute_issues()
  end

  test "it should handle section headers at the end of documentation" do
    """
    defmodule MyModule do
      @doc \"\"\"
      Function with header at the end.

      ## Note
      \"\"\"
      def end_header, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(DocumentationFormatting)
    |> refute_issues()
  end

  test "it should detect indented section headers" do
    """
    defmodule MyModule do
      @doc \"\"\"
      Function with indented headers.

        ## Examples
        Some example here
      \"\"\"
      def indented_header, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(DocumentationFormatting)
    |> assert_issue(fn issue ->
      assert issue.message =~
               "Missing blank line after documentation section header (## Examples)"
    end)
  end
end
