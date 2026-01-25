require "sequel"

DB = Sequel.sqlite("db/release_watcher.sqlite3")
projects = DB[:projects]

projects.all.each do |p|
  raw = p[:source].to_s.downcase.strip

    key = 
        case raw
        when "github" then "github"
        when "steam" then "steam"
        else "website"
        end

    projects.where(id: p[:id]).update(source_key: key)
end

puts "Backfilled source_key"
