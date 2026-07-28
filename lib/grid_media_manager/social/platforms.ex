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
      id: "facebook",
      label: "Facebook",
      max_chars: 63_206,
      style: "Readable, conversational context"
    },
    %{
      id: "instagram",
      label: "Instagram",
      max_chars: 2_200,
      style: "Caption-first and image-led"
    },
    %{
      id: "youtube",
      label: "YouTube Shorts",
      max_chars: 5_000,
      style: "Searchable title, concise context, and a clear invitation"
    },
    %{
      id: "tiktok",
      label: "TikTok",
      max_chars: 2_200,
      style: "Fast hook, clear premise, and a conversational caption"
    },
    %{id: "substack", label: "Substack", max_chars: nil, style: "Newsletter intro or note"}
  ]

  @text_ids ["x", "linkedin", "facebook"]
  @video_ids ["tiktok", "instagram", "youtube"]
  @supported_ids @text_ids ++ @video_ids

  def all, do: Enum.map(@supported_ids, &get/1)

  def ids, do: @supported_ids

  def text_ids, do: @text_ids

  def long_form_ids, do: ["linkedin", "facebook"]

  def video_ids, do: @video_ids

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

  @doc "Returns the platform-visible character count for social copy."
  def character_count(text, "x") when is_binary(text) do
    text
    |> String.replace(~r/(^|\s)#[\p{L}\p{N}_]+/u, "\\1")
    |> String.length()
  end

  def character_count(text, _platform) when is_binary(text), do: String.length(text)
  def character_count(_text, _platform), do: 0

  def within_limit?(text, platform) do
    case max_chars(platform) do
      limit when is_integer(limit) -> character_count(text, platform) <= limit
      nil -> true
    end
  end
end
