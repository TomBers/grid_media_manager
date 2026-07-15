defmodule GridMediaManager.TextNormalizerTest do
  use ExUnit.Case, async: true

  alias GridMediaManager.TextNormalizer

  test "repairs Windows-1252 punctuation without changing valid UTF-8" do
    malformed = "Valid Ԕ text " <> <<0x93>> <> "quoted" <> <<0x94>> <> " " <> <<0x96>> <> " done"

    assert TextNormalizer.normalize_binary(malformed) == "Valid Ԕ text “quoted” – done"
  end

  test "recursively normalizes external payload maps and lists" do
    payload = %{
      "title" => "A title" <> <<0x94>>,
      "items" => [%{"text" => <<0x91>> <> "idea" <> <<0x92>>}]
    }

    assert TextNormalizer.normalize(payload) == %{
             "title" => "A title”",
             "items" => [%{"text" => "‘idea’"}]
           }
  end
end
