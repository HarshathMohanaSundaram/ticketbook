class Driver < ApplicationRecord
  belongs_to :operator
  has_many :trips, dependent: :nullify
  has_many :relief_trips, class_name: "Trip", foreign_key: :relief_driver_id,
           inverse_of: :relief_driver, dependent: :nullify

  validates :name, presence: true
  validates :licence_number, presence: true, uniqueness: true

  scope :licensed_on, ->(date) { where(licence_expires_on: date..).or(where(licence_expires_on: nil)) }

  def licence_valid_on?(date = Date.current)
    licence_expires_on.nil? || licence_expires_on >= date
  end

  def masked_phone
    phone.present? ? "#{phone[0..2]}xxxxx#{phone[-2..]}" : nil
  end
end
