require_relative "test_helper"

class AppTest < Minitest::Test
    def test_homepage_loads
        get "/"
        assert last_response.ok?, "Expected GET / to be 200 OK, got #{last_response.status}"
    end

    def test_add_project_requires_all_fields
        post "/projects", {name: "" , source: "github", url: ""}

        assert_equal 302, last_response.status, "Expected redirect when fields are missing" 
        
        follow_redirect!

        assert_includes last_response.body, "All fields are required"
    end 

    def test_add_project_rejects_non_GH_url_when_source_is_GH
        post "/projects", { name: "BadGH", source: "github", url: "https://example.com/foo/bar" }

        assert_equal 302, last_response.status, "Expected rediret on invalid Github URL" 
        
        follow_redirect!

        assert(
            last_response.body.include?("Github source requires a URL like"),
            "Expected error message about invalid GitHub URL"
        )
    end

    def test_add_project_accepts_valid_GH_repo_URL
        post "/projects", { name: "GoodGH", source: "github", url: "https://github.com/sinatra/sinatra" }

        assert_equal 302, last_response.status, "Expected redirect after successful project addition" 
        
        follow_redirect!

        assert_includes last_response.body, "Added"
    end

    def test_refresh_non_GH_project_failure
        post "/projects", { name: "NonGH", source: "website", url: "https://example.com" }
        follow_redirect!

        project = DB[:projects].where(name: "NonGH").first
        refute_nil project, "Expected project to be created in DB"

        post "/projects/#{project[:id]}/refresh"

        assert_equal 302, last_response.status, "Expected redirect when refreshing non-GH project"
        follow_redirect!

        assert_includes last_response.body, "Refresh is only supported for GitHub projects with valid repo info"
    end
end
