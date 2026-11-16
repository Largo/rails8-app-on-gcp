# frozen_string_literal: true

require_relative "app"

WorkshopHive::App.start_crunching! unless ENV["RACK_ENV"] == "test"
run WorkshopHive::App
