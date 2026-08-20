defmodule GridMediaManager.Repo.Migrations.ExtendEditorialAutopilot do
  use Ecto.Migration

  def change do
    alter table(:editorial_batches) do
      add :requested_count, :integer, null: false, default: 3
      add :theme, :string
    end

    alter table(:editorial_plans) do
      add :recommended_format, :string
      add :recommended_platforms, {:array, :string}, null: false, default: []
    end
  end
end
