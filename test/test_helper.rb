ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"

require_relative "../app"

module TestHelpers
    def app
        ReleaseWatcher
    end
end

class Minitest::Test
    include Rack::Test::Methods
    include TestHelpers
end