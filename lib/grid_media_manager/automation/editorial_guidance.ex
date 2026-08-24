defmodule GridMediaManager.Automation.EditorialGuidance do
  @moduledoc """
  Durable editorial and visual rules shared by autonomous planning prompts.

  Keeping these rules in code makes future planner changes inherit the quality lessons learned
  from real publishing runs instead of relying on one-off prompt wording.
  """

  def topic_selection do
    """
    Choose specific, surprising, or consequential questions rather than generic subjects.
    Titles must be publication-ready: correct spelling, grammar, articles, capitalization, and
    punctuation; use sentence case and end direct questions with a question mark.
    Prefer material that can offer a useful tension, counter-intuitive connection, or practical
    implication without sensationalising the source.
    """
  end

  def story_selection do
    """
    Build a coherent audience journey: a strong human question or claim, enough context to
    understand it, two or three explanatory beats, and a memorable implication or open question.
    Use human questions as hooks, human highlights as high-signal quotations, and AI answers as
    explanatory material. Never present an AI answer as a human quotation.

    Treat bibliographies, raw URLs, citation markers, search queries, model scaffolding, and
    phrases such as “further reading” as grounding metadata—not publishable story moments. Treat
    formatting labels such as “Title:”, “Category:”, and section scaffolding as metadata too; do
    not select a moment merely because one of those labels makes it look distinct. Avoid generic
    assistant language, repeated points, unsupported claims, and content that needs the rest of
    the grid to make sense. Select the fewest moments needed for a complete arc, and never select
    both a grid overview and source moments that simply restate it.

    #{copy_quality()}

    #{platform_depth()}

    #{audience_conversion()}
    """
  end

  def audience_conversion do
    """
    Every package exists to earn a qualified visit to RationalGrid.ai. Give the audience one
    satisfying insight, then leave a genuine curiosity gap that the linked grid can resolve with
    evidence, competing interpretations, or connected questions. Never use vague engagement bait.

    Select the strongest standalone visual moment for text channels and identify its role:
    provocative question, key quotation, evidence highlight, or topic cover. It must remain clear
    without the caption. The caption and final visual should promise the specific additional value
    available on RationalGrid.ai rather than merely saying “learn more”.
    """
  end

  def copy_quality do
    """
    Hooks, cover titles, video titles, and short-form post copy must be concise, accurate,
    publication-ready British English. Correct spelling, grammar, articles, capitalization, and
    punctuation. Use sentence case, end direct questions with a question mark, and never truncate
    a thought. Preserve the approved meaning across platforms while adapting length, depth, and
    tone. Do not include raw Markdown, title prefixes, assistant-like offers, search queries, or
    internal citations.
    """
  end

  def platform_depth do
    """
    Treat LinkedIn and Facebook as destinations for substantive posts, not merely longer captions.
    When the source contains a coherent argument worth unpacking, recommend long_form and select
    one strong structured answer or a small number of genuinely complementary moments. Preserve
    the central thesis, the reasoning or evidence behind it, an important tension or limitation,
    and the practical or intellectual implication. Use several readable paragraphs when the
    material supports them; depth and specificity matter more than brevity, but avoid repetition,
    filler, and stitched-together excerpts that do not form one argument.

    LinkedIn copy may use most of its 3,000-character allowance while ending on a complete section.
    Facebook may retain the fuller explanation when it remains coherent and readable. Do not apply
    short-video frame density or duration constraints to either platform.
    """
  end

  def format_selection do
    """
    Match the format to the material and supported destinations:
    - story_video: a paced vertical narrative for Instagram Reels, TikTok, and YouTube Shorts.
    - portrait: a concise image carousel for X, LinkedIn, and Facebook.
    - long_form: a detailed, multi-paragraph, cover-led post for LinkedIn and Facebook.
    - combined_carousel: vertical video plus image carousel when both genuinely add value.

    Choose for audience impact and comprehension, not maximum channel coverage. Dense arguments
    need more reading space; a sharp question and a few visual beats suit short video. Prefer
    long_form when a source can support a deeper explanation rather than reducing it to a teaser.
    For story_video, make brevity an editorial constraint: select only two or three distinct
    moments, never a generic grid overview, and use at most one structured AI-answer node. Aim for
    four to six rendered frames including the cover and closing frame, roughly 25–40 seconds and
    never more than 45 seconds. Each frame should communicate one complete thought in about 25
    words or fewer. Remember that a structured answer can expand into several frames; if the idea
    needs more moments or denser copy, choose portrait or long_form instead. Apply the same concise
    video sequence inside combined_carousel.
    Text posts are visual posts too: X, LinkedIn, and Facebook should receive an uploaded key
    quotation, question, evidence card, cover, or carousel—not unsupported caption-only output.
    """
  end

  def visual_direction(styles) do
    style_list = Enum.map_join(styles, "\n", &"- #{&1.id}: #{&1.description}")

    """
    Select one coherent visual style and one cover direction that amplify the story's emotional
    register without pretending to illustrate an abstract claim literally.

    Available editable canvas styles:
    #{style_list}

    For a photo cover, write a short concrete Pexels query using visible subjects, setting,
    lighting, colour, and composition—not philosophical jargon. Prefer editorial metaphor,
    atmosphere, human scale, and useful negative space for title text. Avoid clichés such as
    glowing robot heads, stock handshakes, random circuit boards, chess pieces, and text inside
    the image. Avoid misleading depictions of people or events named in the source.

    Use a typography-led cover only when any stock photograph would make the idea less accurate
    or more generic. The cover brief must explain the intended audience response and composition.
    """
  end

  def cover_selection do
    """
    Choose the single photo that best supports the story and visual direction. Judge semantic
    relevance, emotional tone, strong portrait composition, negative space for a title overlay,
    and whether the image will stop a social feed without becoming sensational or misleading.
    Reject options that rely on visible text, logos, tired technology clichés, or irrelevant
    literalism. Use only a supplied Pexels photo ID.
    """
  end

  def publishing do
    """
    Before scheduling, read the live Buffer queue and respect the maximum of ten queued posts per
    channel. Use channel-specific historical metrics to choose topics and posting times; do not
    assume one time works for every network. Schedule a campaign on successive days, avoid
    accidental duplicate content, keep video and text destinations distinct, and verify every
    returned Buffer post ID and final scheduled status. Re-check titles and copy immediately
    before submission.
    """
  end
end
