class ApplicationController < ActionController::Base
  require 'net/nntp'
  require 'shellwords'
  protect_from_forgery
  before_filter :check_maintenance, :authenticate, :get_or_create_user
  
  private
  
    def authenticate
      if not Newsgroup.select(true).first
        @no_script = true
        render 'shared/no_groups'
      elsif not request.env[ENV_USERNAME]
        if not User.select(true).first and not params[:no_user_override]
          if DEV_MODE_ENABLED
            User.create!(:username => 'nobody', :real_name => 'Testing User')
          else
            @no_script = true
            render 'shared/no_users'
          end
        elsif not DEV_MODE_ENABLED and not params[:api_key]
          respond_to do |wants|
            wants.html { render :file => "#{Rails.root}/public/auth.html", :layout => false }
            wants.js { render 'shared/needs_auth' }
            wants.json { render :status => :unauthorized, :json => {
              :reason => 'Missing API key',
              :details => "API access requires a key to be provided in the 'api_key' parameter"
            }}
          end
        end
      end
    end
    
    def check_maintenance
      maintenance = File.exists?('tmp/maintenance.txt')
      reloading = File.exists?('tmp/reloading.txt')
      if maintenance or reloading
        @no_script = true
        @reason = if reloading
          'WebNews is re-importing all newsgroups'
        else
          'WebNews is down for maintenance'
        end
        @explanation = if reloading
          "This could take a while. (#{Newsgroup.count - 1} newsgroups completed so far, started #{File.mtime('tmp/syncing.txt').strftime(SHORT_DATE_FORMAT)})"
        else
          explain = File.read('tmp/maintenance.txt')
          if explain.blank?
            "No explanation was provided for this maintenance, but hopefully we'll be back online soon."
          else
            explain
          end
        end
        
        respond_to do |wants|
          wants.html { render 'shared/maintenance' }
          wants.js { render 'shared/maintenance' }
          wants.json { render :status => :service_unavailable, :json => {
            :reason => @reason,
            :details => @explanation.chomp
          }}
        end
      end
    end
  
    def get_or_create_user
      if params[:api_key]
        @current_user = User.find_by_api_key(params[:api_key])
        if @current_user.nil?
          render :status => :unauthorized, :json => {
            :reason => 'Invalid API key',
            :details => 'The API key you provided does not match any known user'
          }
        elsif not params[:api_agent]
          render :status => :unauthorized, :json => {
            :reason => 'Missing agent name',
            :details => "API access requires an agent name to be provided in the 'api_agent' parameter"
          }
        else
          @current_user.update_attributes(:api_last_access => Time.now, :api_last_agent => params[:api_agent])
        end
      else # Non-API access, may create the user
        @current_user = DEV_MODE_ENABLED ? User.first :
          User.find_by_username(request.env[ENV_USERNAME])
        if @current_user.nil?
          @current_user = User.create!(
            :username => request.env[ENV_USERNAME],
            :real_name => request.env[ENV_REALNAME]
          )
          @new_user = true
        else
          @old_user = true if @current_user.is_inactive?
          @current_user.touch
        end
      end
    end
    
    def get_newsgroups_for_nav
      @newsgroups = Newsgroup.all
      @newsgroups_writable = @newsgroups.select{ |n| n.posting_allowed? }
      @newsgroups_readonly = @newsgroups.select{ |n| not n.posting_allowed? and not n.is_control? }
      @newsgroups_control = @newsgroups.select{ |n| n.is_control? }
    end
    
    def get_newsgroups_for_search
      @newsgroups = Newsgroup.unscoped.order('status DESC, name')
    end
    
    def get_newsgroups_for_posting
      @newsgroups = Newsgroup.where_posting_allowed
    end
    
    def get_newsgroup
      if params[:newsgroup]
        @newsgroup = Newsgroup.find_by_name(params[:newsgroup])
      end
    end
    
    def get_post
      if params[:newsgroup] and params[:number]
        @post = Post.where(:number => params[:number], :newsgroup => params[:newsgroup]).first
      end
    end
    
    def get_next_unread_post
      unread_order = "CASE unread_post_entries.user_created WHEN #{Post.sanitize(true)} THEN 2 ELSE 1 END"
      standard_order = 'newsgroup, date'
      
      if @post and @current_user.thread_mode == :normal
        order = "#{unread_order},
        CASE newsgroup WHEN #{Post.sanitize(@post.newsgroup.name)} THEN 1 ELSE 2 END,
        CASE thread_id WHEN #{Post.sanitize(@post.thread_id)} THEN 1 ELSE 2 END,
        CASE parent_id WHEN #{Post.sanitize(@post.message_id)} THEN 1 ELSE 2 END,
        CASE parent_id WHEN #{Post.sanitize(@post.parent_id)} THEN 1 ELSE 2 END, #{standard_order}"
      elsif @post and @current_user.thread_mode == :hybrid
        order = "#{unread_order},
        CASE newsgroup WHEN #{Post.sanitize(@post.newsgroup.name)} THEN 1 ELSE 2 END,
        CASE thread_id WHEN #{Post.sanitize(@post.thread_id)} THEN 1 ELSE 2 END, #{standard_order}"
      elsif @newsgroup
        order = "#{unread_order},
          CASE newsgroup WHEN #{Post.sanitize(@newsgroup.name)} THEN 1 ELSE 2 END, #{standard_order}"
      else
        order = "#{unread_order}, #{standard_order}"
      end
      
      @next_unread_post = @current_user.unread_posts.order(order).first
    end
    
    def form_error(error_text)
      render :partial => 'shared/form_error', :object => error_text
    end
end
