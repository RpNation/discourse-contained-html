# frozen_string_literal: true

# name: discourse-contained-html
# about: Experimental isolated, script-free HTML post layouts
# version: 0.1.0
# authors: RpNation
# url: https://github.com/RpNation/discourse-contained-html

enabled_site_setting :contained_html_enabled

register_asset "stylesheets/common/contained-html.scss"

module ::ContainedHtml
  PLUGIN_NAME = "discourse-contained-html"

  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace ContainedHtml
  end
end

require_relative "lib/contained_html/sanitizer"

after_initialize do
  Discourse::Application.routes.append { mount ::ContainedHtml::Engine, at: "/contained-html" }
  Rails.application.config.filter_parameters += [:source]
end
