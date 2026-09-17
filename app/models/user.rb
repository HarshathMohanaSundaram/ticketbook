class User < ApplicationRecord
  has_many :holds, dependent: :destroy
  has_many :bookings, dependent: :restrict_with_error

  # The column is citext, so uniqueness is case-insensitive in the database too --
  # this validation is the friendly error, the unique index is the guarantee.
  validates :email, presence: true, uniqueness: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }

  normalizes :email, with: ->(email) { email.strip }

  def display_name
    name.presence || email.split("@").first
  end
end
