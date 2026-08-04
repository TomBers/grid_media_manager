defmodule GridMediaManagerWeb.Router do
  use GridMediaManagerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GridMediaManagerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", GridMediaManagerWeb do
    pipe_through :browser

    live "/", GridImportLive, :new
    get "/campaigns/:id/share-card.png", PromotionAssetController, :grid_card
    get "/campaigns/:id/nodes/:node_id/share-card.png", PromotionAssetController, :node_card
    get "/campaigns/:id/nodes/:node_id/carousel.png", PromotionAssetController, :node_carousel_png

    get "/campaigns/:id/curated-carousels/:token/slides/:slide/image.png",
        PromotionAssetController,
        :curated_carousel_slide

    get "/campaigns/:id/curated-carousels/:token/short.mp4",
        PromotionAssetController,
        :curated_carousel_video

    get "/campaigns/:id/nodes/:node_id/carousel.mp4",
        PromotionAssetController,
        :node_carousel_video

    get "/campaigns/:id/nodes/:node_id/carousel-frames/:slide/image.png",
        PromotionAssetController,
        :node_carousel_video_frame

    get "/campaigns/:id/questions/:question_id/share-card.png",
        PromotionAssetController,
        :question_card

    get "/campaigns/:id/questions/:question_id/short.mp4",
        PromotionAssetController,
        :question_short_video

    get "/campaigns/:id/highlights/:highlight_id/share-card.png",
        PromotionAssetController,
        :highlight_card

    get "/campaigns/:id/highlights/:highlight_id/short.mp4",
        PromotionAssetController,
        :highlight_short_video

    live "/posts/review", PostReviewLive, :show
    live "/campaigns/:id/studio", GuidedShareStudioLive, :show
    live "/campaigns/:id", ShareStudioLive, :show
  end

  scope "/api", GridMediaManagerWeb do
    pipe_through :api

    post "/campaigns/:id/curated-carousels/:token/browser-frames",
         PromotionAssetController,
         :browser_frame

    post "/campaigns/:id/nodes/:node_id/browser-frames",
         PromotionAssetController,
         :node_browser_frame
  end

  # Other scopes may use custom stacks.
  # scope "/api", GridMediaManagerWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:grid_media_manager, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: GridMediaManagerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
