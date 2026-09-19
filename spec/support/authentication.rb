# Signs a user in the way the app does: request the magic link, then follow it.
# Going through the real flow means a request spec exercises token verification
# rather than faking a session.
module AuthenticationHelpers
  def sign_in(user)
    # reload first: signing in touches the user, and updated_at is part of what
    # the token signs (that is what makes a magic link single use). A token built
    # from a stale object would be rejected.
    get verify_session_path(token: user.reload.generate_token_for(:sign_in))
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request
end
