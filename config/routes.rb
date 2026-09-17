Rails.application.routes.draw do
  # A placeholder landing page. F3 replaces this with the trip search.
  root "home#index"

  # Email-only, passwordless: request a link, then click it.
  resource :session, only: %i[new create destroy]
  get "/sign-in/:token", to: "sessions#verify", as: :verify_session

  # Sign-in mails are captured rather than sent in development; read them here.
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
end
