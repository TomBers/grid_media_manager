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

  test "converts Markdown to social text while preserving visible link destinations" do
    markdown = """
    # A useful heading

    A paragraph with **strong text**, *emphasis*, and <strong>HTML</strong>.

    > A quoted claim

    - First point
    - [Explore the grid](https://rationalgrid.ai/g/collective)

    | Claim | Confidence |
    | --- | --- |
    | Art matters | High |

    ```text
    A preserved fenced line
    ```

    <https://rationalgrid.ai/g/another-grid>
    """

    expected =
      [
        "A useful heading",
        "",
        "A paragraph with strong text, emphasis, and HTML.",
        "",
        "“A quoted claim”",
        "",
        "• First point",
        "",
        "• Explore the grid — https://rationalgrid.ai/g/collective",
        "",
        "• Claim: Art matters · Confidence: High",
        "",
        "A preserved fenced line",
        "",
        "https://rationalgrid.ai/g/another-grid"
      ]
      |> Enum.join("\n")

    assert Markdown.social_text(markdown) == expected
    assert Markdown.social_sections(markdown) == [expected]
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

  test "enforces the page limit when a single sentence is unusually long" do
    text =
      "A single sentence can contain enough subordinate clauses and descriptive language to overwhelm a social video frame even though it never reaches a full stop"

    pages = Markdown.paginate_blocks([%{type: :paragraph, text: text}], 60)
    page_texts = Enum.map(pages, &Markdown.readable_text/1)

    assert length(page_texts) == 3
    assert Enum.all?(page_texts, &(String.length(&1) <= 60))
    assert Enum.join(page_texts, " ") == text
  end

  test "does not split common abbreviations into broken reading beats" do
    text =
      "Professional fasters like Dr. Henry Tanner became global attractions. Their performances drew paying crowds."

    pages = Markdown.paginate_blocks([%{type: :paragraph, text: text}], 80)

    assert Enum.map(pages, &Markdown.readable_text/1) == [
             "Professional fasters like Dr. Henry Tanner became global attractions.",
             "Their performances drew paying crowds."
           ]
  end

  test "removes editorial scaffolding while retaining genuine lists" do
    blocks = [
      %{type: :list_item, marker: "•", text: "Category: Historical foundation"},
      %{
        type: :list_item,
        marker: "•",
        text: "The Non-Obvious Connection: Fasting became a public spectacle."
      },
      %{
        type: :list_item,
        marker: "•",
        text: "Question/Insight Opened: What did the audience reward?"
      },
      %{type: :list_item, marker: "•", text: "A genuine list item"}
    ]

    assert Markdown.presentation_blocks(blocks) == [
             %{
               type: :paragraph,
               role: :connection,
               text: "Fasting became a public spectacle."
             },
             %{
               type: :paragraph,
               role: :question,
               text: "What did the audience reward?"
             },
             %{type: :list_item, marker: "•", text: "A genuine list item"}
           ]
  end

  test "removes search-grounding references from presentation sections" do
    markdown = """
    # A grounded answer

    The evidence supports the main claim [1] and a second finding 【turn2search3†source】.

    - A useful implication for the audience.
    - Search query if you want studies: “recommender systems identity memory”
    - The Extended Mind — Clark & Chalmers (search query: "Clark Chalmers 1998")

    ## Further reading / references

    - First source
    - https://example.com/paper

    ## A final question

    What would change your mind?

    References: This trailing bibliography should also disappear.
    """

    sections = Markdown.presentation_sections(markdown)

    assert Enum.map(sections, & &1.title) == ["A grounded answer", "A final question"]

    assert Enum.at(sections, 0).text ==
             "The evidence supports the main claim and a second finding.\n\n• A useful implication for the audience."

    assert Enum.at(sections, 1).text == "What would change your mind?"
  end

  test "recognises reference labels authored as list items or trailing prose" do
    assert [%{text: "A useful conclusion."}] =
             Markdown.presentation_sections("""
             A useful conclusion. References: First source; second source.
             """)

    assert [%{text: "A useful conclusion."}] =
             Markdown.presentation_sections("""
             A useful conclusion.

             - Further reading / references
             - First source
             - Second source
             """)
  end

  test "recovers a presentation title when node metadata contains references" do
    assert Markdown.presentation_title(
             "References: First source; second source",
             "Title: Why this question matters\n\nThe answer follows."
           ) == "Why this question matters"
  end

  test "builds clean longer-post text while retaining section structure" do
    assert Markdown.presentation_text("""
           # Main answer

           A grounded claim [1].

           ## Implication

           The useful consequence.

           ## Sources

           - https://example.com/source
           """) == "Main answer\n\nA grounded claim.\n\nImplication\n\nThe useful consequence."
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
