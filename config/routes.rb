# frozen_string_literal: true

RecordingStudioNotifications::Engine.routes.draw do
  resources :notifications, only: %i[index show] do
    member do
      patch :mark_read
      patch :mark_unread
      patch :archive
    end
  end

  root "notifications#index"
end
