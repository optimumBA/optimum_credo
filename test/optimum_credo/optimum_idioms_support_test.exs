defmodule OptimumCredo.OptimumIdiomsSupportTest do
  use ExUnit.Case, async: true

  alias OptimumCredo.OptimumIdiomsSupport

  defp heex(text), do: Credo.SourceFile.parse(text, "lib/page.html.heex")

  defp tags(text) do
    text
    |> heex()
    |> OptimumIdiomsSupport.heex_tags()
  end

  describe "heex_tags/1" do
    test "reads quoted, single-quoted, expression, bare and valueless attributes with lines" do
      [tag] =
        tags(
          ~s|<div\n  class="a b"\n  id='x'\n  phx-click={JS.push("go")}\n  tabindex=3\n  hidden\n>|
        )

      assert tag.name == "div"
      assert tag.line == 1

      assert tag.attrs == [
               {"class", {:string, "a b"}, 2},
               {"id", {:string, "x"}, 3},
               {"phx-click", {:expr, ~s|JS.push("go")|}, 4},
               {"tabindex", {:bare, "3"}, 5},
               {"hidden", nil, 6}
             ]
    end

    test "braces may contain quoted braces and nested maps" do
      [tag] = tags(~s|<img src={"/a}b"} data={%{a: %{b: 1}}} alt="x">|)

      assert [
               {"src", {:expr, ~s|"/a}b"|}, 1},
               {"data", {:expr, "%{a: %{b: 1}}"}, 1},
               {"alt", {:string, "x"}, 1}
             ] =
               tag.attrs
    end

    test "components, slots and self-closing tags are tags; closing tags are not" do
      assert ~s|<.link href="/x"></.link><:inner_block/><Mod.comp a="1" />|
             |> tags()
             |> Enum.map(& &1.name) ==
               [".link", ":inner_block", "Mod.comp"]
    end

    test "comments, EEx tags, script/style bodies and body interpolation hide markup" do
      text = """
      <!-- <a href="/1"> -->
      <%!-- <a href="/2"> --%>
      <%# <a href="/3"> %>
      <%= "<a href='/4'>" %>
      <SCRIPT>if (a < b) { x = '<a href="/5">' }</SCRIPT>
      <style>a > b { content: "<a href='/6'>" }</style>
      {"<a href='/7'>"}
      <p>text <a href="/real">link</a></p>
      """

      assert text
             |> tags()
             |> Enum.map(& &1.name) == ["SCRIPT", "style", "p", "a"]

      tag =
        text
        |> tags()
        |> Enum.find(&(&1.name == "a"))

      assert tag.line == 8
    end

    test "unterminated constructs do not crash and do not invent tags" do
      for text <- [
            "<a href=\"/x",
            "<!-- <a href='/x'>",
            "<script><a href='/x'>",
            "{ <a href='/x'>",
            "<a {"
          ] do
        assert text
               |> tags()
               |> is_list()
      end

      assert tags("<!-- <a href='/x'>") == []
    end

    test "an unbalanced brace in text is treated as literal text" do
      assert "<p>{ unfinished</p><a href=\"/x\">"
             |> tags()
             |> Enum.map(& &1.name) == ["p", "a"]
    end

    test "~H sigils give tags with file line numbers" do
      source_file =
        Credo.SourceFile.parse(
          ~S'''
          defmodule A do
            def r(assigns) do
              ~H"""
              <div>
                <img src="/a.png">
              </div>
              """
            end
          end
          ''',
          "lib/a.ex"
        )

      assert [{"div", 4}, {"img", 5}] =
               source_file
               |> OptimumIdiomsSupport.heex_tags()
               |> Enum.map(&{&1.name, &1.line})
    end
  end

  describe "heex_visible_text/1" do
    test "blanks comments and raw bodies but keeps length and newlines" do
      text = "a<!-- QCOMMENT\nQ -->b<script>QRAW\nQ</script>e<%!-- QHEEX --%>f"

      [{visible, 1}] =
        text
        |> heex()
        |> OptimumIdiomsSupport.heex_visible_text()

      assert byte_size(visible) == byte_size(text)

      assert visible
             |> String.split("\n")
             |> length() == 3

      assert visible =~ "<script>"
      assert visible =~ "</script>"
      refute visible =~ "Q"
    end
  end

  describe "definition and path helpers" do
    test "without_definition_heads/1 removes heads and attributes only" do
      ast =
        Code.string_to_quoted!(
          "def send(pid, {:ok}), do: send(pid, {:ok})\n@spec send(pid, {:ok}) :: :ok"
        )

      text =
        ast
        |> OptimumIdiomsSupport.without_definition_heads()
        |> Macro.to_string()

      assert text =~ "send(pid, {:ok})"
      refute text =~ "@spec"
      refute text =~ "def send"
    end

    test "path_matches?/2 matches directory segments, not substrings" do
      assert OptimumIdiomsSupport.path_matches?("lib/a/test/b.ex", ["test/"])
      refute OptimumIdiomsSupport.path_matches?("lib/contest/b.ex", ["test/"])
      assert OptimumIdiomsSupport.path_matches?("lib/a_test.exs", ["_test.exs"])
    end
  end
end
