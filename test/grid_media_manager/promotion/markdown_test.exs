defmodule GridMediaManager.Promotion.MarkdownTest do
  use ExUnit.Case, async: true

  alias GridMediaManager.Promotion.Markdown

  test "preserves useful block structure while cleaning inline Markdown" do
    markdown = """
    # A structured answer

    An opening paragraph with **strong language**, *emphasis*, and a [source](https://example.com).

    ## Competing views

    > A quoted claim with a [citation](https://example.com/source).
    > — An author

    - **The Hero:** A recurring pattern.
    - The Shadow

    1. First objection
    2. Second objection
    """

    assert [
             %{type: :heading, level: 1, text: "A structured answer"},
             %{
               type: :paragraph,
               text: "An opening paragraph with strong language, emphasis, and a source."
             },
             %{type: :heading, level: 2, text: "Competing views"},
             %{
               type: :blockquote,
               text: "A quoted claim with a citation. — An author"
             },
             %{type: :list_item, marker: "•", text: "The Hero: A recurring pattern."},
             %{type: :list_item, marker: "•", text: "The Shadow"},
             %{type: :list_item, marker: "1.", text: "First objection"},
             %{type: :list_item, marker: "2.", text: "Second objection"}
           ] = Markdown.blocks(markdown)
  end

  test "paginates long blocks only at complete sentence boundaries" do
    text =
      "First complete thought. Second complete thought. Third complete thought. Fourth complete thought."

    pages = Markdown.paginate_blocks([%{type: :paragraph, text: text}], 55)
    page_texts = Enum.map(pages, &Markdown.readable_text/1)

    assert length(page_texts) > 1
    assert Enum.all?(page_texts, &String.ends_with?(&1, "."))
    assert Enum.join(page_texts, " ") == text
  end

  test "groups Markdown into carousel-ready sections" do
    sections =
      Markdown.sections("""
      # Main answer

      Opening context.

      ## Evidence

      - First source
      - Second source

      ## A challenge

      > What would falsify this claim?
      """)

    assert Enum.map(sections, & &1.title) == ["Main answer", "Evidence", "A challenge"]
    assert Enum.at(sections, 1).text == "• First source\n\n• Second source"
    assert Enum.at(sections, 2).text == "“What would falsify this claim?”"
  end
end
