Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
  
 
  
  # Search interface
  resources :searches, only: [:index, :create, :show] do
    resources :search_results, only: [:index]
    member do
      get :stream_status, to: 'searches#stream_search_status'
    end
  end
  
  # API endpoints
  namespace :api do
    namespace :v1 do
      resources :searches, only: [:create, :show]
    end
  end

  resources :searches, only: [:index, :show, :create]

  namespace :admin do
    get 'searches', to: 'searches#index'
    root to: 'searches#index'
  end
  
  # PWA routes (optional)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  root 'home#index'
end
