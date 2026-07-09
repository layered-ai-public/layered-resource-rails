class AddStatusAndFeaturedToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :status, :integer, default: 0, null: false
    add_column :posts, :featured, :boolean, default: false, null: false
  end
end
