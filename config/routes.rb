# frozen_string_literal: true

RecordingStudioNotifications::Engine.routes.draw do
  resource :settings, only: %i[show update]

  resources :notifications, only: %i[index show] do
    collection do
      get :menu
      get "groups/:group_id/page", action: :group_page, as: :group_page
      patch :clear_all
    end

    member do
      get :open
      patch :mark_read
      patch :mark_unread
      patch :archive
      patch :unarchive
    end
  end

  root "notifications#index"
end
