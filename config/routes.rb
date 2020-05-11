Rails.application.routes.draw do
  
  root "organisations#index"

  devise_for :users, :controllers => { registrations: 'registrations' }
  devise_scope :user do
    get "login", to: "devise/sessions#new"
    get "register", to: "devise/registrations#new"
  end
  
  resources :organisations, only: [:index, :new, :create, :edit, :update]
  resources :services, except: [:edit]
  resources :members, only: [:new, :create, :destroy]

  namespace :admin do
    root "dashboard#index"
    resources :services, except: :edit do
      resources :watch, only: [:create, :destroy]
      resources :notes, only: [:create, :destroy]
      resources :snapshots, only: [:index, :update]
      collection do 
        resources :archive, only: [:update]
        resources :requests, only: [:index, :update]
      end
    end
    resources :organisations, except: :edit
    resources :locations, except: [:edit, :new, :create]
    resources :taxonomies, except: [:new, :edit]
    resources :ofsted, onlt: [:index] do
      collection do
        get "pending"
      end
    end
    resources :activity, only: [:index]
    resources :users, except: [:edit] do
      post "reset"
      post "reactivate"
    end
  end

  namespace :api do
    namespace :v1 do
      resources :services, only: [:show, :index]
    end
  end
end
