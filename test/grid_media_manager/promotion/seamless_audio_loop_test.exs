defmodule GridMediaManager.Promotion.SeamlessAudioLoopTest do
  use ExUnit.Case, async: true

  alias GridMediaManager.Promotion.SeamlessAudioLoop

  test "loops decoded samples instead of repeating the compressed input container" do
    assert SeamlessAudioLoop.input_args("theme.m4a") == ["-i", "theme.m4a"]

    filter = SeamlessAudioLoop.filter(30.0, 0.18, 0.5)

    assert filter =~ "aloop=loop=-1"
    assert filter =~ "asetpts=N/SR/TB"
    assert filter =~ "atrim=duration=30.00"
    refute filter =~ "stream_loop"
    refute filter =~ "apad"
  end
end
