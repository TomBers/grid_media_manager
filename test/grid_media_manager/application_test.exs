defmodule GridMediaManager.ApplicationTest do
  use ExUnit.Case, async: false

  alias GridMediaManager.Application

  @environment_variables [
    "RATIONAL_GRID_BASE_URL",
    "PUBLIC_BASE_URL",
    "RATIONALGRID_PROMOTION_API_TOKEN",
    "BUFFER_API_KEY",
    "PEXELS_API_KEY"
  ]

  setup do
    previous_values = Map.new(@environment_variables, &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(previous_values, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  test "summarizes launch environment without exposing secrets" do
    System.put_env("RATIONAL_GRID_BASE_URL", "http://localhost:4000")
    System.put_env("PUBLIC_BASE_URL", "https://studio.example.com")
    System.put_env("RATIONALGRID_PROMOTION_API_TOKEN", "rational-secret-1234")
    System.put_env("BUFFER_API_KEY", "buffer-secret-5678")
    System.put_env("PEXELS_API_KEY", "pexels-secret-9012")

    summary = Application.environment_summary()

    assert summary =~ "RATIONAL_GRID_BASE_URL=http://localhost:4000"
    assert summary =~ "PUBLIC_BASE_URL=https://studio.example.com"
    assert summary =~ "RATIONALGRID_PROMOTION_API_TOKEN=set (20 chars, ending …1234)"
    assert summary =~ "BUFFER_API_KEY=set (18 chars, ending …5678)"
    assert summary =~ "PEXELS_API_KEY=set (18 chars, ending …9012)"

    refute summary =~ "rational-secret-1234"
    refute summary =~ "buffer-secret-5678"
    refute summary =~ "pexels-secret-9012"
  end

  test "reports missing values" do
    Enum.each(@environment_variables, &System.delete_env/1)

    summary = Application.environment_summary()

    assert summary =~ "RATIONAL_GRID_BASE_URL=not set"
    assert summary =~ "PUBLIC_BASE_URL=not set"
    assert summary =~ "RATIONALGRID_PROMOTION_API_TOKEN=not set"
    assert summary =~ "BUFFER_API_KEY=not set"
    assert summary =~ "PEXELS_API_KEY=not set"
  end
end
