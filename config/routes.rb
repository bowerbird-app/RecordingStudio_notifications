# frozen_string_literal: true

RecordingStudioNotifications::Engine.routes.draw do
  resource :settings, only: %i[show update]

  resources :notifications, only: %i[index show] do
    collection do
      get :menu
    end

    member do
      get :open
      patch :mark_read
      patch :mark_unread
      patch :archive
      patch :unarchive
    end
  end

  resources :digests, only: :show

  root "notifications#index"
end
