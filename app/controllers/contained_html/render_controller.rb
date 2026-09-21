# frozen_string_literal: true

class ContainedHtml::RenderController < ::ApplicationController
  MAX_SOURCE_BYTES = 256 * 1024
  MAX_REQUEST_BYTES = 2 * 1024 * 1024
  REQUESTS_PER_MINUTE = 60

  requires_plugin ContainedHtml::PLUGIN_NAME

  prepend_before_action :check_request_size
  before_action :check_json_request

  def create
    raise Discourse::NotFound unless SiteSetting.contained_html_enabled

    source = params[:source]
    unless source.is_a?(String) && source.bytesize <= MAX_SOURCE_BYTES
      raise Discourse::InvalidParameters, :source
    end

    RateLimiter.new(
      nil,
      "contained-html-ip-#{request.remote_ip}",
      REQUESTS_PER_MINUTE,
      1.minute,
    ).performed!
    if current_user
      RateLimiter.new(
        current_user,
        "contained-html-render",
        REQUESTS_PER_MINUTE,
        1.minute,
        apply_limit_to_staff: true,
      ).performed!
    end

    response.headers["Cache-Control"] = "no-store"
    render json: { document: ContainedHtml::Sanitizer.render(source), height: frame_height(source) }
  rescue ContainedHtml::Sanitizer::InvalidSource
    raise Discourse::InvalidParameters, :source
  end

  private

  def frame_height(source)
    requested = source[/\A\s*<!--\s*layout-height:\s*(\d{3,4})\s*-->/, 1].to_i
    requested.between?(200, 1600) ? requested : 480
  end

  def check_request_size
    return head :payload_too_large if request.content_length.to_i > MAX_REQUEST_BYTES

    body = request.body
    body.rewind
    oversized = body.read(MAX_REQUEST_BYTES + 1).bytesize > MAX_REQUEST_BYTES
    body.rewind
    head :payload_too_large if oversized
  end

  def check_json_request
    head :unsupported_media_type unless request.media_type == "application/json"
  end
end
