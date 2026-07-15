defmodule GridMediaManager.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @public_environment_variables [
    "RATIONAL_GRID_BASE_URL",
    "PUBLIC_BASE_URL",
    "S3_BUCKET",
    "AWS_REGION",
    "S3_ENDPOINT",
    "S3_PUBLIC_BASE_URL",
    "BUFFER_YOUTUBE_CATEGORY_ID"
  ]

  @secret_environment_variables [
    "RATIONALGRID_PROMOTION_API_TOKEN",
    "BUFFER_API_KEY",
    "BUFFER_VIDEO_API_KEY",
    "BUFFER_TEXT_API_KEY",
    "PEXELS_API_KEY",
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_SESSION_TOKEN"
  ]

  @impl true
  def start(_type, _args) do
    Logger.info(environment_summary())

    children = [
      GridMediaManagerWeb.Telemetry,
      GridMediaManager.Repo,
      {DNSCluster,
       query: Application.get_env(:grid_media_manager, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: GridMediaManager.PubSub},
      # Start a worker by calling: GridMediaManager.Worker.start_link(arg)
      # {GridMediaManager.Worker, arg},
      # Start to serve requests, typically the last entry
      GridMediaManagerWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GridMediaManager.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc false
  def environment_summary do
    public_lines =
      Enum.map(@public_environment_variables, fn name ->
        "#{name}=#{environment_value(name)}"
      end)

    secret_lines =
      Enum.map(@secret_environment_variables, fn name ->
        "#{name}=#{secret_environment_value(name)}"
      end)

    lines = public_lines ++ secret_lines

    "Environment configuration:\n  " <> Enum.join(lines, "\n  ")
  end

  defp environment_value(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> value
      _value -> "not set"
    end
  end

  defp secret_environment_value(name) do
    case System.get_env(name) do
      value when is_binary(value) -> masked_secret(value)
      _value -> "not set"
    end
  end

  defp masked_secret(value) do
    value = String.trim(value)
    length = String.length(value)

    cond do
      length == 0 -> "not set"
      length <= 8 -> "set (#{length} chars)"
      true -> "set (#{length} chars, ending …#{String.slice(value, -4, 4)})"
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GridMediaManagerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
