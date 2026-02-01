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

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        http.request(req)
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

    if latest.nil?
      flash[:error] = "Could not fetch latest release (repo may have no releases, or we've hit a rate limit..)"
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

    github_projects.each do |project|
      #skip if checked recently
      if project[:last_checked_at] && project[:last_checked_at] > cutoff
        skipped += 1
        next
      end

      #Skip if repo parsing is missing
      next if project[:github_owner].blank? || project[:github_repo].blank?

      latest = fetch_github_latest_release(project[:github_owner], project[:github_repo])
      next if latest.nil?

      Projects.where(id: project[:id]).update(
        latest_release_tag: latest[:tag_name],
        latest_release_url: latest[:html_url],
        latest_release_published_at: latest[:published_at] ? Time.parse(latest[:published_at]) : nil,
        last_checked_at: Time.now,
        updated_at: Time.now
      )

      refreshed += 1
    end


    flash[:success] = "Refreshed #{refreshed} projects. Skipped (cooldown): #{skipped}"
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