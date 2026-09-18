Rails.application.routes.draw do
  root "trips#index"

  resources :trips, only: %i[index show] do
    resources :holds, only: :create
  end

  # A hold is a short-lived claim on seats: five minutes to confirm it.
  resources :holds, only: %i[show destroy] do
    # Singular: one hold converts into at most one booking, enforced by a unique
    # index on bookings.hold_id.
    resource :booking, only: %i[new create]
  end

  # Addressed by PNR rather than id -- see Booking#to_param.
  resources :bookings, only: %i[index show] do
    # Singular: a booking is cancelled once, and the record of it lives on the
    # booking itself (cancelled_at, refund_paise).
    resource :cancellation, only: :create
  end

  # Email-only, passwordless: request a link, then click it.
  resource :session, only: %i[new create destroy]
  get "/sign-in/:token", to: "sessions#verify", as: :verify_session

  # Sign-in mails are captured rather than sent in development; read them here.
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  # Scheduled hold-expiry jobs are visible here. Development only -- this would
  # need authentication before it went anywhere near production.
  if Rails.env.development?
    require "sidekiq/web"
    require "sidekiq/cron/web"
    mount Sidekiq::Web => "/sidekiq"
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
end
