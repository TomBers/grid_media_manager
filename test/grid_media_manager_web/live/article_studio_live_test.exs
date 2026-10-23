defmodule GridMediaManagerWeb.ArticleStudioLiveTest do
  use GridMediaManagerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias GridMediaManager.Articles
  alias GridMediaManager.Articles.Draft
  alias GridMediaManager.Repo

  test "opens the Borges example and validates blank submissions without a generation request", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/articles")
    assert has_element?(view, "#article-form input[value*='borges-and-infinity']")
    assert has_element?(view, "#article-empty")
    view |> form("#article-form", article: %{source: "", brief: ""}) |> render_submit()
    assert has_element?(view, "#article-form .text-error")
    refute has_element?(view, "#article-progress")
  end

  test "saved drafts reopen with section jumps and correct node URLs", %{conn: conn} do
    draft = draft()
    {:ok, view, _} = live(conn, "/articles/#{draft.id}")

    assert has_element?(view, "#article-preview")
    assert has_element?(view, "#article-map a[href='#sections-1']")
    assert has_element?(view, "#sections-1 a[href='https://rationalgrid.ai/g/test-grid?node=2']")
    assert has_element?(view, "#download-article[href='/articles/#{draft.id}/download']")
    assert has_element?(view, "#article-markdown")
    assert has_element?(view, "#copy-for-substack")
    assert has_element?(view, "#copy-article-title[data-copy-text='An essay']")

    assert has_element?(
             view,
             "#download-article-html[href='/articles/#{draft.id}/download?format=html']"
           )

    assert has_element?(view, "#article-copy-content")
    assert has_element?(view, "#drafts-#{draft.id}")
    refute has_element?(view, "#article-empty")
    assert has_element?(view, "#legacy-article-notice")
  end

  test "original passages show highlight provenance and preserve the source in export", %{
    conn: conn
  } do
    {:ok, graph} =
      Articles.prepare_graph(%{
        "metadata" => %{"title" => "A source title"},
        "graph" => %{
          "nodes" => [
            %{
              "id" => "1",
              "class" => "answer",
              "content" =>
                "# Source heading\n\nAn original **highlighted** paragraph.\n\n## A source subheading\n\nThe next original paragraph."
            }
          ]
        },
        "highlights" => [
          %{"id" => 12, "node_id" => "1", "text" => "highlighted", "note" => "Useful direction"}
        ]
      })

    {:ok, content} =
      GridMediaManager.Articles.Source.assemble(
        %{"sections" => [%{"node_ids" => ["1"], "passage_ids" => ["1:1", "1:2"]}]},
        graph
      )

    draft =
      %Draft{}
      |> Draft.changeset(%{
        slug: "original-grid",
        source_title: "A source title",
        source_url: "https://rationalgrid.ai/g/original-grid",
        content: content,
        graph: graph
      })
      |> Repo.insert!()

    {:ok, view, _} = live(conn, "/articles/#{draft.id}")
    assert has_element?(view, "#article-source-method", "1 of 1 grid highlights")

    assert has_element?(
             view,
             "#sections-1 [data-passage-id='1:1']",
             "An original highlighted paragraph."
           )

    assert has_element?(view, "#highlights-12", "Included in this selection")
    assert has_element?(view, "#highlights-12", "Useful direction")
    assert has_element?(view, "#sections-1 [data-passage-id='1:2'] h4", "A source subheading")
    refute has_element?(view, "#sections-1 [data-passage-id='1:1'] h4")
    refute has_element?(view, "#legacy-article-notice")
    assert Articles.markdown(draft) =~ "An original **highlighted** paragraph."
    refute has_element?(view, "#article-sections [data-passage-id] a")
    refute has_element?(view, "#article-sections", "Contains a grid highlight")
    refute has_element?(view, "#article-sections", "[…]")
  end

  test "exports the saved essay with deep links as a Markdown attachment", %{conn: conn} do
    draft = draft()
    conn = get(conn, "/articles/#{draft.id}/download")
    assert response(conn, 200) == Articles.markdown(draft)

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="test-grid-article.md")
           ]

    assert Articles.markdown(draft) =~
             "[Explore this thread in the grid](https://rationalgrid.ai/g/test-grid?node=2)"
  end

  test "missing articles redirect and missing downloads return 404", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/articles"}}} = live(conn, "/articles/not-an-id")
    assert conn |> get("/articles/not-an-id/download") |> response(404)
    assert conn |> get("/articles/not-an-id/document") |> response(404)
    assert conn |> get("/articles/not-an-id/download?format=html") |> response(404)
  end

  test "serves a standalone document and downloadable HTML", %{conn: conn} do
    draft = draft()
    preview = get(conn, "/articles/#{draft.id}/document")
    document = preview |> html_response(200) |> LazyHTML.from_document()
    assert LazyHTML.query(document, "article h1") |> LazyHTML.text() == "An essay"
    assert LazyHTML.query(document, "article h2") |> Enum.count() == 2
    assert LazyHTML.query(document, "button, nav, aside, script") |> Enum.count() == 0

    download = get(conn, "/articles/#{draft.id}/download?format=html")
    assert response(download, 200) == GridMediaManager.Articles.HTML.document(draft)

    assert get_resp_header(download, "content-disposition") == [
             ~s(attachment; filename="test-grid-article.html")
           ]
  end

  defp draft do
    %Draft{}
    |> Draft.changeset(%{
      slug: "test-grid",
      source_title: "Test grid",
      source_url: "https://rationalgrid.ai/g/test-grid",
      content: %{
        "title" => "An essay",
        "subtitle" => "A map of a question",
        "introduction" => "The beginning.",
        "conclusion" => "An open question.",
        "sections" => [
          %{
            "title" => "A different direction",
            "summary" => "An objection changes the question.",
            "relationship" => "Objection",
            "body" => "The argument.\n\nIts implications.",
            "node_ids" => ["1", "2"]
          }
        ]
      },
      graph: %{
        "nodes" => [
          %{"id" => "1", "content" => "Opening", "class" => "origin"},
          %{"id" => "2", "content" => "Objection", "class" => "antithesis"}
        ],
        "edges" => [%{"source" => "1", "target" => "2"}]
      }
    })
    |> Repo.insert!()
  end
end
