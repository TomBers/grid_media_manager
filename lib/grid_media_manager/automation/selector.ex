defmodule GridMediaManager.Automation.Selector do
  @moduledoc false

  @callback select_topics(pos_integer(), String.t() | nil, [map()]) ::
              {:ok, map()} | {:error, term()}
  @callback select_grid(String.t(), [map()]) :: {:ok, map()} | {:error, term()}
  @callback select_story(String.t(), struct(), [map()]) :: {:ok, map()} | {:error, term()}
  @callback select_cover(String.t(), String.t(), String.t(), [map()]) ::
              {:ok, map()} | {:error, term()}
end
