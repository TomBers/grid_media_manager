defmodule GridMediaManager.Weekly.Validation do
  @moduledoc "Blocking production checks, separate from optional editorial taste."
  alias GridMediaManager.Promotion.ShortVideo
  @fields ~w(x linkedin facebook instagram tiktok youtube hook idea_card cover_search_query)
  def normalise(copy) do
    Map.new(copy, fn {key, value} ->
      value =
        if is_binary(value) do
          value
          |> then(fn text ->
            Regex.replace(
              ~r/(^|[.!?]\s+|\n\s*)(?:quick hook|hook|premise|question|tension|reasoning|qualification|focused question|example):[ \t]*(.)/imu,
              text,
              fn _, prefix, first -> prefix <> String.upcase(first) end
            )
          end)
          |> String.trim()
        else
          value
        end

      {key, value}
    end)
  end

  def copy_issues(copy, theme) do
    field = fn key -> if is_binary(copy[key]), do: copy[key], else: "" end
    script = if is_list(copy["video_script"]), do: copy["video_script"], else: []

    missing =
      for f <- @fields, not is_binary(copy[f]) or String.trim(copy[f]) == "", do: "Missing #{f}."

    text = @fields |> Enum.map(field) |> Enum.join("\n")

    missing ++
      issue(
        not ShortVideo.valid_script?(copy["video_script"]),
        "Video needs three complete beats of at most 22 words."
      ) ++
      issue(length(script) != 3, "Video must have three beats.") ++
      issue(ShortVideo.word_count(field.("hook")) > 12, "Cover hook exceeds 12 words.") ++
      issue(ShortVideo.word_count(field.("idea_card")) > 22, "Idea card exceeds 22 words.") ++
      issue(
        Regex.match?(
          ~r/(?:^|[.!?]\s+)(?:quick hook|hook|premise|question|tension|reasoning|qualification|focused question|example):/im,
          text
        ),
        "Remove drafting labels."
      ) ++
      issue(
        Regex.match?(~r/[\x{4E00}-\x{9FFF}\x{FFFD}\x00]/u, text),
        "Unexpected or corrupted text in English copy."
      ) ++
      issue(
        excludes_ai?(theme) and
          Regex.match?(
            ~r/\b(?:AI|artificial intelligence|LLMs?)\b/i,
            text <> (script |> Enum.filter(&is_binary/1) |> Enum.join(" "))
          ),
        "Copy violates the exclusion of AI topics."
      ) ++
      issue(
        String.length(field.("linkedin")) < 500,
        "LinkedIn needs a substantive standalone explanation."
      ) ++
      issue(
        String.length(field.("facebook")) < 400,
        "Facebook needs a substantive standalone explanation."
      )
  end

  def hash(value),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(value)) |> Base.encode16(case: :lower)

  defp excludes_ai?(theme),
    do:
      Regex.match?(
        ~r/(?:unrelated to|without|exclude|not about|no) (?:AI|artificial intelligence)/i,
        theme
      )

  defp issue(true, message), do: [message]
  defp issue(false, _), do: []
end
