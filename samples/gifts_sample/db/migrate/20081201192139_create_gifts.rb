class CreateGifts < ActiveRecord::Migration
  def self.up
    create_table :gifts do |t|
      t.integer :gift_name_id
      t.string :sent_by
      t.string :received_by
      t.boolean :viewed

      t.timestamps
    end
  end

  def self.down
    drop_table :gifts
  end
end
