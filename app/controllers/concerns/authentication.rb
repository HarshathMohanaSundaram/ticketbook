# Everything the rest of the app uses to answer "who is this, and may they?".
# Holds, bookings, cancellations and reschedules all hang off current_user.
module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :signed_in?
  end

  private

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.find_by(id: session[:user_id])
  end

  def signed_in? = current_user.present?

  def sign_in(user)
    # Where they were heading before being bounced to sign-in. Captured first
    # because reset_session below empties the session -- without this, following
    # a magic link always landed on the home page instead of the seat map the
    # visitor originally clicked.
    destination = session[:return_to]

    # New session id on privilege change: an attacker who planted a session
    # cookie before sign-in does not get to keep it afterwards.
    reset_session

    session[:user_id] = user.id
    session[:return_to] = destination if destination.present?
    @current_user = user
  end

  def sign_out
    reset_session
    @current_user = nil
  end

  def require_authentication
    return if signed_in?

    # Remember where they were headed so the magic link lands them there and not
    # on the home page -- it matters when the link they clicked was a seat map.
    remember_destination(request.get? ? request.fullpath : request.referer)
    redirect_to new_session_path, alert: "Please sign in to continue."
  end

  # Stores where to come back to after signing in.
  #
  # Only relative paths are accepted. Taking a full URL from a parameter -- or
  # from Referer -- would let someone craft a sign-in link that bounces the
  # visitor to another site afterwards, which is the classic open redirect.
  def remember_destination(value)
    return if value.blank?

    uri = URI.parse(value.to_s)
    # An absolute URL is only acceptable if it points back at us -- this is how
    # Referer arrives. Anything pointing elsewhere is dropped entirely rather
    # than reduced to its path, because the visitor never asked for that page.
    return if uri.host.present? && uri.host != request.host

    path = uri.is_a?(URI::HTTP) ? uri.request_uri : value.to_s
    return unless path.start_with?("/") && !path.start_with?("//")

    session[:return_to] = path
  rescue URI::InvalidURIError
    nil
  end

  def return_to_path_or(default)
    session.delete(:return_to) || default
  end
end
