require 'rails_helper'

RSpec.describe "Holds", type: :request do
  describe "GET /show" do
    it "returns http success" do
      get "/holds/show"
      expect(response).to have_http_status(:success)
    end
  end

end
