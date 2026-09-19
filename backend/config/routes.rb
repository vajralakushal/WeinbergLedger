Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Everything below lives under /api so the existing same-origin reverse-proxy
  # invariant (see README: "/api/* -> backend, everything else -> frontend/dist")
  # keeps working unchanged for the new auth/admin routes too.
  namespace :api, path: "api" do
    get "search",  to: "books#search"
    get "whoami",  to: "whoami#show"
    get "audit",   to: "audit#index"
    get "lookup",  to: "lookup#show"

    get    "book/:id/thumbnail", to: "books#thumbnail"
    get    "book/:id/history",   to: "books#history"
    patch  "book/:id/borrower",  to: "books#update_borrower"
    patch  "book/:id/location",  to: "books#update_location"
    post   "book",                to: "books#create"
    delete "book/:id",            to: "books#destroy"
    post   "books/bulk",          to: "books#bulk_create"

    post   "registrations", to: "registrations#create"

    post   "sessions", to: "sessions#create"
    delete "sessions", to: "sessions#destroy"

    get   "me",          to: "me#show"
    patch "me/password", to: "me#update_password"

    namespace :admin do
      get    "users",                    to: "users#index"
      patch  "users/:id/approve",        to: "users#approve"
      delete "users/:id",                to: "users#destroy"
      patch  "users/:id/reset_password", to: "users#reset_password"
      patch  "users/:id/make_admin",     to: "users#make_admin"
    end
  end
end
