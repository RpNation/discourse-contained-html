# frozen_string_literal: true

RSpec.describe ContainedHtml::RenderController do
  describe "#create" do
    before { SiteSetting.contained_html_enabled = true }

    it "returns a private JSON document for an anonymous reader" do
      post "/contained-html/render.json",
           params: {
             source: "<p>A character profile</p>",
           },
           as: :json

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("application/json")
      expect(response.headers["Cache-Control"]).to include("no-store")
      document = Nokogiri.HTML5(response.parsed_body.fetch("document"))
      expect(document.at_css("p").text).to eq("A character profile")
      expect(document.at_css('meta[http-equiv="Content-Security-Policy"]')).to be_present
    end

    it "returns the same rendering policy for a signed-in author and an anonymous reader" do
      source = '<p onclick="alert(1)">A character profile</p><script>alert(2)</script>'
      post "/contained-html/render.json", params: { source: source }, as: :json
      reader_document = response.parsed_body.fetch("document")

      sign_in(Fabricate(:user))
      post "/contained-html/render.json", params: { source: source }, as: :json

      expect(response.status).to eq(200)
      expect(response.parsed_body.fetch("document")).to eq(reader_document)
    end

    it "rejects requests while the plugin is disabled" do
      SiteSetting.contained_html_enabled = false

      post "/contained-html/render.json", params: { source: "<p>Hidden</p>" }, as: :json

      expect(response.status).to eq(404)
    end

    it "accepts a bounded frame height without enabling child scripts" do
      post "/contained-html/render.json",
           params: {
             source: "<!-- layout-height: 600 --><p>A complete card</p>",
           },
           as: :json

      expect(response.parsed_body["height"]).to eq(600)
      expect(response.parsed_body["document"]).to include("script-src 'none'")
    end

    it "uses the default height for oversized, malformed or misplaced hints" do
      %w[199 1601 999999999 600px 600;position:fixed].each do |height|
        post "/contained-html/render.json",
             params: {
               source: "<!-- layout-height: #{height} --><p>Card</p>",
             },
             as: :json
        expect(response.parsed_body["height"]).to eq(480)
      end
      post "/contained-html/render.json",
           params: {
             source: "<p>Text</p><!-- layout-height: 600 -->",
           },
           as: :json
      expect(response.parsed_body["height"]).to eq(480)
    end

    it "requires a string source within the byte limit" do
      [nil, { html: "<p>Nested</p>" }, ["<p>Array</p>"], "x" * (256 * 1024 + 1)].each do |source|
        post "/contained-html/render.json", params: { source: source }, as: :json

        expect(response.status).to eq(400)
      end
    end

    it "rejects oversized requests before parsing the document" do
      post "/contained-html/render.json", params: { source: "x" * (2 * 1024 * 1024) }, as: :json

      expect(response.status).to eq(413)
    end

    it "accepts only JSON input" do
      post "/contained-html/render.json", params: { source: "<p>Form input</p>" }

      expect(response.status).to eq(415)
    end

    it "preserves the site's login requirement" do
      SiteSetting.login_required = true

      post "/contained-html/render.json", params: { source: "<p>Private site</p>" }, as: :json

      expect(response.status).to eq(403)
    end

    it "requires the normal CSRF token for anonymous rendering" do
      ActionController::Base.allow_forgery_protection = true

      post "/contained-html/render.json", params: { source: "<p>Preview</p>" }, as: :json
      expect(response.status).to eq(403)

      get "/session/csrf.json"
      csrf_token = response.parsed_body.fetch("csrf")
      post "/contained-html/render.json",
           params: {
             source: "<p>Preview</p>",
           },
           headers: {
             "X-CSRF-Token" => csrf_token,
           },
           as: :json
      expect(response.status).to eq(200)
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    it "limits anonymous rendering requests by IP" do
      RateLimiter.enable

      stub_const(described_class, :REQUESTS_PER_MINUTE, 2) do
        2.times do
          post "/contained-html/render.json", params: { source: "<p>Preview</p>" }, as: :json
          expect(response.status).to eq(200)
        end

        post "/contained-html/render.json", params: { source: "<p>Preview</p>" }, as: :json
        expect(response.status).to eq(429)
      end
    end

    it "limits signed-in authors even when their IP changes" do
      admin = Fabricate(:admin)
      sign_in(admin)
      RateLimiter.enable

      stub_const(described_class, :REQUESTS_PER_MINUTE, 1) do
        post "/contained-html/render.json",
             params: {
               source: "<p>First preview</p>",
             },
             headers: {
               "REMOTE_ADDR" => "192.0.2.1",
             },
             as: :json
        expect(response.status).to eq(200)

        post "/contained-html/render.json",
             params: {
               source: "<p>Second preview</p>",
             },
             headers: {
               "REMOTE_ADDR" => "192.0.2.2",
             },
             as: :json
        expect(response.status).to eq(429)
      end
    end
  end
end
