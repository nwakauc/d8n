Rails.application.routes.draw do
  root "welcome#index"

  namespace :api do
    get "docs" => "docs#show"

    namespace :v1 do
      get "health" => "health#show"
      get "openapi.json" => "openapi#show"
      get "me" => "me#show"
      delete "me" => "me#destroy"
      post "account/deactivation" => "account_deactivations#create"
      get "discovery" => "discovery#index"
      get "find" => "find#index"
      get "profiles/:profile_id" => "profiles#show"
      get "matches" => "matches#index"
      post "matches/:match_id/unmatch" => "matches#unmatch"
      get "conversations" => "conversations#index"
      post "matches/:match_id/conversation" => "conversations#create"
      get "conversations/:conversation_id/messages" => "messages#index"
      post "conversations/:conversation_id/messages" => "messages#create"
      post "conversations/:conversation_id/attachments/uploads" => "message_attachment_uploads#create"
      delete "conversations/:conversation_id/messages/:message_id/attachments/:id" => "message_attachments#destroy"
      get "notifications" => "notifications#index"
      patch "notifications/:id/read" => "notifications#read"
      post "notifications/read_all" => "notifications#read_all"
      get "notifications/preferences" => "notification_preferences#show"
      patch "notifications/preferences" => "notification_preferences#update"
      get "likes/incoming" => "likes#incoming"
      get "likes/outgoing" => "likes#outgoing"
      post "profiles/:profile_id/likes" => "likes#create"
      post "profiles/:profile_id/pass" => "profile_passes#create"
      post "profiles/:profile_id/hook" => "hooks#create"
      get "hooks" => "hooks#index"
      post "hooks/:hook_id/reply" => "hooks#reply"
      post "hooks/:hook_id/decline" => "hooks#decline"
      post "profiles/:profile_id/opener" => "openers#create"
      get "openers" => "openers#index"
      post "openers/:opener_id/reply" => "openers#reply"
      post "openers/:opener_id/decline" => "openers#decline"
      get "hook_tonight" => "hook_tonight#show"
      post "hook_tonight" => "hook_tonight#create"
      delete "hook_tonight" => "hook_tonight#destroy"
      get "hook_tonight/discovery" => "hook_tonight#discovery"
      get "blocks" => "profile_blocks#index"
      post "profiles/:profile_id/block" => "profile_blocks#create"
      delete "profiles/:profile_id/block" => "profile_blocks#destroy"
      post "reports" => "reports#create"
      post "profiles/:profile_id/report" => "reports#profile"
      namespace :admin do
        get "reports" => "reports#index"
        get "reports/:id" => "reports#show"
        patch "reports/:id" => "reports#update"
        get "profile_photos" => "profile_photos#index"
        patch "profile_photos/:id" => "profile_photos#update"
        post "profiles/:profile_id/suspension" => "suspensions#create"
        delete "profiles/:profile_id/suspension" => "suspensions#destroy"
      end
      # HQ: unified company command centre backend (docs/FOUNDER-HQ/D8N-HQ/).
      # Never a normal consumer API -- authorized identically to the admin
      # namespace above (Admin::ModeratorContext), never exposed to product
      # clients. `lookup` may be an email/phone (containing "." or "+") or a
      # profile public_id, so it needs an explicit constraint to avoid Rails'
      # default dot-as-format-separator route parsing.
      namespace :hq do
        get "trust_safety/overview" => "trust_safety#overview"
        get "trust_safety/repeat_offenders" => "trust_safety#repeat_offenders"
        get "trust_safety/enforcements" => "trust_safety#enforcements"
        get "members/:lookup" => "members#show", constraints: { lookup: /[^\/]+/ }
        get "members/:lookup/security_events" => "members#security_events", constraints: { lookup: /[^\/]+/ }
        get "members/:lookup/auth_attempts" => "members#auth_attempts", constraints: { lookup: /[^\/]+/ }
        get "members/:lookup/enforcements" => "members#enforcements", constraints: { lookup: /[^\/]+/ }
        get "members/:lookup/discovery_diagnostic" => "members#discovery_diagnostic", constraints: { lookup: /[^\/]+/ }
      end
      get "profile" => "profile#show"
      patch "profile" => "profile#update"
      post "profile/publication" => "profile_publications#create"
      delete "profile/publication" => "profile_publications#destroy"
      get "profile/location" => "profile_locations#show"
      put "profile/location" => "profile_locations#update"
      delete "profile/location" => "profile_locations#destroy"
      get "places" => "places#index"
      get "locations/search" => "location_search#index"
      put "profile/place" => "profile_places#update"
      get "profile/configuration" => "profile_configuration#show"
      patch "profile/options" => "profile_options#update"
      get "profile/prompts" => "profile_prompts#show"
      put "profile/prompts" => "profile_prompts#update"
      get "profile/preferences" => "profile_preferences#show"
      patch "profile/preferences" => "profile_preferences#update"
      get "profile/photos" => "profile_photos#index"
      post "profile/photos/uploads" => "profile_photos#create_upload"
      post "profile/photos" => "profile_photos#create"
      put "profile/photos/order" => "profile_photos#reorder"
      delete "profile/photos/:id" => "profile_photos#destroy"
      get "auth/methods" => "auth/methods#show"
      post "auth/password/register" => "auth/passwords#register"
      post "auth/password/login" => "auth/passwords#login"
      post "auth/password/reactivation" => "auth/passwords#reactivate"
      patch "auth/password" => "auth/passwords#update"
      post "auth/email/change" => "auth/email_changes#create"
      patch "auth/email/change" => "auth/email_changes#update"
      post "auth/password/recovery" => "auth/password_recoveries#create"
      post "auth/password/recovery/verify" => "auth/password_recoveries#verify"
      post "auth/password/recovery/reset" => "auth/password_recoveries#reset"
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
