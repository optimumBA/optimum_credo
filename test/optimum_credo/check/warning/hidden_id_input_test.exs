defmodule OptimumCredo.Check.Warning.HiddenIdInputTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.HiddenIdInput

  test "reports hidden *_id inputs in several syntaxes" do
    ~S'''
    defmodule MyAppWeb.Form do
      def form(assigns) do
        ~H"""
        <input type="hidden" name="user_id" value={@user.id} />
        <.input type="hidden" field={@form[:account_id]} />
        <input
          type="hidden"
          name="post[author_id]"
          value={@author_id}
        />
        <input value={if @a > 1, do: 1} type='hidden' id="team_id">
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(HiddenIdInput)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [4, 5, 6, 11] end)
  end

  test "ignores visible inputs, bare id, other hidden fields and non-input tags" do
    ~S'''
    defmodule MyAppWeb.Form do
      def form(assigns) do
        ~H"""
        <input type="text" name="user_id" />
        <input type="hidden" name="id" />
        <input type="hidden" name="token" />
        <.input type="hidden" field={@form[:locale]} />
        <div type="hidden" name="user_id"></div>
        <input type="hidden" name={@field} />
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(HiddenIdInput)
    |> refute_issues()
  end

  test "allowed_fields accepts named fields" do
    ~S'''
    defmodule MyAppWeb.Form do
      def form(assigns), do: ~H"<input type='hidden' name='locale_id'/><input type='hidden' name='user_id'/>"
    end
    '''
    |> to_source_file()
    |> run_check(HiddenIdInput, allowed_fields: ["locale_id"])
    |> assert_issue(fn issue -> assert issue.message =~ "user_id" end)
  end

  test "ignores strings and non-HEEx code, and reads .heex files" do
    ~S'''
    defmodule MyApp.Mailer do
      def html, do: "<input type=\"hidden\" name=\"user_id\" />"
    end
    '''
    |> to_source_file()
    |> run_check(HiddenIdInput)
    |> refute_issues()

    ~s|<form>\n<input type="hidden" name="user_id"/>\n</form>|
    |> Credo.SourceFile.parse("lib/form.html.heex")
    |> run_check(HiddenIdInput)
    |> assert_issue(fn issue -> assert issue.line_no == 2 end)
  end

  test "ignores commented-out, script and text examples; reads real tags around them" do
    ~S'''
    defmodule MyAppWeb.Form do
      def form(assigns) do
        ~H"""
        <!-- <input type="hidden" name="user_id"> -->
        <%!-- <.input type="hidden" field={@form[:account_id]} /> --%>
        <script>f.innerHTML = '<input type="hidden" name="org_id">'</script>
        <p>Use <input type="hidden" name="x"> as in `type="hidden" name="team_id"`.</p>
        <input type="hidden" name="real_id">
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(HiddenIdInput)
    |> assert_issue(fn issue ->
      assert issue.line_no == 8
      assert issue.message =~ "real_id"
    end)
  end

  test "type must be the type attribute, any case; > inside a quoted value does not end the tag" do
    ~S'''
    defmodule MyAppWeb.Form do
      def form(assigns) do
        ~H"""
        <input data-type="hidden" name="a_id" type="text">
        <input type="hidden" title="a>b" name="b_id">
        <input type="HIDDEN" name="c_id">
        <input value={"x}"} type="hidden" name="d_id">
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(HiddenIdInput)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [5, 6, 7]

      assert Enum.map(
               issues,
               &(&1.message =~ "b_id" or &1.message =~ "c_id" or &1.message =~ "d_id")
             ) == [true, true, true]
    end)
  end

  test "name wins over the DOM id, so allowed_fields applies to the submitted field" do
    ~S'''
    defmodule MyAppWeb.Form do
      def form(assigns), do: ~H"<input type='hidden' id='x_id' name='locale_id'/>"
    end
    '''
    |> to_source_file()
    |> run_check(HiddenIdInput, allowed_fields: ["locale_id"])
    |> refute_issues()
  end

  test "ignores comments in standalone .heex files" do
    ~s|<form>\n<!-- <input type="hidden" name="user_id"/> -->\n</form>|
    |> Credo.SourceFile.parse("lib/form.html.heex")
    |> run_check(HiddenIdInput)
    |> refute_issues()
  end
end
