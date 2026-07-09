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
    get "/campaigns/:id/share-card.svg", PromotionAssetController, :grid_card
    get "/campaigns/:id/nodes/:node_id/share-card.svg", PromotionAssetController, :node_card

    get "/campaigns/:id/questions/:question_id/share-card.svg",
        PromotionAssetController,
        :question_card

    get "/campaigns/:id/highlights/:highlight_id/share-card.svg",
        PromotionAssetController,
        :highlight_card

    live "/campaigns/:id", ShareStudioLive, :show
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
