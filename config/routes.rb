Rails.application.routes.draw do
  root "welcome#index"

  namespace :api do
    get "docs" => "docs#show"

    namespace :v1 do
      get "health" => "health#show"
      get "openapi.json" => "openapi#show"
      get "me" => "me#show"
      get "discovery" => "discovery#index"
      get "matches" => "matches#index"
      get "conversations" => "conversations#index"
      post "matches/:match_id/conversation" => "conversations#create"
      post "profiles/:profile_id/likes" => "likes#create"
      post "profiles/:profile_id/pass" => "profile_passes#create"
      post "profiles/:profile_id/block" => "profile_blocks#create"
      delete "profiles/:profile_id/block" => "profile_blocks#destroy"
      get "profile" => "profile#show"
      patch "profile" => "profile#update"
      post "profile/publication" => "profile_publications#create"
      delete "profile/publication" => "profile_publications#destroy"
      put "profile/location" => "profile_locations#update"
      delete "profile/location" => "profile_locations#destroy"
      get "profile/configuration" => "profile_configuration#show"
      patch "profile/options" => "profile_options#update"
      get "profile/preferences" => "profile_preferences#show"
      patch "profile/preferences" => "profile_preferences#update"
      get "profile/photos" => "profile_photos#index"
      post "profile/photos/uploads" => "profile_photos#create_upload"
      post "profile/photos" => "profile_photos#create"
      delete "profile/photos/:id" => "profile_photos#destroy"
      get "auth/methods" => "auth/methods#show"
      post "auth/password/register" => "auth/passwords#register"
      post "auth/password/login" => "auth/passwords#login"
      patch "auth/password" => "auth/passwords#update"
      post "auth/verification" => "auth/verifications#create"
      patch "auth/verification" => "auth/verifications#update"
      delete "auth/session" => "auth/sessions#destroy"
    end
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
