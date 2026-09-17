# Turns query-string params into a validated, typed search.
#
# Everything the user can ask for lives here: the three search fields the brief
# requires, the four advanced filters, and the sort. Keeping it in one object
# means the controller never coerces a param, the query object never reads
# params, and F9 has a single place to hash into a cache key.
class TripSearchForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  SORTS = {
    "departure" => "Departure time",
    "price_low" => "Price: low to high",
    "price_high" => "Price: high to low",
    "rating" => "Operator rating",
    "duration" => "Shortest journey"
  }.freeze

  # Search
  attribute :from, :string        # city slug
  attribute :to, :string          # city slug
  attribute :date, :date

  # Advanced filters
  attribute :bus_type, :string    # ac | non_ac
  attribute :berth_type, :string  # sleeper | seater
  attribute :min_price, :integer  # rupees, as typed by a human
  attribute :max_price, :integer
  attribute :min_rating, :decimal
  attribute :sort, :string, default: "departure"

  validates :from, :to, :date, presence: true, if: :attempted?
  validate :cities_must_exist, if: :attempted?
  validate :date_must_not_be_past, if: :attempted?
  validate :price_range_must_make_sense

  # Checkboxes arrive as an array of codes, or not at all.
  def amenities = @amenities ||= []

  def amenities=(value)
    @amenities = Array(value).compact_blank & Bus::AMENITY_CODES
  end

  # Ruby has no endless definition for setters, so these stay in long form.
  def bus_type=(value)
    super(value.presence)
  end

  def berth_type=(value)
    super(value.presence)
  end

  def sort=(value)
    super(SORTS.key?(value) ? value : "departure")
  end

  # Did the visitor actually ask for something, or are they just looking at the
  # empty form? Distinguishes "no results" from "no search yet".
  def attempted? = from.present? || to.present? || date.present?

  def searchable? = attempted? && valid?

  def origin_city = @origin_city ||= City.find_by(slug: from)
  def destination_city = @destination_city ||= City.find_by(slug: to)

  def min_price_paise = min_price && min_price * 100
  def max_price_paise = max_price && max_price * 100

  def filters_applied?
    bus_type.present? || berth_type.present? || min_price.present? ||
      max_price.present? || min_rating.present? || amenities.any?
  end

  def filter_count
    [ bus_type, berth_type, min_price, max_price, min_rating ].compact_blank.size + amenities.size
  end

  # What the search reduces to once coerced -- the basis of the F9 cache key.
  def filter_attributes
    {
      bus_type: bus_type, berth_type: berth_type,
      min_price_paise: min_price_paise, max_price_paise: max_price_paise,
      min_rating: min_rating&.to_s, amenities: amenities.sort, sort: sort
    }.compact
  end

  def to_params
    { from: from, to: to, date: date&.to_s, bus_type: bus_type, berth_type: berth_type,
      min_price: min_price, max_price: max_price, min_rating: min_rating,
      amenities: amenities, sort: sort }.compact_blank
  end

  # Swap origin and destination -- powers the "reverse" button.
  def reversed_params = to_params.merge(from: to, to: from)

  private

  def cities_must_exist
    errors.add(:from, "is not a city we serve") if from.present? && origin_city.nil?
    errors.add(:to, "is not a city we serve") if to.present? && destination_city.nil?
    errors.add(:to, "must differ from the origin") if from.present? && from == to
  end

  def date_must_not_be_past
    return if date.blank? || date >= Date.current

    errors.add(:date, "is in the past")
  end

  def price_range_must_make_sense
    return if min_price.blank? || max_price.blank? || min_price <= max_price

    errors.add(:max_price, "must be at least the minimum price")
  end
end
