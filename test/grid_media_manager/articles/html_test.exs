defmodule GridMediaManager.Articles.HTMLTest do
  use ExUnit.Case, async: true
  alias GridMediaManager.Articles.HTML

  test "preserves supported formatting as semantic HTML" do
    html =
      HTML.markdown("""
      ## A heading

      A **strong** idea, *emphasis*, and a [source](https://example.org/a?x=1&y=2).

      - **First:** an idea
      - Second

      3. Third
      4. Fourth

      > A quotation
      > continues here.
      """)

    document = LazyHTML.from_fragment(html)
    assert LazyHTML.query(document, "h2") |> LazyHTML.text() == "A heading"
    assert LazyHTML.query(document, "strong") |> Enum.count() == 2
    assert LazyHTML.query(document, "em") |> LazyHTML.text() == "emphasis"
    assert LazyHTML.query(document, "ul > li") |> Enum.count() == 2
    assert LazyHTML.query(document, "ol[start='3'] > li") |> Enum.count() == 2

    assert LazyHTML.query(document, "blockquote p") |> LazyHTML.text() ==
             "A quotation continues here."

    assert LazyHTML.query(document, "a[href='https://example.org/a?x=1&y=2']") |> Enum.count() ==
             1
  end

  test "escapes source HTML, rejects executable links, and preserves unmatched punctuation" do
    html =
      HTML.markdown("""
      <script>alert('x')</script>

      [bad](javascript:alert) [data](data:text/html,evil) **unclosed and _unfinished

      `x < y` and <img src=x onerror=alert(1)>
      """)

    document = LazyHTML.from_fragment(html)
    assert LazyHTML.query(document, "script, img, a, strong, em") |> Enum.count() == 0
    assert LazyHTML.text(document) =~ "**unclosed and _unfinished"
    assert LazyHTML.query(document, "code") |> LazyHTML.text() == "x < y"
  end

  test "exports uninterrupted article content with a single section link" do
    html = HTML.body(draft())
    document = LazyHTML.from_fragment(html)
    assert LazyHTML.query(document, "h1, button, aside, script, style") |> Enum.count() == 0
    assert LazyHTML.query(document, "h2") |> LazyHTML.text() == "A direction"
    assert LazyHTML.query(document, "p strong") |> LazyHTML.text() == "original"

    assert LazyHTML.query(document, "a[href='https://rationalgrid.ai/g/example?node=2']")
           |> Enum.count() == 1

    refute LazyHTML.text(document) =~ "[…]"
    refute LazyHTML.text(document) =~ "Contains a grid highlight"

    full = HTML.document(draft()) |> LazyHTML.from_document()
    assert LazyHTML.query(full, "title") |> LazyHTML.text() == "Title <with> characters"
    assert LazyHTML.query(full, "article h1") |> LazyHTML.text() == "Title <with> characters"
    assert LazyHTML.query(full, "article with, script") |> Enum.count() == 0
  end

  test "reading links exclude shared ancestors and repeated contributing nodes" do
    draft = draft()
    [section] = draft.content["sections"]
    [passage] = section["passages"]

    first = %{
      section
      | "node_ids" => ["1", "2"],
        "passages" => [passage, %{passage | "text" => "Another paragraph."}]
    }

    second = %{
      section
      | "node_ids" => ["1", "2", "3"],
        "passages" => [passage, %{passage | "node_id" => "3", "text" => "A new direction."}]
    }

    draft = put_in(draft, [:content, "sections"], [first, second])
    document = draft |> HTML.body() |> LazyHTML.from_fragment()
    assert LazyHTML.query(document, "a[href$='?node=1']") |> Enum.count() == 0
    assert LazyHTML.query(document, "a[href$='?node=2']") |> Enum.count() == 1
    assert LazyHTML.query(document, "a[href$='?node=3']") |> Enum.count() == 1
    assert LazyHTML.text(document) =~ "Another paragraph."
    assert LazyHTML.text(document) =~ "A new direction."
    refute LazyHTML.text(document) =~ "Follow this path"
  end

  test "restores source subheadings once per run in HTML and Markdown without changing prose" do
    draft = draft()
    [section] = draft.content["sections"]
    [passage] = section["passages"]

    passages = [
      Map.merge(passage, %{"heading" => "A direction", "text" => "Opening paragraph."}),
      Map.merge(passage, %{"heading" => "A **source** subheading", "text" => "First paragraph."}),
      Map.merge(passage, %{"heading" => "A **source** subheading", "text" => "Second paragraph."}),
      Map.merge(passage, %{"heading" => "Another direction", "text" => "> Original quotation."}),
      Map.merge(passage, %{"heading" => nil, "text" => "Closing paragraph."})
    ]

    draft = put_in(draft, [:content, "sections"], [%{section | "passages" => passages}])

    for html <- [HTML.body(draft), HTML.document(draft)] do
      document = LazyHTML.from_fragment(html)
      assert LazyHTML.query(document, "h2") |> Enum.count() == 1
      assert LazyHTML.query(document, "h3") |> Enum.count() == 2
      assert LazyHTML.query(document, "h3 strong") |> LazyHTML.text() == "source"
      assert LazyHTML.query(document, "blockquote p") |> LazyHTML.text() == "Original quotation."
      assert LazyHTML.text(document) =~ "First paragraph."
      assert LazyHTML.text(document) =~ "Second paragraph."
    end

    markdown = GridMediaManager.Articles.markdown(draft)
    assert length(String.split(markdown, "### A **source** subheading")) == 2
    refute markdown =~ "### A direction"
  end

  test "source subheadings escape HTML and unsafe links" do
    html =
      HTML.passage(%{
        "text" => "Original.",
        :reading_heading => "<img src=x> [bad](javascript:evil)"
      })

    document = LazyHTML.from_fragment(html)
    assert LazyHTML.query(document, "h3") |> LazyHTML.text() == "<img src=x> bad"
    assert LazyHTML.query(document, "img, a") |> Enum.count() == 0
  end

  defp draft do
    %{
      source_title: "Source",
      source_url: "https://rationalgrid.ai/g/example",
      content: %{
        "title" => "Title <with> characters",
        "subtitle" => "An existing subtitle",
        "mode" => "source_passages",
        "sections" => [
          %{
            "title" => "A direction",
            "node_ids" => ["2"],
            "passages" => [
              %{
                "text" => "An **original** paragraph.",
                "omitted_before" => true,
                "node_id" => "2",
                "highlight_ids" => ["1"]
              }
            ]
          }
        ]
      }
    }
  end
end
