class City < ApplicationRecord
  has_many :stop_points, dependent: :destroy
  has_many :departing_trips, class_name: "Trip", foreign_key: :origin_city_id, inverse_of: :origin_city,
           dependent: :restrict_with_error
  has_many :arriving_trips, class_name: "Trip", foreign_key: :destination_city_id, inverse_of: :destination_city,
           dependent: :restrict_with_error

  validates :name, :state, presence: true
  validates :slug, presence: true, uniqueness: true

  scope :alphabetical, -> { order(:name) }

  def to_param = slug
end
