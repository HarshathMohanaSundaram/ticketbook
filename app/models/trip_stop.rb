# A scheduled stop on one trip: which place, at what time, in which role.
# The role is the STI subclass -- BoardingStop or DroppingStop -- so an
# association typed to one of them cannot be handed the other.
class TripStop < ApplicationRecord
  belongs_to :trip
  belongs_to :stop_point

  validates :scheduled_at, presence: true

  scope :ordered, -> { order(:position, :scheduled_at) }

  delegate :name, :landmark, :full_name, to: :stop_point, prefix: false

  def self.role = name.underscore.delete_suffix("_stop")   # "boarding" | "dropping"

  def role = self.class.role

  def scheduled_time = scheduled_at.in_time_zone(Trip::TZ).strftime("%l:%M %p").strip

  def label = "#{full_name} (#{scheduled_time})"
end
