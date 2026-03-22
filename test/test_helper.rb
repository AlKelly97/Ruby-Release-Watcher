ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"

require_relative "../app"

require_relative "../db/setup"

module TestHelpers
    def app
        ReleaseWatcher
    end

    def setup
        DB[:projects].delete
    end
end

class Minitest::Test
    include Rack::Test::Methods
    include TestHelpers
end