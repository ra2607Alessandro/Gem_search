Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
  
  # Root route
  root 'home#index'
  
  # Search interface
  resources :searches, only: [:index, :create, :show] do
    resources :search_results, only: [:index]
  end
  
  # API endpoints
  namespace :api do
    namespace :v1 do
      resources :searches, only: [:create, :show]
    end
  end
  
  # PWA routes (optional)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
