# frozen_string_literal: true

ContainedHtml::Engine.routes.draw do
  post "/render" => "render#create", :defaults => { format: :json }
end
