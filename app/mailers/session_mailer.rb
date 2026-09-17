class SessionMailer < ApplicationMailer
  # params: :user, :token
  def magic_link
    @user = params[:user]
    @url = verify_session_url(token: params[:token])
    @expires_in_minutes = User::SIGN_IN_TOKEN_WINDOW.inspect

    mail to: @user.email, subject: "Your Ticketbook sign-in link"
  end
end
