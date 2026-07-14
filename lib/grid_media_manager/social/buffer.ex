defmodule GridMediaManager.Social.Buffer do
  @moduledoc """
  Focused client for scheduling campaign post drafts through Buffer's GraphQL API.

  Configure it under `:grid_media_manager, :buffer`:

      config :grid_media_manager, :buffer,
        api_key: "...",
        endpoint: "https://api.buffer.com"

  The endpoint defaults to `https://api.buffer.com`. A `:plug` option may be
  configured for `Req.Test` without allowing test requests onto the network.
  """

  alias GridMediaManager.Campaigns.PostDraft

  @default_endpoint "https://api.buffer.com"

  @create_post_mutation """
  mutation CreatePost($input: CreatePostInput!) {
    createPost(input: $input) {
      ... on PostActionSuccess {
        post {
          id
          status
          dueAt
        }
      }
      ... on MutationError {
        message
      }
    }
  }
  """

  @doc "Returns whether a non-blank Buffer API key is configured."
  def configured? do
    not is_nil(api_key())
  end

  @doc "Returns the configured Buffer channel ID for a social platform."
  def channel_id(platform) when is_binary(platform) do
    case config_value(:channels) do
      channels when is_map(channels) ->
        Map.get(channels, platform) || Map.get(channels, String.to_existing_atom(platform))

      channels when is_list(channels) ->
        Keyword.get(channels, String.to_existing_atom(platform))

      _other ->
        nil
    end
    |> string_value()
  rescue
    ArgumentError -> nil
  end

  def channel_id(_platform), do: nil

  @doc """
  Schedules a post draft for a Buffer channel.

  `opts` requires `:channel_id` and accepts `:media_url`, `:mime_type`, `:title`,
  `:instagram_type`, and `:youtube_category_id`. Media defaults to an image; a MIME type of `video/mp4`
  creates a video asset. Instagram images default to `post`, while videos
  default to `reel`. The draft's `scheduled_for` value is sent as Buffer's `dueAt`.
  """
  def schedule(%PostDraft{} = draft, opts) when is_list(opts) or is_map(opts) do
    with {:ok, key} <- configured_api_key(),
         {:ok, channel_id} <- required_string(option(opts, :channel_id), "channel_id is required"),
         {:ok, text} <- required_string(draft.body, "post draft body is required"),
         {:ok, due_at} <- due_at(draft.scheduled_for),
         {:ok, assets} <- assets(opts),
         {:ok, metadata} <- post_metadata(draft, opts) do
      input =
        %{
          "text" => text,
          "channelId" => channel_id,
          "schedulingType" => "automatic",
          "mode" => "customScheduled",
          "dueAt" => due_at,
          "assets" => assets
        }
        |> maybe_put_input("metadata", metadata)

      create_post(key, input)
    end
  end

  def schedule(%PostDraft{}, _opts), do: {:error, "options must be a keyword list or map"}
  def schedule(_draft, _opts), do: {:error, "post draft must be a PostDraft"}

  defp create_post(key, input) do
    request_options =
      [
        url: endpoint(),
        headers: [{"authorization", "Bearer #{key}"}],
        json: %{"query" => @create_post_mutation, "variables" => %{"input" => input}},
        receive_timeout: receive_timeout(),
        retry: false
      ]
      |> maybe_put(:plug, config_value(:plug))

    request_options
    |> Req.post()
    |> handle_response()
  end

  defp handle_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    body
    |> decode_body()
    |> parse_graphql_response()
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    case response_error_message(decode_body(body)) do
      nil -> {:error, "Buffer API request failed with HTTP status #{status}"}
      message -> {:error, "Buffer API request failed (HTTP #{status}): #{message}"}
    end
  end

  defp handle_response({:error, reason}) do
    {:error, "Buffer API request failed: #{request_error_message(reason)}"}
  end

  defp parse_graphql_response(%{"errors" => errors}) when is_list(errors) and errors != [] do
    {:error, "Buffer GraphQL error: #{join_error_messages(errors)}"}
  end

  defp parse_graphql_response(%{
         "data" => %{
           "createPost" => %{
             "post" => %{"id" => id, "status" => status} = post
           }
         }
       }) do
    {:ok, %{id: id, status: status, due_at: Map.get(post, "dueAt")}}
  end

  defp parse_graphql_response(%{
         "data" => %{"createPost" => %{"message" => message}}
       })
       when is_binary(message) do
    {:error, message}
  end

  defp parse_graphql_response(_body), do: {:error, "Buffer API returned an unexpected response"}

  defp assets(opts) do
    media_url = string_value(option(opts, :media_url))
    mime_type = string_value(option(opts, :mime_type))

    case {media_url, mime_type} do
      {nil, nil} ->
        {:ok, []}

      {nil, _mime_type} ->
        {:error, "media_url is required when mime_type is provided"}

      {url, nil} ->
        {:ok, [%{"image" => %{"url" => url}}]}

      {url, mime_type} ->
        asset_for_mime_type(url, String.downcase(mime_type))
    end
  end

  defp asset_for_mime_type(url, "video/mp4") do
    {:ok, [%{"video" => %{"url" => url}}]}
  end

  defp asset_for_mime_type(url, "image/" <> _subtype) do
    {:ok, [%{"image" => %{"url" => url}}]}
  end

  defp asset_for_mime_type(_url, mime_type) do
    {:error, "unsupported media MIME type: #{mime_type}; expected image/* or video/mp4"}
  end

  defp post_metadata(%PostDraft{platform: "instagram"}, opts) do
    mime_type = option(opts, :mime_type) |> string_value() |> to_string() |> String.downcase()
    requested_type = option(opts, :instagram_type) |> string_value()
    type = requested_type || if(mime_type == "video/mp4", do: "reel", else: "post")

    if type in ["post", "story", "reel"] do
      instagram_metadata =
        %{"type" => type}
        |> maybe_put_map("shouldShareToFeed", type == "reel" && true)

      {:ok, %{"instagram" => instagram_metadata}}
    else
      {:error, "instagram_type must be post, story, or reel"}
    end
  end

  defp post_metadata(%PostDraft{platform: "youtube"}, opts) do
    with {:ok, title} <- required_string(option(opts, :title), "YouTube title is required") do
      category_id =
        option(opts, :youtube_category_id)
        |> string_value()
        |> fallback_youtube_category_id()

      {:ok,
       %{
         "youtube" => %{
           "title" => fit_youtube_title(title),
           "categoryId" => category_id
         }
       }}
    end
  end

  defp post_metadata(%PostDraft{}, _opts), do: {:ok, nil}

  defp fallback_youtube_category_id(nil) do
    System.get_env("BUFFER_YOUTUBE_CATEGORY_ID")
    |> string_value()
    |> case do
      nil -> config_value(:youtube_category_id) |> string_value() || "27"
      category_id -> category_id
    end
  end

  defp fallback_youtube_category_id(category_id), do: category_id

  defp fit_youtube_title(title) do
    if String.length(title) <= 100, do: title, else: "RationalGrid video"
  end

  defp due_at(%DateTime{} = scheduled_for), do: {:ok, DateTime.to_iso8601(scheduled_for)}

  defp due_at(_scheduled_for) do
    {:error, "post draft scheduled_for must be a UTC DateTime"}
  end

  defp configured_api_key do
    case api_key() do
      nil -> {:error, "Buffer is not configured; set :grid_media_manager, :buffer, :api_key"}
      key -> {:ok, key}
    end
  end

  defp api_key do
    config_value(:api_key)
    |> string_value()
  end

  defp endpoint do
    config_value(:endpoint)
    |> string_value()
    |> case do
      nil -> @default_endpoint
      configured_endpoint -> configured_endpoint
    end
  end

  defp receive_timeout do
    case config_value(:receive_timeout) do
      timeout when is_integer(timeout) and timeout >= 0 -> timeout
      _other -> 15_000
    end
  end

  defp config_value(key) do
    case Application.get_env(:grid_media_manager, :buffer, []) do
      config when is_list(config) -> Keyword.get(config, key)
      config when is_map(config) -> Map.get(config, key)
      _other -> nil
    end
  end

  defp option(opts, key) when is_list(opts), do: Keyword.get(opts, key)

  defp option(opts, key) when is_map(opts) do
    Map.get(opts, key) || Map.get(opts, Atom.to_string(key))
  end

  defp required_string(value, message) do
    case string_value(value) do
      nil -> {:error, message}
      value -> {:ok, value}
    end
  end

  defp string_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp string_value(_value), do: nil

  defp maybe_put(options, _key, nil), do: options
  defp maybe_put(options, key, value), do: Keyword.put(options, key, value)

  defp maybe_put_input(input, _key, nil), do: input
  defp maybe_put_input(input, key, value), do: Map.put(input, key, value)

  defp maybe_put_map(map, _key, false), do: map
  defp maybe_put_map(map, key, value), do: Map.put(map, key, value)

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      {:error, _reason} -> body
    end
  end

  defp decode_body(body), do: body

  defp response_error_message(%{"errors" => errors}) when is_list(errors) and errors != [] do
    join_error_messages(errors)
  end

  defp response_error_message(%{"message" => message}) when is_binary(message), do: message

  defp response_error_message(%{"error_description" => message}) when is_binary(message),
    do: message

  defp response_error_message(%{"error" => message}) when is_binary(message), do: message

  defp response_error_message(body) when is_binary(body) do
    case String.trim(body) do
      "" -> nil
      message -> message
    end
  end

  defp response_error_message(_body), do: nil

  defp join_error_messages(errors) do
    errors
    |> Enum.map(fn
      %{"message" => message} when is_binary(message) -> message
      error -> inspect(error)
    end)
    |> Enum.join("; ")
  end

  defp request_error_message(%Req.TransportError{reason: reason}), do: inspect(reason)

  defp request_error_message(reason) do
    Exception.message(reason)
  rescue
    _error -> inspect(reason)
  end
end
