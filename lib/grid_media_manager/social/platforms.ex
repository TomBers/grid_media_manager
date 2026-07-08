defmodule GridMediaManager.Social.Platforms do
  @moduledoc """
  Platform metadata for draft generation and UI constraints.
  """

  @platforms [
    %{id: "x", label: "X", max_chars: 280, style: "Short, curious, and link-forward"},
    %{id: "bluesky", label: "Bluesky", max_chars: 300, style: "Conversational and question-led"},
    %{
      id: "linkedin",
      label: "LinkedIn",
      max_chars: 3_000,
      style: "Professional educational framing"
    },
    %{
      id: "instagram",
      label: "Instagram",
      max_chars: 2_200,
      style: "Caption-first and image-led"
    },
    %{id: "substack", label: "Substack", max_chars: nil, style: "Newsletter intro or note"}
  ]

  def all, do: @platforms

  def ids, do: Enum.map(@platforms, & &1.id)

  def get(id) when is_binary(id), do: Enum.find(@platforms, &(&1.id == id))

  def label(id) do
    case get(id) do
      %{label: label} -> label
      _ -> String.capitalize(to_string(id))
    end
  end

  def max_chars(id) do
    case get(id) do
      %{max_chars: max_chars} -> max_chars
      _ -> nil
    end
  end
end
