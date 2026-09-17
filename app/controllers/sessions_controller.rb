class SessionsController < ApplicationController
  # Three steps: ask for an email, mail a signed link, trust the link.
  #
  # Signup and login are the same action deliberately -- the brief asks for an
  # email-only flow, so an address we have not seen creates the account rather
  # than erroring with "no such user", which would also leak who has registered.

  def new
    redirect_to root_path, notice: "You are already signed in." if signed_in?
  end

  def create
    email = params[:email].to_s.strip

    user = User.find_or_initialize_by(email: email)
    unless user.persisted? || user.save
      # flash.now, not `alert:` -- the latter is a redirect_to option and is
      # silently ignored by render, which would swallow the error message.
      flash.now[:alert] = user.errors.full_messages.to_sentence
      return render :new, status: :unprocessable_entity
    end

    SessionMailer.with(user: user, token: user.generate_token_for(:sign_in))
                 .magic_link.deliver_later

    # The same message whether or not the address was already registered.
    redirect_to new_session_path,
                notice: "Check your inbox -- we sent a sign-in link to #{email}."
  end

  # GET /sign-in/:token -- the link in the email.
  def verify
    user = User.find_by_token_for(:sign_in, params[:token])

    if user.nil?
      # Expired, tampered with, or already invalidated by an email change.
      return redirect_to new_session_path,
                         alert: "That sign-in link has expired. Please request a new one."
    end

    # Burns the link: updated_at is part of what the token signs.
    user.touch
    sign_in(user)
    redirect_to return_to_path_or(root_path), notice: "Signed in as #{user.email}."
  end

  def destroy
    sign_out
    # 303 so Turbo follows the redirect with GET rather than repeating the DELETE.
    redirect_to root_path, notice: "Signed out.", status: :see_other
  end
end
