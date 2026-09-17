# Where passengers get on.
class BoardingStop < TripStop
  scope :for_trip, ->(trip) { where(trip: trip).ordered }
end
