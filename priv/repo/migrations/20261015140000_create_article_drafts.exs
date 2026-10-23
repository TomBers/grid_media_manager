defmodule GridMediaManager.Repo.Migrations.CreateArticleDrafts do
  use Ecto.Migration

  def change do
    create table(:article_drafts) do
      add :slug, :string, null: false
      add :source_title, :string, null: false
      add :source_url, :text, null: false
      add :brief, :text, null: false, default: ""
      add :content, :map, null: false
      add :graph, :map, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:article_drafts, [:inserted_at])
  end
end
