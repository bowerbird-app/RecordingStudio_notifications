class SystemNotification < ApplicationRecord
  belongs_to :creator, class_name: "User", optional: true

  validates :title, presence: true
  validates :body, presence: true
end
