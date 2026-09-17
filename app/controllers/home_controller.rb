class HomeController < ApplicationController
  def index
    redirect_to new_session_path, notice: "Please sign in to continue." unless signed_in?
  end
end
