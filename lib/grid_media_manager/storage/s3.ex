defmodule GridMediaManager.Storage.S3 do
  @moduledoc """
  Uploads generated media to an Amazon S3 bucket using Req and AWS Signature V4.

  Environment variables take precedence over application configuration:

    * `S3_BUCKET`
    * `AWS_REGION` (defaults to `us-east-1`)
    * `AWS_ACCESS_KEY_ID`
    * `AWS_SECRET_ACCESS_KEY`
    * `AWS_SESSION_TOKEN` (optional)
    * `S3_ENDPOINT` (optional full bucket endpoint)
    * `S3_PUBLIC_BASE_URL` (optional CloudFront or public bucket URL)
  """

  @service "s3"
  @default_region "us-east-1"

  def configured? do
    Enum.all?([bucket(), access_key_id(), secret_access_key()], &is_binary/1)
  end

  def put_object(key, body, content_type)
      when is_binary(key) and is_binary(body) and is_binary(content_type) do
    with {:ok, config} <- configuration(),
         encoded_key <- encode_key(key),
         url <- object_url(config, encoded_key),
         headers <- signed_headers(config, url, body, content_type, DateTime.utc_now()),
         {:ok, response} <- request(url, body, headers),
         :ok <- successful_response(response) do
      {:ok, public_url(config, encoded_key)}
    end
  end

  def put_object(_key, _body, _content_type), do: {:error, "Invalid S3 object data."}

  defp configuration do
    config = %{
      bucket: bucket(),
      region: region(),
      access_key_id: access_key_id(),
      secret_access_key: secret_access_key(),
      session_token: setting("AWS_SESSION_TOKEN", :session_token),
      endpoint: setting("S3_ENDPOINT", :endpoint),
      public_base_url: setting("S3_PUBLIC_BASE_URL", :public_base_url),
      plug: config_value(:plug)
    }

    missing =
      [
        {"S3_BUCKET", config.bucket},
        {"AWS_ACCESS_KEY_ID", config.access_key_id},
        {"AWS_SECRET_ACCESS_KEY", config.secret_access_key}
      ]
      |> Enum.filter(fn {_name, value} -> is_nil(value) end)
      |> Enum.map_join(", ", &elem(&1, 0))

    if missing == "" do
      {:ok, config}
    else
      {:error, "S3 is not configured. Set #{missing}."}
    end
  end

  defp signed_headers(config, url, body, content_type, now) do
    uri = URI.parse(url)
    amz_date = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")
    date = Calendar.strftime(now, "%Y%m%d")
    payload_hash = sha256_hex(body)

    headers =
      %{
        "content-type" => content_type,
        "host" => uri_host(uri),
        "x-amz-content-sha256" => payload_hash,
        "x-amz-date" => amz_date
      }
      |> maybe_put("x-amz-security-token", config.session_token)

    signed_header_names = headers |> Map.keys() |> Enum.sort()
    signed_headers = Enum.join(signed_header_names, ";")

    canonical_headers =
      Enum.map_join(signed_header_names, "", fn name ->
        "#{name}:#{headers |> Map.fetch!(name) |> normalize_header()}\n"
      end)

    canonical_request =
      Enum.join(
        [
          "PUT",
          uri.path,
          uri.query || "",
          canonical_headers,
          signed_headers,
          payload_hash
        ],
        "\n"
      )

    scope = "#{date}/#{config.region}/#{@service}/aws4_request"

    string_to_sign =
      Enum.join(
        ["AWS4-HMAC-SHA256", amz_date, scope, sha256_hex(canonical_request)],
        "\n"
      )

    signing_key = signing_key(config.secret_access_key, date, config.region)
    signature = hmac_hex(signing_key, string_to_sign)

    authorization =
      "AWS4-HMAC-SHA256 Credential=#{config.access_key_id}/#{scope}, " <>
        "SignedHeaders=#{signed_headers}, Signature=#{signature}"

    headers
    |> Map.delete("host")
    |> Map.put("authorization", authorization)
    |> Enum.to_list()
  end

  defp request(url, body, headers) do
    options =
      [
        url: url,
        body: body,
        headers: headers,
        retry: false,
        receive_timeout: 30_000
      ]
      |> maybe_put_option(:plug, config_value(:plug))

    Req.put(options)
  end

  defp successful_response(%{status: status}) when status in 200..299, do: :ok

  defp successful_response(%{status: status, body: body}) do
    message = s3_error_message(body)
    {:error, "S3 upload failed with HTTP #{status}#{if(message, do: ": #{message}", else: "")}"}
  end

  defp object_url(config, encoded_key) do
    config
    |> endpoint()
    |> join_url(encoded_key)
  end

  defp public_url(%{public_base_url: nil} = config, encoded_key),
    do: object_url(config, encoded_key)

  defp public_url(%{public_base_url: base_url}, encoded_key), do: join_url(base_url, encoded_key)

  defp endpoint(%{endpoint: endpoint}) when is_binary(endpoint),
    do: String.trim_trailing(endpoint, "/")

  defp endpoint(%{bucket: bucket, region: region}) do
    "https://#{bucket}.s3.#{region}.amazonaws.com"
  end

  defp join_url(base_url, encoded_key),
    do: String.trim_trailing(base_url, "/") <> "/" <> encoded_key

  defp encode_key(key) do
    key
    |> String.split("/", trim: true)
    |> Enum.map_join("/", &URI.encode(&1, fn character -> URI.char_unreserved?(character) end))
  end

  defp uri_host(%URI{host: host, port: nil}), do: host
  defp uri_host(%URI{host: host, scheme: "https", port: 443}), do: host
  defp uri_host(%URI{host: host, scheme: "http", port: 80}), do: host
  defp uri_host(%URI{host: host, port: port}), do: "#{host}:#{port}"

  defp signing_key(secret, date, region) do
    ("AWS4" <> secret)
    |> hmac(date)
    |> hmac(region)
    |> hmac(@service)
    |> hmac("aws4_request")
  end

  defp sha256_hex(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  defp hmac(key, value), do: :crypto.mac(:hmac, :sha256, key, value)
  defp hmac_hex(key, value), do: hmac(key, value) |> Base.encode16(case: :lower)

  defp normalize_header(value), do: value |> String.trim() |> String.replace(~r/\s+/, " ")

  defp bucket, do: setting("S3_BUCKET", :bucket)
  defp region, do: setting("AWS_REGION", :region) || @default_region
  defp access_key_id, do: setting("AWS_ACCESS_KEY_ID", :access_key_id)
  defp secret_access_key, do: setting("AWS_SECRET_ACCESS_KEY", :secret_access_key)

  defp setting(environment_name, config_key) do
    System.get_env(environment_name)
    |> present_string()
    |> case do
      nil -> config_value(config_key) |> present_string()
      value -> value
    end
  end

  defp config_value(key) do
    case Application.get_env(:grid_media_manager, :s3, []) do
      config when is_list(config) -> Keyword.get(config, key)
      config when is_map(config) -> Map.get(config, key)
      _config -> nil
    end
  end

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp present_string(_value), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_option(options, _key, nil), do: options
  defp maybe_put_option(options, key, value), do: Keyword.put(options, key, value)

  defp s3_error_message(body) when is_binary(body) do
    case Regex.run(~r/<Message>(.*?)<\/Message>/s, body, capture: :all_but_first) do
      [message] -> message
      _match -> nil
    end
  end

  defp s3_error_message(_body), do: nil
end
