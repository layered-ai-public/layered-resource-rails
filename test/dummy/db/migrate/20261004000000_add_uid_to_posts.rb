class AddUidToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :uid, :string
    add_index :posts, :uid, unique: true

    reversible do |dir|
      dir.up do
        select_values("SELECT id FROM posts WHERE uid IS NULL").each do |id|
          execute "UPDATE posts SET uid = #{quote(SecureRandom.base58(24))} WHERE id = #{id.to_i}"
        end
      end
    end
  end
end
