ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"

require_relative "../app"

require_relative "../db/setup"

Dir.glob("db/migrate_*.rb").sort.each { |file| require_relative "../#{file}" }


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