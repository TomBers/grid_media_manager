defmodule GridMediaManager.Repo.Migrations.CreateEditorialBatchesAndPlans do
  use Ecto.Migration

  def change do
    create table(:editorial_batches) do
      add :topics, {:array, :string}, null: false, default: []
      add :status, :string, null: false, default: "pending"
      add :model, :string
      add :error_message, :text

      timestamps(type: :utc_datetime)
    end

    create index(:editorial_batches, [:status])

    create table(:editorial_plans) do
      add :editorial_batch_id, references(:editorial_batches, on_delete: :delete_all), null: false

      add :campaign_id, references(:campaigns, on_delete: :nilify_all)
      add :position, :integer, null: false
      add :topic, :string, null: false
      add :source_slug, :string
      add :source_title, :string
      add :selected_keys, {:array, :string}, null: false, default: []
      add :hook, :text
      add :rationale, :text
      add :confidence, :float
      add :status, :string, null: false, default: "planned"
      add :error_message, :text
      add :selection_details, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:editorial_plans, [:campaign_id])
    create unique_index(:editorial_plans, [:editorial_batch_id, :position])
  end
end
