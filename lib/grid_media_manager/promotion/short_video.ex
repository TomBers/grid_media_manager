defmodule GridMediaManager.Promotion.ShortVideo do
  @moduledoc "Editorial pacing checks shared by generation, review, and publishing."

  alias GridMediaManager.Promotion.CarouselVideo

  def word_count(text), do: text |> to_string() |> String.split(~r/\s+/u, trim: true) |> length()

  def visible_words(slide) do
    keys =
      if slide["kind"] in ["quote", "highlight"], do: ~w(label title), else: ~w(label title body)

    slide |> Map.take(keys) |> Map.values() |> Enum.join(" ") |> word_count()
  end

  def script_slides(script) when is_list(script) do
    script
    |> Enum.with_index(1)
    |> Enum.map(fn {text, index} ->
      %{
        "kind" => "node_text",
        "label" => "#{index} / #{length(script)}",
        "title" => "",
        "body" => text
      }
    end)
  end

  def valid_script?(script) when is_list(script) and length(script) in 2..4 do
    Enum.all?(script, &(is_binary(&1) and String.trim(&1) != "" and word_count(&1) <= 22))
  end

  def valid_script?(_), do: false

  def issues(slides) when is_list(slides) do
    density =
      slides
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {slide, index} ->
        if slide["kind"] != "cta" and visible_words(slide) > 25,
          do: ["Frame #{index} has #{visible_words(slide)} words; edit it to 25 or fewer."],
          else: []
      end)

    duration = slides |> CarouselVideo.slide_durations() |> CarouselVideo.duration_seconds()

    density ++
      if(length(slides) in 4..6,
        do: [],
        else: ["Use 4–6 frames, including the opening and closing."]
      ) ++
      if(duration <= 45,
        do: [],
        else: ["This video runs for #{duration}s; shorten it to 45s or less."]
      )
  end

  def validate_asset(%{mime_type: "video/mp4", metadata: metadata}) do
    slides = Map.get(metadata || %{}, "slides", [])

    indexes =
      Map.get(metadata || %{}, "selected_slide_indexes") ||
        Enum.to_list(1..max(length(slides), 1))

    selected = Enum.map(indexes, &Enum.at(slides, &1 - 1)) |> Enum.reject(&is_nil/1)

    case issues(selected) do
      [] -> :ok
      issues -> {:error, "Video needs a pacing edit: " <> Enum.join(issues, " ")}
    end
  end

  def validate_asset(_), do: :ok
end
