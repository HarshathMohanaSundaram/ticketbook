require 'rails_helper'

RSpec.describe "Trips", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/trips/index"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/trips/show"
      expect(response).to have_http_status(:success)
    end
  end

end
