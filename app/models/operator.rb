class Operator < ApplicationRecord
  has_many :buses, dependent: :restrict_with_error
  has_many :drivers, dependent: :restrict_with_error
  has_many :trips, dependent: :restrict_with_error
  has_many :stop_points, dependent: :nullify

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :rating, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }

  def to_param = slug
end
