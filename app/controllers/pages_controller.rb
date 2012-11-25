class PagesController < ApplicationController
  before_filter :get_newsgroups_for_nav, :only => [:home, :check_new]
  before_filter :get_newsgroup, :only => :check_new
  before_filter :get_post, :only => :check_new

  def home
    if params[:no_user_override]
      redirect_to root_path and return
    end
    
    respond_to do |wants|
      
      wants.html do
        if request.env[ENV_REALNAME]
          @current_user.real_name = request.env[ENV_REALNAME]
          @current_user.save!
        end
        cronless_sync_all
        get_last_sync_time
        get_next_unread_post
      end
      
      wants.js do
        get_activity_feed
        get_next_unread_post
      end
      
      wants.json do
        get_activity_feed
        render :json => { :activity => @activity }
      end
      
    end
  end
  
  def about
    render 'shared/dialog'
  end
  
  def new_user
    render 'shared/dialog'
  end
  
  def old_user
    render 'shared/dialog'
  end
  
  def rss_caution
    render 'shared/dialog'
  end
  
  def check_new
    cronless_sync_all
    get_last_sync_time
    get_next_unread_post
    if params[:location] == '#!/home'
      @dashboard_active = true
      get_activity_feed
    end
  end
  
  private
    
    def get_activity_feed
      included_newsgroups = Newsgroup.pluck(:name).reject{ |name| name =~ ACTIVITY_EXCLUDE }
      newest_in_stickies = Post.sticky.map{ |post| post.all_in_thread.order('date').last }
      newest_in_threads = Post.where(:newsgroup => included_newsgroups).
        where('date > ?', 1.month.ago).order('date DESC').uniq_by(&:thread_id)[0...20]
      activity_posts = newest_in_stickies | newest_in_threads
      
      @activity = activity_posts.map do |post|
        thread_parent = post.thread_parent
        unread_count = thread_parent.unread_count_in_thread_for_user(@current_user)
        {
          :thread_parent => thread_parent,
          :newest_post => post,
          :cross_posted => post.crossposted?(true),
          :next_unread => @current_user.unread_posts.where(:thread_id => post.thread_id).order('date').first,
          :post_count => thread_parent.post_count_in_thread,
          :unread_count => unread_count,
          :personal_class => if unread_count > 0
            thread_parent.unread_personal_class_for_user(@current_user)
          else
            thread_parent.personal_class_for_user(@current_user)
          end
        }
      end
    end
end
