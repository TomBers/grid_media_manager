defmodule GridMediaManager.Articles.Draft do
  use Ecto.Schema
  import Ecto.Changeset

  schema "article_drafts" do
    field :slug, :string
    field :source_title, :string
    field :source_url, :string
    field :brief, :string, default: ""
    field :content, :map
    field :graph, :map
    timestamps(type: :utc_datetime)
  end

  def changeset(draft, attrs) do
    draft
    |> cast(attrs, [:slug, :source_title, :source_url, :brief, :content, :graph])
    |> validate_required([:slug, :source_title, :source_url, :content, :graph])
  end
end
