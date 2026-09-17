# Preview at http://localhost:3000/rails/mailers/session_mailer/magic_link
class SessionMailerPreview < ActionMailer::Preview
  def magic_link
    user = User.first || User.new(email: "passenger@example.com")
    SessionMailer.with(user: user, token: user.generate_token_for(:sign_in)).magic_link
  end
end
