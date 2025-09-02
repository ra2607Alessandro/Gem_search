require 'rails_helper'

RSpec.describe "Searches", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/searches/index"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /create" do
    it "returns http success" do
      get "/searches/create"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/searches/show"
      expect(response).to have_http_status(:success)
    end
  end

end
