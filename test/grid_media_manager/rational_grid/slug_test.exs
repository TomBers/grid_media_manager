defmodule GridMediaManager.RationalGrid.SlugTest do
  use ExUnit.Case, async: true

  alias GridMediaManager.RationalGrid.Slug

  describe "normalize/1" do
    test "accepts a bare slug" do
      assert Slug.normalize("what-is-the-collective-subconscious-637e9a") ==
               {:ok, "what-is-the-collective-subconscious-637e9a"}
    end

    test "extracts the slug from a grid URL" do
      assert Slug.normalize(
               "https://rationalgrid.ai/g/what-is-the-collective-subconscious-637e9a?node=9"
             ) ==
               {:ok, "what-is-the-collective-subconscious-637e9a"}
    end

    test "extracts the slug from a media endpoint URL" do
      assert Slug.normalize(
               "https://rationalgrid.ai/g/what-is-the-collective-subconscious-637e9a/media.json"
             ) ==
               {:ok, "what-is-the-collective-subconscious-637e9a"}
    end

    test "extracts the slug from the promotion materials API route" do
      assert Slug.normalize(
               "http://localhost:4000/api/promotion/grids/what-is-the-collective-subconscious-637e9a/materials"
             ) ==
               {:ok, "what-is-the-collective-subconscious-637e9a"}
    end

    test "rejects blank input" do
      assert Slug.normalize("   ") == {:error, :blank}
    end
  end

  describe "direct_media_url?/1" do
    test "detects direct JSON endpoints" do
      assert Slug.direct_media_url?("https://rationalgrid.ai/g/example/media.json")
    end

    test "detects direct promotion materials endpoints" do
      assert Slug.direct_media_url?(
               "http://localhost:4000/api/promotion/grids/what-is-the-collective-subconscious-637e9a/materials"
             )
    end

    test "does not treat normal grid URLs as direct endpoints" do
      refute Slug.direct_media_url?("https://rationalgrid.ai/g/example")
      refute Slug.direct_media_url?("https://rationalgrid.ai/g/social-media-example")
    end
  end
end
