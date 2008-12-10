module GiftsHelper
  def gift_viewed?(gift)
    if !gift.viewed
      gift.viewed = true
      gift.save
      
      return "<span class='new'>New</span>"
    end
  end
end
