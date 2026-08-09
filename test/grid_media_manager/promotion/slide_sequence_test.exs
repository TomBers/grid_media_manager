defmodule GridMediaManager.Promotion.SlideSequenceTest do
  use ExUnit.Case, async: true

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Promotion.SlideSequence

  test "question and highlight slides contain only their primary text" do
    campaign = %Campaign{title: "A story"}

    candidates = [
      %{
        type: "question",
        title: "What changed?",
        excerpt: "Question context",
        label: "Question"
      },
      %{
        type: "highlight",
        title: "The preserved passage",
        excerpt: "Human-curated signal",
        label: "Highlight"
      }
    ]

    [_cover, question, highlight, _closing] = SlideSequence.build(campaign, candidates)

    assert question == %{
             "kind" => "quote",
             "label" => "Question",
             "title" => "What changed?",
             "body" => ""
           }

    assert highlight == %{
             "kind" => "highlight",
             "label" => "Highlight",
             "title" => "The preserved passage",
             "body" => ""
           }
  end
end
