require "sequel"

DB = Sequel.sqlite("db/release_watcher.sqlite3")

DB.alter_table :projects do
    add_column :source_key, String
    add_column :notes, String
    add_column :last_checked_at, DateTime unless DB[:projects].columns.include? (:last_checked_at)
end

puts "Added source_key, notes and last_checked_at if missing. But this was already added in a previous migration. Adding again 
for demonstration purposes."
