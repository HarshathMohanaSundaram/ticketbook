# Where passengers get off.
class DroppingStop < TripStop
  scope :for_trip, ->(trip) { where(trip: trip).ordered }
end
