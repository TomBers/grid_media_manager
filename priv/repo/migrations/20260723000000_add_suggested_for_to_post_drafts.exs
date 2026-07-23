defmodule GridMediaManager.Repo.Migrations.AddSuggestedForToPostDrafts do
  use Ecto.Migration

  def change do
    alter table(:post_drafts) do
      add :suggested_for, :utc_datetime
    end
  end
end
