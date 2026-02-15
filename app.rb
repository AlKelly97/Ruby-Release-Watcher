require "active_support/all"
require "active_support/core_ext/string/inflections"
require "sinatra"
require "sinatra/flash" 
require "sinatra/reloader" if development?

require "sequel"

require "net/http"
require "json"
require "uri"

DB = Sequel.sqlite("db/release_watcher.sqlite3")
Projects = DB[:projects]

class ReleaseWatcher < Sinatra::Base
  set :root, File.dirname(__FILE__)

  configure do
    register Sinatra::Flash
    enable :sessions
    enable :method_override
  end
  
    configure :development do
    register Sinatra::Reloader
  end

  helpers do
    
    def parse_github_repo(url)
      uri = URI(url)
      host = uri.host.to_s.downcase
        return nil unless host == "github.com" || host == "www.github.com"
      parts = uri.path.split("/").reject(&:blank?)
        return nil if parts.length < 2
      owner = parts[0]
      repo = parts[1].sub(/\.git\z/, "")
      [owner, repo]
      rescue URI::InvalidURIError
      nil
    end
    
    def fetch_github_latest_release(owner, repo)

      api_url = "https://api.github.com/repos/#{owner}/#{repo}/releases/latest"
      uri = URI(api_url)

      req = Net::HTTP::Get.new(uri)
      req["Accept"] = "application/vnd.github+json"
      req["X-GitHub-Api-Version"] = "2022-11-28"

      token = ENV["GITHUB_TOKEN"]
      req["Authorization"] = "Bearer #{token}" if token && !token.strip.empty?
      req["User-Agent"] = "Ruby-Release-Watcher"

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        http.request(req)
      end

      return :no_releases if res.code.to_i == 404

      if [403, 429].include?(res.code.to_i) && res["x-ratelimit-remaining"] == "0"
        reset_epoch = res["x-ratelimit-reset"]&.to_i
        retry_at = reset_epoch && reset_epoch > Time.now.to_i ? Time.at(reset_epoch) : nil

        retry_after = res["retry-after"]&.to_i
        retry_at = retry_after && retry_after > 0 ? (Time.now.utc + retry_after) : reset_time

        return {error: :rate_limited, retry_at: retry_at }
      end

      return nil unless res.is_a?(Net::HTTPSuccess)

      json = JSON.parse(res.body)
      {
        tag_name: json["tag_name"],
        html_url: json["html_url"],
        published_at: json["published_at"]
      }

    end

    def partial(name, locals = {})
      erb(:"_#{name}", layout: false, locals: locals)
    end

    def github_prjoject?(project)
      project[:source].to_s.downcase.strip == "github"
    end
end



  post "/projects" do
    name = params[:name]&.strip
    source = params[:source]&.strip
    url = params[:url]&.strip
    notes = params[:notes]&.strip

    if name.blank? || source.blank? || url.blank?
      flash[:error] = "All fields are required"
      redirect "/"
    end

    source_key = source.to_s.downcase.strip
    source_key = "website" unless %w[github steam website].include?(source_key)

    owner = repo = nil
    if source_key == "github"
      owner_repo = parse_github_repo(url)
      if owner_repo.nil?
        flash[:error] = "Github source requires a URL like https://github.com/owner/repo"
        redirect "/"
      end
      owner, repo = owner_repo
    end

  begin
    Projects.insert(
      name: name,
      source: source,
      source_key: source_key,
      url: url,
      notes: notes,
      github_owner: owner,
      github_repo: repo,
      created_at: Time.now,
      updated_at: Time.now
    )
  rescue Sequel::UniqueConstraintViolation
    flash[:error] = "That project is already being tracked"
    redirect "/"
  end

    flash[:success] = "Added '#{name}'"
    redirect "/"
  end

  post "/projects/:id/refresh" do
    id = params[:id].to_i
    project = Projects.where(id: id).first

    if project.nil? 
      flash[:error] = "Project not found"
      redirect to ("/")
    end

    if project[:source_key] != "github" || project[:github_owner].blank? || project[:github_repo].blank?
      flash[:error] = "Refresh is only supported for GitHub projects with valid repo info"
      redirect to ("/")
    end

    latest = fetch_github_latest_release(project[:github_owner], project[:github_repo])

   if latest.is_a?(Hash) && latest[:error] == :rate_limited
  when_text = latest[:retry_at] ? latest[:retry_at].to_s : "later"
  flash[:error] = "GitHub rate limit hit. Try again after: #{when_text}"
  redirect "/"
  end 

    case latest
    when :no_releases
      flash[:error] = "No Github releases published for this repo"
      redirect to ("/")

    when :rate_limited
      flash[:error] = "Github Rate Limit Exceeded. Please try again later"
      redirect to ("/")

    when nil
      flash[:error] = "Failed to fetch latest release (unexpected error)"
      redirect to ("/")
    end

    Projects.where(id:id).update(
      latest_release_tag: latest[:tag_name],
      latest_release_url: latest[:html_url],
      latest_release_published_at: latest[:published_at] ? Time.parse(latest[:published_at]) : nil,
      last_checked_at: Time.now,
      updated_at: Time.now
    )

    flash[:success] = "Refreshed '#{project[:name]}'"
    redirect to ("/")
  end

  post "/refresh_all" do
    cooldown_hours = 6
    cutoff = Time.now - (cooldown_hours * 60 * 60)

    github_projects = Projects.where(source_key: "github").all

    refreshed = 0
    skipped = 0
    skipped_missing_repo = 0
    no_releases = 0
    rate_limited = 0
    api_errors = 0

    github_projects.each do |project|
      #skip if checked recently
      if project[:last_checked_at] && project[:last_checked_at] > cutoff
        skipped += 1
        next
      end

      #Skip if repo parsing is missing
      if project[:github_owner].blank? || project[:github_repo].blank?
        skipped_missing_repo += 1
        next
      end

      latest = fetch_github_latest_release(project[:github_owner], project[:github_repo])

      if latest.is_a?(Hash) && latest[:error] == :rate_limited
      when_text = latest[:retry_at] ? latest[:retry_at].to_s : "later"
      flash[:error] = "GitHub rate limit hit. Try again after: #{when_text}"
      redirect "/"
      end
      
      case latest
      when :no_releases
        no_releases += 1
        next
      when :rate_limited
        rate_limited += 1
        next
      when nil
        api_errors += 1
        next
      end

      Projects.where(id: project[:id]).update(
        latest_release_tag: latest[:tag_name],
        latest_release_url: latest[:html_url],
        latest_release_published_at: latest[:published_at] ? Time.parse(latest[:published_at]) : nil,
        last_checked_at: Time.now,
        updated_at: Time.now
      )

      refreshed += 1
    end


    flash[:success] = "Refreshed #{refreshed} projects. Skipped (cooldown): #{skipped}, Skipped (missing repo): #{skipped_missing_repo}, No releases: #{no_releases}, Rate limited: #{rate_limited}, API errors: #{api_errors}"
    redirect to ("/")
    end


  delete "/projects/:id" do
    id = params[:id].to_i
    deleted = Projects.where(id: id).delete
    
    if deleted > 0 
      flash[:success] = "Deleted Project"
    else
      flash[:error] = "Project not found"
    end

    redirect "/"
  end

  get "/" do
    @title = "Release Watcher"
    @projects = Projects.order(:name).all
    erb :index
  end
end