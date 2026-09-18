class User < ApplicationRecord
  has_many :holds, dependent: :destroy
  has_many :bookings, dependent: :restrict_with_error

  # The column is citext, so uniqueness is case-insensitive in the database too --
  # this validation is the friendly error, the unique index is the guarantee.
  validates :email, presence: true, uniqueness: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }

  normalizes :email, with: ->(email) { email.strip }

  # The magic link. Rails signs the user id into the token and refuses it after
  # fifteen minutes -- no column, no cleanup job, no token table. Changing the
  # email invalidates any link already in flight, because the address is part of
  # what gets signed.
  SIGN_IN_TOKEN_WINDOW = 15.minutes

  # Signing updated_at into the token makes the link single-use: SessionsController
  # touches the user on a successful sign-in, so the link in the inbox -- and any
  # earlier one -- stops verifying even inside the fifteen minutes.
  generates_token_for :sign_in, expires_in: SIGN_IN_TOKEN_WINDOW do
    # Nanoseconds, not seconds: touch() inside the same second would otherwise
    # produce an identical token, and the link would not be burned after use.
    "#{email}/#{updated_at&.strftime('%s%N')}"
  end

  def display_name
    name.presence || email.split("@").first
  end
end
