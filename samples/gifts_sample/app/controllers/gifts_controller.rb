class GiftsController < ApplicationController
  include OpenSocial::Auth
  
  # Declares the keys for your app on different containers. The index is the
  # incoming consumer key sent in the signed makeRequest from the gadget.
  # These are sample gadget credentials and should be replaced with the HMAC
  # keys granted to your own gadget.
  KEYS = {
    '649048920060' => {
      :secret => '2rKmqUigMbFqK783szqzzOky',
      :outgoing_key => 'orkut.com:649048920060',
      :container => OpenSocial::Connection::ORKUT
    },
    'http://opensocial-resources.googlecode.com/svn/samples/rest_rpc/sample.xml' => {
      :secret => '6a838d107daf4d09b7d446422f5e7a81',
      :outgoing_key => 'http://opensocial-resources.googlecode.com/svn/samples/rest_rpc/sample.xml',
      :container => OpenSocial::Connection::MYSPACE
    }
  }
  
  # Declares where your application lives. Points to the page where users are
  # redirected after loading the iframe.
  SERVER = 'http://example.com/iframe'
  
  # Controls the auto-validation of the signed makeRequest.
  before_filter :check_signature, :only => [:iframe]
  
  # Renders pages with boilerplate HTML/CSS/JS.
  layout 'default'
  
  # Implicitly checks the signature of the incoming request and saves the
  # owner id, viewer id, and consumer key in a temporary session for later use.
  # The session id is returned as an iframe snippet that the gadget can use to
  # render the app.
  def iframe
    session[:id] = params[:opensocial_owner_id]
    session[:viewer] = params[:opensocial_viewer_id]
    session[:consumer_key] = params[:oauth_consumer_key]
    render :text => "<iframe width='98%' height='600px' frameborder='0' src='#{SERVER}?sessid=#{session.model.session_id}' />"
  end
  
  # Loads the temporary session referenced by sessid, copies the values into
  # a persistent session that will be used to actually drive the app, and
  # deletes the temporary session (to prevent replay). Then, initiates a
  # connection to the given container and renders the appropriate content.
  def index
    proxied_session = session.model.class.find(:first,
                        :conditions => ['session_id = ?', params[:sessid]])
                        
    if params[:sessid] && proxied_session
      session[:id] = proxied_session.data[:id]
      session[:viewer] = proxied_session.data[:viewer]
      session[:consumer_key] = proxied_session.data[:consumer_key]
      proxied_session.destroy
    end
    
    c = OpenSocial::Connection.new(:container => KEYS[session[:consumer_key]][:container],
                                   :consumer_key => KEYS[session[:consumer_key]][:outgoing_key],
                                   :consumer_secret => KEYS[session[:consumer_key]][:secret],
                                   :xoauth_requestor_id => session[:id])
    
    if session[:id] == session[:viewer]
      render_owner(c)
    elsif session[:viewer] && session[:id] != session[:viewer]
      render_viewer_with_app(c)
    else
      render_viewer_without_app(c)
    end
  end
  
  # Sends a gift on behalf of the viewer. If the viewer is the owner, the gift
  # is sent to the selected friend (but doesn't check to confirm that the owner
  # is friends with the specified ID). If the viewer is not the owner, the gift
  # is sent to the owner. Then the app redirects to the index.
  def give
    gift = Gift.new(params[:gift])
    if session[:id] != session[:viewer]
      gift.sent_by = session[:viewer]
      gift.received_by = session[:id]
    else
      gift.sent_by = session[:id]
    end
    
    if gift.save
      redirect_to :action => :index
    else
      flash[:error] = 'Error giving gift.'
      redirect_to :action => :index
    end
  end
  
  private
  
  # If the viewer is also the owner, this will render the list of gifts the
  # owner has sent or received. The owner can elect to send a gift to a friend.
  def render_owner(c)
    @id = session[:id]
    @gifts = Gift.find(:all,
                       :conditions => ['sent_by = ? OR received_by = ?', @id, @id],
                       :order => 'created_at DESC', :limit => 10)
    @gift_names = GiftName.find(:all)
    
    @people = fetch_gift_givers_and_friends(@id, @gifts, c)
    @owner = @people.delete(@id)
    
    render :action => "owner"
  end
  
  # If the viewer has the app installed, this will render the list of gifts
  # exchanged between the owner and viewer. The viewer can elect to send a gift
  # to the owner.
  def render_viewer_with_app(c)
    @id = session[:viewer]
    @owner_id = session[:id]
    
    @gifts = Gift.find(:all,
                       :conditions => ['(sent_by = ? AND received_by = ?) OR ' +
                                       '(sent_by = ? AND received_by = ?)',
                                       @owner_id, @id, @id, @owner_id],
                       :order => 'created_at DESC', :limit => 10)
    @gift_names = GiftName.find(:all)
    
    @viewer = OpenSocial::FetchPersonRequest.new(c, @id).send
    @owner = OpenSocial::FetchPersonRequest.new(c).send
    
    render :action => "viewer_with_app"
  end
  
  # If the viewer doesn't have the app installed, this will render the list of
  # gifts the owner has sent or received (without notes). No gifts may be sent.
  def render_viewer_without_app(c)
    @id = session[:id]
    @gifts = Gift.find(:all,
                       :conditions => ['sent_by = ? OR received_by = ?', @id, @id],
                       :order => 'created_at DESC', :limit => 10)
    @gift_names = GiftName.find(:all)
    
    @people = fetch_gift_givers_and_friends(@id, @gifts, c)
    
    render :action => "viewer_without_app"
  end
  
  # Requests social data for each of the people that have sent or received a
  # gift from the owner (oid). The method first generates a unique list of
  # user ids from the list of gifts, and sends a REST request for their data.
  # Users without the app installed will trigger an exception which is caught.
  # Finally, the owner's friends are fetched (which fills in the missing spaces
  # where insufficient permissions are granted to collect the user data
  # directly) and merged with the existing data.
  # This function could be sped up considerably by using a single RPC request
  # if the container supports it.
  def fetch_gift_givers_and_friends(oid, gifts, c)
    people = {}
    ids = gifts.collect {|g| [g.sent_by, g.received_by]}.flatten.uniq
    ids.each do |id|
      begin
        r = OpenSocial::FetchPersonRequest.new(c, id)
        people[id] = r.send
      rescue OpenSocial::AuthException
      end
    end
    friends = OpenSocial::FetchPeopleRequest.new(c, oid).send
    return people.merge(friends)
  end
  
  # Looks up the consumer secret paired with the given consumer key and
  # hands them off to the client library authentication.
  def check_signature
    key = params[:oauth_consumer_key]
    unless validate(key, KEYS[key][:secret])
      render :text => '401 Unauthorized', :status => :unauthorized
    end
  end
end