# A physical place a bus stops at -- Madiwala Checkpost, Koyambedu CMBT. The same
# place is a boarding point on the outbound trip and a dropping point on the
# return, so the role lives in the trip_stops STI subclass, not here.
class StopPoint < ApplicationRecord
  belongs_to :city
  belongs_to :operator, optional: true   # nil means the point is shared, e.g. a bus stand
  has_many :trip_stops, dependent: :restrict_with_error

  validates :name, presence: true

  scope :for_operator, ->(operator) { where(operator: [ operator, nil ]) }

  def full_name
    [ name, landmark ].compact_blank.join(" - ")
  end
end
