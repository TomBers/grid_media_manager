defmodule GridMediaManager.Social.Buffer do
  @moduledoc """
  Focused client for scheduling campaign post drafts through Buffer's GraphQL API.

  Configure it under `:grid_media_manager, :buffer`:

      config :grid_media_manager, :buffer,
        api_key: "...",
        text_api_key: "...",
        organization_id: "...",
        text_organization_id: "...",
        video_organization_id: "...",
        text_channels: %{"x" => "...", "linkedin" => "..."},
        endpoint: "https://api.buffer.com"

  Video platforms use `api_key`/`video_api_key` and `video_channels`. Text-first
  platforms use `text_api_key` and `text_channels` when configured.
  Organization IDs may be shared through `organization_id` or configured per
  account. When omitted, snapshots discover the organization and require the
  authenticated account to contain exactly one.

  The endpoint defaults to `https://api.buffer.com`. A `:plug` option may be
  configured for `Req.Test` without allowing test requests onto the network.
  """

  alias GridMediaManager.Campaigns.PostDraft
  alias GridMediaManager.Social.Platforms

  @default_endpoint "https://api.buffer.com"
  @queue_limit 10
  @page_size 50
  @maximum_pages 100

  @organizations_query """
  query BufferOrganizations {
    account {
      organizations {
        id
        name
      }
    }
  }
  """

  @queue_posts_query """
  query BufferQueuePosts($after: String, $first: Int!, $input: PostsInput!) {
    posts(after: $after, first: $first, input: $input) {
      edges {
        node {
          id
          text
          status
          dueAt
          channelId
          createdAt
        }
      }
      pageInfo {
        endCursor
        hasNextPage
      }
    }
  }
  """

  @performance_posts_query """
  query BufferPerformancePosts($after: String, $first: Int!, $input: PostsInput!) {
    posts(after: $after, first: $first, input: $input) {
      edges {
        node {
          id
          text
          status
          dueAt
          sentAt
          channelId
          createdAt
          metrics {
            type
            name
            value
            unit
          }
          metricsUpdatedAt
        }
      }
      pageInfo {
        endCursor
        hasNextPage
      }
    }
  }
  """

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
    not is_nil(api_key()) or not is_nil(api_key("text"))
  end

  @doc "Returns whether the Buffer account for a platform is configured."
  def configured?(platform) when is_binary(platform), do: not is_nil(account_for(platform))
  def configured?(_platform), do: configured?()

  @doc "Returns the Buffer account credentials and channel for a platform."
  def account_for(platform) when is_binary(platform) do
    case {api_key(platform), channel_id(platform)} do
      {api_key, channel_id} when is_binary(api_key) and is_binary(channel_id) ->
        %{api_key: api_key, channel_id: channel_id}

      _missing ->
        nil
    end
  end

  def account_for(_platform), do: nil

  @doc """
  Returns the complete scheduled queue for each requested Buffer platform.

  The result includes normalized posts, scheduled counts, and vacancies against
  the project's ten-post queue limit. All requested platforms must be configured.
  """
  def queue_snapshot(platforms) when is_list(platforms) do
    with {:ok, accounts} <- snapshot_accounts(platforms),
         {:ok, posts} <- fetch_account_posts(accounts, :scheduled, nil) do
      {:ok,
       %{
         fetched_at: DateTime.utc_now() |> DateTime.truncate(:second),
         queue_limit: @queue_limit,
         platforms: platform_snapshots(accounts, posts, :queue)
       }}
    end
  end

  def queue_snapshot(_platforms), do: {:error, :invalid_platforms}

  @doc """
  Returns sent Buffer posts and their normalized per-post metrics.

  Options accept `:since` and `:until` UTC `DateTime` values. The default window
  is the 90 days ending now and the maximum supported window is 365 days.
  """
  def performance_snapshot(platforms, opts) when is_list(platforms) and is_list(opts) do
    with {:ok, range} <- performance_range(opts),
         {:ok, accounts} <- snapshot_accounts(platforms),
         {:ok, posts} <- fetch_account_posts(accounts, :sent, range) do
      {:ok,
       %{
         fetched_at: DateTime.utc_now() |> DateTime.truncate(:second),
         since: range.since,
         until: range.until,
         platforms: platform_snapshots(accounts, posts, :performance)
       }}
    end
  end

  def performance_snapshot(_platforms, _opts), do: {:error, :invalid_options}

  @doc "Returns the configured Buffer channel ID for a social platform."
  def channel_id(platform) when is_binary(platform) do
    channel = channel_value(account_channels(platform), platform)

    if is_nil(channel) and is_nil(config_value(account_channels_key(platform))) do
      channel_value(config_value(:channels), platform)
    else
      channel
    end
  rescue
    ArgumentError -> nil
  end

  def channel_id(_platform), do: nil

  @doc """
  Schedules a post draft for a Buffer channel.

  `opts` requires `:channel_id` and accepts `:media`, `:media_url`, `:mime_type`,
  `:title`, `:instagram_type`, and `:youtube_category_id`. `:media` is an ordered
  list of items containing `url` and `mime_type`, or normalized Buffer asset maps.
  It takes precedence over the single-asset `:media_url` and `:mime_type` options.
  Legacy media defaults to an image; a MIME type of `video/mp4` creates a video
  asset. Multiple Instagram images default to `carousel`, while a single video
  defaults to `reel`. The draft's `scheduled_for` value is sent as Buffer's
  `dueAt`.
  """
  def schedule(%PostDraft{} = draft, opts) when is_list(opts) or is_map(opts) do
    with {:ok, key} <- configured_api_key(option(opts, :api_key)),
         {:ok, channel_id} <- required_string(option(opts, :channel_id), "channel_id is required"),
         {:ok, text} <- required_string(draft.body, "post draft body is required"),
         {:ok, due_at} <- due_at(draft.scheduled_for),
         {:ok, assets} <- assets(opts),
         {:ok, metadata} <- post_metadata(draft, opts, assets) do
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

  defp snapshot_accounts(platforms) do
    platforms = Enum.uniq(platforms)
    invalid = Enum.reject(platforms, &(&1 in Platforms.ids()))

    cond do
      platforms == [] ->
        {:error, :invalid_platforms}

      invalid != [] ->
        {:error, {:unsupported_platforms, invalid}}

      true ->
        accounts =
          Enum.map(platforms, fn platform ->
            case account_for(platform) do
              %{api_key: key, channel_id: channel_id} ->
                %{
                  platform: platform,
                  api_key: key,
                  channel_id: channel_id,
                  account_kind: account_kind(platform)
                }

              nil ->
                nil
            end
          end)

        missing =
          accounts
          |> Enum.zip(platforms)
          |> Enum.filter(fn {account, _platform} -> is_nil(account) end)
          |> Enum.map(fn {_account, platform} -> platform end)

        if missing == [],
          do: {:ok, accounts},
          else: {:error, {:platforms_not_configured, missing}}
    end
  end

  defp fetch_account_posts(accounts, status, range) do
    accounts
    |> Enum.group_by(&{&1.api_key, &1.account_kind})
    |> Enum.reduce_while({:ok, []}, fn {{key, account_kind}, group}, {:ok, all_posts} ->
      channel_ids = Enum.map(group, & &1.channel_id)

      with {:ok, organization_id} <- resolve_organization_id(key, account_kind),
           {:ok, posts} <- fetch_posts(key, organization_id, channel_ids, status, range) do
        {:cont, {:ok, all_posts ++ posts}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp resolve_organization_id(key, account_kind) do
    case configured_organization_id(account_kind) do
      nil -> fetch_single_organization_id(key, account_kind)
      organization_id -> {:ok, organization_id}
    end
  end

  defp fetch_single_organization_id(key, account_kind) do
    with {:ok, %{"account" => %{"organizations" => organizations}}} <-
           graphql_request(key, @organizations_query, %{}) do
      case organizations do
        [%{"id" => id}] when is_binary(id) ->
          {:ok, id}

        [] ->
          {:error, {:buffer_organization_not_found, account_kind}}

        organizations when is_list(organizations) ->
          {:error,
           {:buffer_organization_ambiguous, account_kind, Enum.map(organizations, & &1["id"])}}

        _other ->
          {:error, {:invalid_buffer_organizations_response, account_kind}}
      end
    else
      {:ok, _unexpected} -> {:error, {:invalid_buffer_organizations_response, account_kind}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_posts(key, organization_id, channel_ids, status, range) do
    query = if(status == :sent, do: @performance_posts_query, else: @queue_posts_query)
    input = posts_input(organization_id, channel_ids, status, range)
    fetch_post_pages(key, query, input, nil, [], 0)
  end

  defp fetch_post_pages(_key, _query, _input, _after, _posts, @maximum_pages),
    do: {:error, :buffer_pagination_limit_exceeded}

  defp fetch_post_pages(key, query, input, after_cursor, posts, page_count) do
    variables = %{
      "after" => after_cursor,
      "first" => @page_size,
      "input" => input
    }

    with {:ok, %{"posts" => %{"edges" => edges, "pageInfo" => page_info}}} <-
           graphql_request(key, query, variables),
         true <- is_list(edges) and is_map(page_info) do
      with {:ok, page_posts} <- normalize_post_edges(edges) do
        accumulated = posts ++ page_posts

        case page_info do
          %{"hasNextPage" => true, "endCursor" => cursor} when is_binary(cursor) ->
            fetch_post_pages(key, query, input, cursor, accumulated, page_count + 1)

          %{"hasNextPage" => false} ->
            {:ok, accumulated}

          _invalid_page_info ->
            {:error, :invalid_buffer_pagination_response}
        end
      end
    else
      false -> {:error, :invalid_buffer_posts_response}
      {:ok, _unexpected} -> {:error, :invalid_buffer_posts_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp posts_input(organization_id, channel_ids, status, range) do
    filter =
      %{
        "status" => [Atom.to_string(status)],
        "channelIds" => channel_ids
      }
      |> maybe_put_date_range(range)

    %{
      "organizationId" => organization_id,
      "filter" => filter,
      "sort" => [
        %{
          "field" => "dueAt",
          "direction" => if(status == :sent, do: "desc", else: "asc")
        }
      ]
    }
  end

  defp maybe_put_date_range(filter, nil), do: filter

  defp maybe_put_date_range(filter, range) do
    filter
    |> Map.put("startDate", DateTime.to_iso8601(range.since))
    |> Map.put("endDate", DateTime.to_iso8601(range.until))
  end

  defp normalize_post_edge(%{"node" => post}) when is_map(post) do
    {:ok,
     %{
       id: post["id"],
       text: post["text"],
       status: post["status"],
       due_at: post["dueAt"],
       sent_at: post["sentAt"],
       created_at: post["createdAt"],
       channel_id: post["channelId"],
       metrics_updated_at: post["metricsUpdatedAt"],
       metrics: Enum.map(post["metrics"] || [], &normalize_metric/1)
     }}
  end

  defp normalize_post_edge(_edge), do: {:error, :invalid_buffer_posts_response}

  defp normalize_post_edges(edges) do
    Enum.reduce_while(edges, {:ok, []}, fn edge, {:ok, posts} ->
      case normalize_post_edge(edge) do
        {:ok, post} -> {:cont, {:ok, [post | posts]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, posts} -> {:ok, Enum.reverse(posts)}
      error -> error
    end
  end

  defp normalize_metric(metric) when is_map(metric) do
    %{
      type: metric["type"],
      name: metric["name"],
      value: metric["value"],
      unit: metric["unit"]
    }
  end

  defp platform_snapshots(accounts, posts, mode) do
    Map.new(accounts, fn account ->
      channel_posts = Enum.filter(posts, &(&1.channel_id == account.channel_id))

      snapshot = %{
        channel_id: account.channel_id,
        post_count: length(channel_posts),
        posts: channel_posts
      }

      snapshot =
        if mode == :queue do
          snapshot
          |> Map.put(:scheduled_count, length(channel_posts))
          |> Map.put(:vacancies, max(@queue_limit - length(channel_posts), 0))
        else
          snapshot
        end

      {account.platform, snapshot}
    end)
  end

  defp performance_range(opts) do
    until = Keyword.get(opts, :until, DateTime.utc_now())
    since = Keyword.get(opts, :since, default_since(until))

    with true <- match?(%DateTime{}, since) and match?(%DateTime{}, until),
         :lt <- DateTime.compare(since, until),
         seconds when seconds <= 365 * 86_400 <- DateTime.diff(until, since, :second) do
      {:ok,
       %{
         since: DateTime.truncate(since, :second),
         until: DateTime.truncate(until, :second)
       }}
    else
      _invalid -> {:error, :invalid_performance_window}
    end
  end

  defp default_since(%DateTime{} = until), do: DateTime.add(until, -90 * 86_400, :second)
  defp default_since(_until), do: nil

  defp graphql_request(key, query, variables) do
    request_options =
      [
        url: endpoint(),
        headers: [{"authorization", "Bearer #{key}"}],
        json: %{"query" => query, "variables" => variables},
        receive_timeout: receive_timeout(),
        retry: false
      ]
      |> maybe_put(:plug, config_value(:plug))

    case Req.post(request_options) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        case decode_body(body) do
          %{"errors" => errors} when is_list(errors) and errors != [] ->
            {:error, "Buffer GraphQL error: #{join_error_messages(errors)}"}

          %{"data" => data} when is_map(data) ->
            {:ok, data}

          _unexpected ->
            {:error, "Buffer API returned an unexpected response"}
        end

      {:ok, %{status: status, body: body}} ->
        case response_error_message(decode_body(body)) do
          nil -> {:error, "Buffer API request failed with HTTP status #{status}"}
          message -> {:error, "Buffer API request failed (HTTP #{status}): #{message}"}
        end

      {:error, reason} ->
        {:error, "Buffer API request failed: #{request_error_message(reason)}"}
    end
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
    case option(opts, :media) do
      nil -> legacy_assets(opts)
      media when is_list(media) -> normalize_media(media)
      _other -> {:error, "media must be a list"}
    end
  end

  defp legacy_assets(opts) do
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
        with {:ok, asset} <- asset_for_mime_type(url, String.downcase(mime_type)) do
          {:ok, [asset]}
        end
    end
  end

  defp normalize_media(media) do
    media
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, assets} ->
      case normalize_media_item(item) do
        {:ok, asset} -> {:cont, {:ok, [asset | assets]}}
        {:error, message} -> {:halt, {:error, "media item #{index}: #{message}"}}
      end
    end)
    |> case do
      {:ok, assets} -> {:ok, Enum.reverse(assets)}
      error -> error
    end
  end

  defp normalize_media_item(item) when is_list(item) do
    if Keyword.keyword?(item) do
      normalize_media_fields(Keyword.get(item, :url), Keyword.get(item, :mime_type))
    else
      {:error, "must be a keyword list or map"}
    end
  end

  defp normalize_media_item(item) when is_map(item) do
    case normalized_asset(item) do
      {:ok, asset} -> {:ok, asset}
      :not_normalized -> normalize_media_fields(option(item, :url), option(item, :mime_type))
    end
  end

  defp normalize_media_item(_item), do: {:error, "must be a keyword list or map"}

  defp normalized_asset(item) do
    image = Map.get(item, :image) || Map.get(item, "image")
    video = Map.get(item, :video) || Map.get(item, "video")

    case {image, video} do
      {image, nil} when is_map(image) -> normalize_asset_url("image", image)
      {nil, video} when is_map(video) -> normalize_asset_url("video", video)
      {nil, nil} -> :not_normalized
      _other -> {:error, "must contain exactly one image or video asset"}
    end
  end

  defp normalize_asset_url(type, asset) do
    case string_value(Map.get(asset, :url) || Map.get(asset, "url")) do
      nil -> {:error, "#{type} url is required"}
      url -> {:ok, %{type => %{"url" => url}}}
    end
  end

  defp normalize_media_fields(url, mime_type) do
    with {:ok, url} <- required_string(url, "url is required"),
         {:ok, mime_type} <- required_string(mime_type, "mime_type is required") do
      asset_for_mime_type(url, String.downcase(mime_type))
    end
  end

  defp asset_for_mime_type(url, "video/mp4") do
    {:ok, %{"video" => %{"url" => url}}}
  end

  defp asset_for_mime_type(url, "image/" <> _subtype) do
    {:ok, %{"image" => %{"url" => url}}}
  end

  defp asset_for_mime_type(_url, mime_type) do
    {:error, "unsupported media MIME type: #{mime_type}; expected image/* or video/mp4"}
  end

  defp post_metadata(%PostDraft{platform: "instagram"}, opts, assets) do
    requested_type = option(opts, :instagram_type) |> string_value()

    type =
      requested_type ||
        cond do
          multiple_images?(assets) -> "carousel"
          single_video?(assets) -> "reel"
          true -> "post"
        end

    if type in ["post", "story", "reel", "carousel"] do
      instagram_metadata = %{
        "type" => type,
        "shouldShareToFeed" => type != "story"
      }

      {:ok, %{"instagram" => instagram_metadata}}
    else
      {:error, "instagram_type must be post, story, reel, or carousel"}
    end
  end

  defp post_metadata(%PostDraft{platform: "youtube"}, opts, _assets) do
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

  defp post_metadata(%PostDraft{platform: "facebook"}, opts, _assets) do
    type = option(opts, :facebook_type) |> string_value() || "post"

    if type in ["post", "story", "reel"] do
      {:ok, %{"facebook" => %{"type" => type}}}
    else
      {:error, "facebook_type must be post, story, or reel"}
    end
  end

  defp post_metadata(%PostDraft{}, _opts, _assets), do: {:ok, nil}

  defp single_video?([%{"video" => %{"url" => _url}}]), do: true
  defp single_video?(_assets), do: false

  defp multiple_images?(assets) when is_list(assets) do
    length(assets) > 1 and Enum.all?(assets, &match?(%{"image" => %{"url" => _}}, &1))
  end

  defp multiple_images?(_assets), do: false

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

  defp configured_api_key(explicit_key) do
    case string_value(explicit_key) || api_key() do
      nil -> {:error, "Buffer is not configured; set :grid_media_manager, :buffer, :api_key"}
      key -> {:ok, key}
    end
  end

  defp api_key do
    config_value(:api_key)
    |> string_value()
  end

  defp api_key(platform) when platform in ["x", "linkedin", "facebook", "bluesky", "substack"] do
    case config_value(:text_api_key) |> string_value() do
      nil -> api_key()
      key -> key
    end
  end

  defp api_key(_platform) do
    case config_value(:video_api_key) |> string_value() do
      nil -> api_key()
      key -> key
    end
  end

  defp account_kind(platform) when platform in ["x", "linkedin", "facebook"], do: :text
  defp account_kind(_platform), do: :video

  defp configured_organization_id(account_kind) do
    account_kind
    |> organization_config_key()
    |> config_value()
    |> string_value()
    |> case do
      nil -> config_value(:organization_id) |> string_value()
      organization_id -> organization_id
    end
  end

  defp organization_config_key(:text), do: :text_organization_id
  defp organization_config_key(:video), do: :video_organization_id

  defp account_channels(platform) do
    case config_value(account_channels_key(platform)) do
      nil -> config_value(:channels)
      channels -> channels
    end
  end

  defp account_channels_key(platform)
       when platform in ["x", "linkedin", "facebook", "bluesky", "substack"],
       do: :text_channels

  defp account_channels_key(_platform), do: :video_channels

  defp channel_value(channels, platform) when is_map(channels) do
    Map.get(channels, platform) ||
      Map.get(channels, String.to_existing_atom(platform))
      |> string_value()
  rescue
    ArgumentError -> nil
  end

  defp channel_value(channels, platform) when is_list(channels) do
    Keyword.get(channels, String.to_existing_atom(platform))
    |> string_value()
  rescue
    ArgumentError -> nil
  end

  defp channel_value(_channels, _platform), do: nil

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
