defmodule GridMediaManagerWeb.ArticleExportController do
  use GridMediaManagerWeb, :controller
  alias GridMediaManager.Articles
  alias GridMediaManager.Articles.HTML

  def document(conn, %{"id" => id}) do
    case Articles.get_draft(id) do
      nil -> send_resp(conn, :not_found, "Article not found")
      draft -> conn |> put_resp_content_type("text/html") |> send_resp(:ok, HTML.document(draft))
    end
  end

  def download(conn, %{"id" => id, "format" => "html"}) do
    case Articles.get_draft(id) do
      nil ->
        send_resp(conn, :not_found, "Article not found")

      draft ->
        send_download(conn, {:binary, HTML.document(draft)},
          filename: "#{draft.slug}-article.html",
          content_type: "text/html"
        )
    end
  end

  def download(conn, %{"id" => id}) do
    case Articles.get_draft(id) do
      nil ->
        send_resp(conn, :not_found, "Article not found")

      draft ->
        send_download(conn, {:binary, Articles.markdown(draft)},
          filename: "#{draft.slug}-article.md",
          content_type: "text/markdown"
        )
    end
  end
end
