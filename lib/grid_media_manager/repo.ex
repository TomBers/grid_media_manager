defmodule GridMediaManager.Repo do
  use Ecto.Repo,
    otp_app: :grid_media_manager,
    adapter: Ecto.Adapters.Postgres
end
