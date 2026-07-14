defmodule GridMediaManager.TextNormalizer do
  @moduledoc """
  Recursively normalizes external payload text to valid UTF-8.

  RationalGrid payloads should be UTF-8, but older copied content can contain raw
  Windows-1252 punctuation bytes. Valid UTF-8 sequences are preserved while only
  invalid bytes are repaired.
  """

  @windows_1252 %{
    0x80 => "€",
    0x82 => "‚",
    0x83 => "ƒ",
    0x84 => "„",
    0x85 => "…",
    0x86 => "†",
    0x87 => "‡",
    0x88 => "ˆ",
    0x89 => "‰",
    0x8A => "Š",
    0x8B => "‹",
    0x8C => "Œ",
    0x8E => "Ž",
    0x91 => "‘",
    0x92 => "’",
    0x93 => "“",
    0x94 => "”",
    0x95 => "•",
    0x96 => "–",
    0x97 => "—",
    0x98 => "˜",
    0x99 => "™",
    0x9A => "š",
    0x9B => "›",
    0x9C => "œ",
    0x9E => "ž",
    0x9F => "Ÿ"
  }

  def normalize(term) when is_binary(term), do: normalize_binary(term)
  def normalize(term) when is_list(term), do: Enum.map(term, &normalize/1)

  def normalize(term) when is_map(term) and not is_struct(term) do
    Map.new(term, fn {key, value} -> {normalize(key), normalize(value)} end)
  end

  def normalize(term), do: term

  def normalize_binary(binary) when is_binary(binary) do
    if String.valid?(binary), do: binary, else: repair_binary(binary, [])
  end

  defp repair_binary("", acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp repair_binary(binary, acc) do
    case :unicode.characters_to_binary(binary, :utf8, :utf8) do
      converted when is_binary(converted) ->
        [converted | acc] |> Enum.reverse() |> IO.iodata_to_binary()

      {:error, valid_prefix, <<invalid_byte, rest::binary>>} ->
        repair_binary(rest, [replacement(invalid_byte), valid_prefix | acc])

      {:incomplete, valid_prefix, rest} ->
        repaired_tail = rest |> :binary.bin_to_list() |> Enum.map(&replacement/1)
        [repaired_tail, valid_prefix | acc] |> Enum.reverse() |> IO.iodata_to_binary()
    end
  end

  defp replacement(byte), do: Map.get(@windows_1252, byte, latin1_or_replacement(byte))

  defp latin1_or_replacement(byte) when byte in 0xA0..0xFF, do: <<byte::utf8>>
  defp latin1_or_replacement(_byte), do: "�"
end
