require "sequel"

DB  = Sequel.sqlite("db/release_watcher.sqlite3")

DB.create_table? :projects do
    primary_key :id
    String :name, null: false
    String :source, null: false
    String :url, null: false
    String :github_owner
    String :github_repo

    String :latest_release_tag
    String :latest_release_url
    DateTime :latest_release_published_at

    DateTime :created_at
    DateTime :updated_at
end

puts "DB Ready!"