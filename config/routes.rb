# frozen_string_literal: true

RecordingStudioNotifications::Engine.routes.draw do
  resource :settings, only: %i[show update]

  resources :notifications, only: %i[index show] do
    member do
      get :open
      patch :mark_read
      patch :mark_unread
      patch :archive
    end
  end

  root "notifications#index"
end
