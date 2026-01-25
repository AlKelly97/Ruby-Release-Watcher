require "sequel"

DB = Sequel.sqlite("db/release_watcher.sqlite3")

DB.alter_table :projects do
    add_index :url, unique: true
end

puts "Added UNIQUE index on url"