defmodule GridMediaManager.Promotion.SeamlessAudioLoopTest do
  use ExUnit.Case, async: true

  alias GridMediaManager.Promotion.SeamlessAudioLoop

  test "crossfades the decoded tail into the head before looping the cycle" do
    assert SeamlessAudioLoop.input_args("theme.m4a") == ["-i", "theme.m4a"]

    filter = SeamlessAudioLoop.filter(13.815873, 30.0, 0.18, 0.5)

    assert filter =~ "asplit=3"
    assert filter =~ "atrim=start=0:end=0.500000"
    assert filter =~ "atrim=start=13.315873:end=13.815873"
    assert filter =~ "acrossfade=d=0.500000:c1=tri:c2=tri"
    assert filter =~ "concat=n=2:v=0:a=1"
    assert filter =~ "aloop=loop=-1"
    assert filter =~ "asetpts=N/SR/TB"
    assert filter =~ "atrim=duration=30.00"
    assert filter =~ "[looped_audio]"
    refute filter =~ "stream_loop"
    refute filter =~ "apad"
  end

  test "retains a decoded-sample fallback when source duration cannot be probed" do
    filter = SeamlessAudioLoop.fallback_filter(8.0, 0.18, 0.5)

    assert filter =~ "[1:a:0]aloop=loop=-1"
    assert filter =~ "atrim=duration=8.00"
    assert filter =~ "[looped_audio]"
  end
end
