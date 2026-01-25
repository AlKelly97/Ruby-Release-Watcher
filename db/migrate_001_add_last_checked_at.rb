require "sequel"

DB = Sequel.sqlite("db/release_watcher.sqlite3")

DB.alter_table :projects do
    add_column :last_checked_at, DateTime
end

puts "Added last_checked_at"