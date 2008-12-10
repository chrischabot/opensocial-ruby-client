class Gift < ActiveRecord::Base
  belongs_to :gift_name
  
  validates_presence_of :sent_by, :received_by, :gift_name_id
  
  protected
  
  def validate
    errors.add_to_base("You cannot send gifts to yourself.") unless sent_by != received_by
  end
end
