defmodule GridMediaManager.Repo.Migrations.CreateWeeklyRuns do
  use Ecto.Migration

  def change do
    create table(:weekly_runs) do
      add :status, :string, null: false, default: "analysing"
      add :theme, :text, null: false
      add :start_date, :date, null: false
      add :end_date, :date, null: false
      add :batch_id, references(:editorial_batches)
      add :evidence, :map, null: false, default: %{}
      add :quotas, :map, null: false, default: %{}
      add :windows, :map, null: false, default: %{}
      add :story_count, :integer, null: false, default: 0
      add :error, :text
      add :attempts, :integer, null: false, default: 0
      add :next_run_at, :utc_datetime
      add :lease_until, :utc_datetime
      add :lease_token, :uuid
      timestamps(type: :utc_datetime)
    end

    create unique_index(:weekly_runs, ["(true)"],
             name: :one_active_weekly_run,
             where: "status NOT IN ('completed', 'cancelled')"
           )

    create table(:weekly_stories) do
      add :run_id, references(:weekly_runs, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :question, :text, null: false
      add :rationale, :text, null: false
      add :exploration_id, references(:grid_explorations)
      add :plan_id, references(:editorial_plans)
      add :status, :string, null: false, default: "proposed"
      add :copy, :map, null: false, default: %{}
      add :copy_fingerprint, :string
      add :review, :map, null: false, default: %{}
      add :public, :boolean, null: false, default: false
      add :error, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:weekly_stories, [:run_id, :position])

    create table(:weekly_deliveries) do
      add :run_id, references(:weekly_runs, on_delete: :delete_all), null: false
      add :story_id, references(:weekly_stories), null: false
      add :post_draft_id, references(:post_drafts), null: false
      add :platform, :string, null: false
      add :scheduled_for, :utc_datetime, null: false
      add :window, :string, null: false
      add :status, :string, null: false, default: "prepared"
      add :body_hash, :string, null: false
      add :external_post_id, :string
      add :attempted_at, :utc_datetime
      add :checks, :integer, null: false, default: 0
      add :error, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:weekly_deliveries, [:run_id, :post_draft_id])
    create unique_index(:weekly_deliveries, [:run_id, :platform, :scheduled_for])
  end
end
