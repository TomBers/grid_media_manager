defmodule GridMediaManager.RationalGrid.Connection do
  use Ecto.Schema

  schema "rational_grid_connections" do
    field :key, :string
    field :client_id, :string
    field :credentials, :string, redact: true
    field :expires_at, :utc_datetime
    field :status, :string, default: "disconnected"
    timestamps(type: :utc_datetime)
  end
end
