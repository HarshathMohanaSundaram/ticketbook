require "rails_helper"

RSpec.describe "Sessions", type: :request do
  describe "GET /session/new" do
    context "when signed out" do
      before { get new_session_path }

      it "renders the sign-in form" do
        expect(response.body).to include("Email me a sign-in link")
      end

      it "returns a successful response" do
        expect(response).to have_http_status(:ok)
      end
    end

    context "when already signed in" do
      before do
        sign_in(create(:user))
        get new_session_path
      end

      it "redirects to the search page" do
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "POST /session" do
    context "with an address nobody has used" do
      let(:email) { "newcomer@example.com" }

      it "creates the account" do
        expect { post session_path, params: { email: email } }.to change(User, :count).by(1)
      end

      it "sends a sign-in link" do
        expect { post session_path, params: { email: email } }
          .to have_enqueued_mail(SessionMailer, :magic_link)
      end

      it "tells the visitor to check their inbox" do
        post session_path, params: { email: email }
        expect(flash[:notice]).to include("Check your inbox")
      end

      it "does not sign them in yet" do
        post session_path, params: { email: email }
        get root_path
        expect(response.body).to include("Sign in")
      end
    end

    context "with an address that already exists" do
      let!(:user) { create(:user, email: "returning@example.com") }

      it "creates no second account" do
        expect { post session_path, params: { email: user.email } }.not_to change(User, :count)
      end

      it "still sends a link" do
        expect { post session_path, params: { email: user.email } }
          .to have_enqueued_mail(SessionMailer, :magic_link)
      end
    end

    context "with the same address in a different case" do
      let!(:user) { create(:user, email: "Ravi@example.com") }

      it "reuses the existing account" do
        expect { post session_path, params: { email: "RAVI@EXAMPLE.COM" } }.not_to change(User, :count)
      end
    end

    context "with a malformed address" do
      before { post session_path, params: { email: "not-an-email" } }

      it "responds with unprocessable content so Turbo re-renders the form" do
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "explains what is wrong" do
        expect(response.body).to include("Email is invalid")
      end

      it "creates no account" do
        expect(User.count).to eq(0)
      end
    end
  end

  describe "GET /sign-in/:token" do
    let(:user) { create(:user) }

    context "with a valid link" do
      before { get verify_session_path(token: user.generate_token_for(:sign_in)) }

      it "redirects to where they were going" do
        expect(response).to redirect_to(root_path)
      end

      it "signs the user in" do
        get root_path
        expect(response.body).to include(user.email)
      end
    end

    context "when the same link is clicked twice" do
      before do
        token = user.generate_token_for(:sign_in)
        get verify_session_path(token: token)
        reset!
        get verify_session_path(token: token)
      end

      it "refuses the second click" do
        expect(response).to redirect_to(new_session_path)
      end

      it "explains that the link has expired" do
        expect(flash[:alert]).to include("expired")
      end
    end

    context "with a tampered token" do
      before { get verify_session_path(token: "#{user.generate_token_for(:sign_in)}x") }

      it "refuses it" do
        expect(response).to redirect_to(new_session_path)
      end
    end

    context "when the visitor was heading somewhere protected" do
      let!(:booking) { create(:booking, user: user) }

      before do
        get booking_path(booking)          # bounced to sign in, destination remembered
        get verify_session_path(token: user.generate_token_for(:sign_in))
      end

      it "returns them to the page they wanted" do
        expect(response).to redirect_to(booking_path(booking))
      end
    end
  end

  describe "DELETE /session" do
    before do
      sign_in(create(:user))
      delete session_path
    end

    it "redirects with a See Other, so Turbo follows with a GET" do
      expect(response).to have_http_status(:see_other)
    end

    it "signs the user out" do
      get root_path
      expect(response.body).to include("Sign in")
    end
  end
end
