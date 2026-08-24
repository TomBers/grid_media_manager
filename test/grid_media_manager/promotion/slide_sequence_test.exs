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

  test "short video reading beats remove authoring labels and cap text density" do
    campaign = %Campaign{
      title: "A long answer",
      raw_payload: %{
        "content" => %{
          "key_nodes" => [
            %{
              "id" => "answer-1",
              "title" => "A structured argument",
              "content" => """
              # A structured argument

              Opening context that gives the viewer enough information to follow the argument.

              ## 1. Historical foundation: Public fasting as spectacle
              - **Category:** Historical foundation
              - **The Non-Obvious Connection:** Professional fasters became public attractions. Their performances turned endurance into a commercial spectacle.
              - **Question/Insight Opened:** What did the audience actually reward? The answer changes how the story reads.
              """
            }
          ]
        }
      }
    }

    candidate = %{
      type: "key_node",
      source_id: "answer-1",
      title: "A structured argument",
      label: "Answer"
    }

    slides = SlideSequence.build(campaign, [candidate], reading_mode: :short_video)
    bodies = Enum.map(slides, &Map.get(&1, "body", ""))

    refute Enum.any?(bodies, &String.contains?(&1, "Category:"))
    refute Enum.any?(bodies, &String.contains?(&1, "Non-Obvious Connection:"))
    refute Enum.any?(bodies, &String.contains?(&1, "Question/Insight Opened:"))

    assert Enum.any?(
             slides,
             &Enum.any?(Map.get(&1, "blocks", []), fn block -> block["type"] == "heading" end)
           )

    assert Enum.any?(
             slides,
             &Enum.any?(Map.get(&1, "blocks", []), fn block ->
               block["type"] == "heading" and block["text"] == "Public fasting as spectacle"
             end)
           )

    assert Enum.all?(
             Enum.filter(slides, &(&1["kind"] == "node_text")),
             &(String.length(&1["body"]) <= 320)
           )
  end

  test "short video reading beats never end midway through a sentence" do
    complete_sentence =
      "While philosophical inquiries often focus on how raw sensory data or subjective boundaries are organized, cognitive developmental science asks a more mechanical question: what primitive categories must a mind possess to cut the continuous flux of reality into discrete entities?"

    campaign = %Campaign{
      title: "A complete thought",
      raw_payload: %{
        "content" => %{
          "key_nodes" => [
            %{
              "id" => "answer-1",
              "title" => "The cognitive toolkit",
              "content" => "# The cognitive toolkit\n\n#{complete_sentence}"
            }
          ]
        }
      }
    }

    candidate = %{
      type: "key_node",
      source_id: "answer-1",
      title: "The cognitive toolkit",
      label: "Answer"
    }

    slides = SlideSequence.build(campaign, [candidate], reading_mode: :short_video)

    assert Enum.any?(slides, &(&1["body"] == complete_sentence))
    refute Enum.any?(slides, &String.ends_with?(&1["body"], "possess to"))
  end

  test "long answers do not turn grounding references into slides" do
    campaign = %Campaign{
      title: "A grounded answer",
      raw_payload: %{
        "content" => %{
          "key_nodes" => [
            %{
              "id" => "answer-1",
              "title" => "A grounded answer",
              "content" => """
              # A grounded answer

              The central argument is useful and self-contained [1].

              - Search query: "grounded answer evidence"

              ## References

              - https://example.com/reference
              """
            }
          ]
        }
      }
    }

    candidate = %{
      type: "key_node",
      source_id: "answer-1",
      title: "A grounded answer",
      label: "Answer"
    }

    slides = SlideSequence.build(campaign, [candidate], reading_mode: :full)
    public_text = Enum.map_join(slides, " ", &"#{&1["title"]} #{&1["body"]}")

    assert public_text =~ "The central argument is useful and self-contained."
    refute public_text =~ "Search query"
    refute public_text =~ "References"
    refute public_text =~ "example.com"
    refute public_text =~ "[1]"
  end
end
