Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

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
  end
end
