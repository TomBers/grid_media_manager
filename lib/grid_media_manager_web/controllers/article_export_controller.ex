defmodule GridMediaManagerWeb.ArticleExportController do
  use GridMediaManagerWeb, :controller
  alias GridMediaManager.Articles

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
