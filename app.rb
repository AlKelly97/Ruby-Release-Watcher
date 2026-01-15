require "active_support/all"
require "active_support/core_ext/string/inflections"
require "sinatra"
require "sinatra/flash" 
require "sinatra/reloader" if development?

class ReleaseWatcher < Sinatra::Base
  configure do
    register Sinatra::Flash
  end
  
    configure :development do
    register Sinatra::Reloader
  end

  @@projects = [
    { name: "Ghost of Yotei", source: "Sucker Punch", url: "https://www.playstation.com/en-ie/games/ghost-of-yotei/" },
    { name: "DayZ", source: "Bohemia Interactive", url: "https://dayz.com/" },
    { name: "Ghost of Tsushima", source: "Sucker Punch", url: "https://www.playstation.com/en-ie/games/ghost-of-tsushima/" },
    { name: "Cyberpunk 2077", source: "CD Projekt Red", url: "https://www.cyberpunk.net/" }
  ]

  enable :sessions
  enable :method_override

  post "/projects" do
    name = params[:name]&.strip
    source = params[:source]&.strip
    url = params[:url]&.strip

    if name.blank? || source.blank? || url.blank?
      flash[:error] = "All fields are required"
      redirect "/"
    elsif @@projects.any? { |p| p[:name] == name }
      flash[:error] = "Project already exists"
      redirect "/"
    else
      @@projects << { name: name, source: source, url: url }
      flash[:success] = "Added '#{name}'"
      redirect "/"
    end
  end

  delete "/projects/:id" do
    id = params[:id]
    original_count = @@projects.length

    @@projects.delete_if { |p| p[:name].parameterize == id }

    if @@projects.length < original_count
      flash[:success] = "Deleted Project"
    else
      flash[:error] = "Project not found"
    end

    redirect "/"
  end

  get "/" do
    @projects = @@projects
    erb :index
  end
end