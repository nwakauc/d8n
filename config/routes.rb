Rails.application.routes.draw do
  root "welcome#index"

  namespace :api do
    namespace :v1 do
      get "health" => "health#show"
      get "me" => "me#show"
      post "auth/phone/request_otp" => "auth/phone#request_otp"
      post "auth/phone/verify_otp" => "auth/phone#verify_otp"
    end
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
